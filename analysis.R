library(cmdstanr)
library(posterior)
library(dplyr)
library(tidyr)
library(ggplot2)
library(cowplot)

source("plotting.R")
plot_font <- plotting_font_family()
if (!interactive()) options(device = plotting_pdf_device())

set.seed(2026)

# -------------------------------------------------------------------------
# 1. Simulate realistic poster judging data
# -------------------------------------------------------------------------
P <- 18   # 18 posters
J <- 10   # 10 judges

# True latent poster qualities on (0, 1)
true_theta <- matrix(runif(P * 2, 0.25, 0.88), nrow = P, ncol = 2)
true_eta   <- qlogis(true_theta)

# Correlated judge effects (rho = 0.75)
tau_true   <- c(0.65, 0.55)
rho_true   <- 0.75
Sigma_true <- diag(tau_true) %*% matrix(c(1, rho_true, rho_true, 1), 2, 2) %*% diag(tau_true)
L_true     <- chol(Sigma_true)
true_b     <- matrix(rnorm(J * 2), nrow = J, ncol = 2) %*% L_true

# Make Judge 1 very harsh ("hawk") and Judge 2 very lenient ("dove")
true_b[1, ] <- c(-1.1, -0.9)
true_b[2, ] <- c(+1.0, +0.9)

phi_true <- c(18, 22)

# Sparse assignment: each poster rated by 3 to 4 judges
eval_list <- list()
for (p in 1:P) {
  assigned_judges <- sample(1:J, size = sample(3:4, 1), replace = FALSE)
  for (j in assigned_judges) {
    mu_sci  <- plogis(true_eta[p, 1] + true_b[j, 1])
    mu_pres <- plogis(true_eta[p, 2] + true_b[j, 2])
    
    y_star_sci  <- rbeta(1, mu_sci * phi_true[1], (1 - mu_sci) * phi_true[1])
    y_star_pres <- rbeta(1, mu_pres * phi_true[2], (1 - mu_pres) * phi_true[2])
    
    eval_list[[length(eval_list) + 1]] <- data.frame(
      poster_id = p,
      judge_id = j,
      science_score = ceiling(10 * y_star_sci),
      presentation_score = ceiling(10 * y_star_pres)
    )
  }
}
df <- bind_rows(eval_list)

# -------------------------------------------------------------------------
# 2. Compile and fit the Stan model
# -------------------------------------------------------------------------
mod <- cmdstan_model("rating_model/rating_model.stan")

stan_data <- list(
  N = nrow(df),
  P = P,
  J = J,
  poster_id = df$poster_id,
  judge_id = df$judge_id,
  science_score = ifelse(is.na(df$science_score), -1L, as.integer(df$science_score)),
  presentation_score = ifelse(is.na(df$presentation_score), -1L, as.integer(df$presentation_score))
)

output_dir <- "outputs"
if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) {
  stop("Could not create output directory: ", output_dir)
}

fit <- mod$sample(
  data = stan_data,
  output_dir = output_dir,
  seed = 2026,
  chains = 4,
  parallel_chains = 4,
  iter_warmup = 1000,
  iter_sampling = 1500,
  adapt_delta = 0.95
)

# Quick diagnostic check on hyperparameters
print(fit$summary(variables = c("tau", "rho_judge", "phi")))

# -------------------------------------------------------------------------
# 3. Summarize posterior expectations and Pr(Poster is Best)
# -------------------------------------------------------------------------
obs_summary <- df %>%
  mutate(obs_mean = (science_score + presentation_score) / 2) %>%
  group_by(poster_id) %>%
  summarise(
    n_judges = n(),
    raw_mean_score = mean(obs_mean, na.rm = TRUE),
    raw_se_score   = sd(obs_mean, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  )

post_exp <- fit$summary(
  variables = "exp_mean",
  mean, median,
  ~quantile(.x, probs = c(0.05, 0.25, 0.75, 0.95))
) %>%
  mutate(poster_id = as.integer(gsub("exp_mean\\[|\\]", "", variable))) %>%
  rename(
    adj_mean = mean,
    adj_median = median,
    q05 = `5%`,
    q25 = `25%`,
    q75 = `75%`,
    q95 = `95%`
  )

post_best <- fit$summary(variables = "is_best", prob_best = mean) %>%
  mutate(poster_id = as.integer(gsub("is_best\\[|\\]", "", variable))) %>%
  select(poster_id, prob_best)

plot_df <- obs_summary %>%
  left_join(post_exp, by = "poster_id") %>%
  left_join(post_best, by = "poster_id") %>%
  mutate(
    poster_label = factor(
      sprintf("Poster %02d (n=%d)", poster_id, n_judges),
      levels = sprintf("Poster %02d (n=%d)", poster_id[order(adj_mean)], n_judges[order(adj_mean)])
    ),
    shift = adj_mean - raw_mean_score
  )

# -------------------------------------------------------------------------
# 4. Classical aesthetic two-panel plot using ggplot2 + cowplot
# -------------------------------------------------------------------------
# Panel A: Observed Raw Mean vs. Judge-Adjusted Posterior Mean (1-10 scale)
p_scores <- ggplot(plot_df, aes(y = poster_label)) +
  # Dashed connector showing direction & magnitude of judge-bias adjustment
  geom_segment(
    aes(x = raw_mean_score, xend = adj_mean, yend = poster_label),
    color = "grey55", linetype = "dotted", linewidth = 0.6
  ) +
  # 90% Posterior Credible Interval (thin line)
  geom_errorbarh(
    aes(xmin = q05, xmax = q95),
    height = 0, linewidth = 0.55, color = "#1B365D"
  ) +
  # 50% Posterior Credible Interval (thick bar)
  geom_errorbarh(
    aes(xmin = q25, xmax = q75),
    height = 0, linewidth = 1.6, color = "#1B365D"
  ) +
  # Raw observed mean (open circle)
  geom_point(
    aes(x = raw_mean_score, shape = "Observed raw mean"),
    size = 2.6, fill = "white", color = "black", stroke = 0.9
  ) +
  # Posterior expected average | judge = 0 (filled circle)
  geom_point(
    aes(x = adj_mean, shape = "Adjusted posterior mean"),
    size = 2.8, fill = "#1B365D", color = "#1B365D"
  ) +
  scale_shape_manual(
    name = NULL,
    values = c("Observed raw mean" = 21, "Adjusted posterior mean" = 16)
  ) +
  scale_x_continuous(
    limits = c(1, 10),
    breaks = 1:10,
    expand = expansion(mult = c(0.02, 0.03))
  ) +
  labs(
    x = "Average Score (Science and Presentation, 1–10 Scale)",
    y = NULL,
    title = "A. Judge-Adjusted Posterior Score vs. Raw Mean",
    subtitle = "Thick & thin bars show 50% and 90% credible intervals (given average judge)"
  ) +
  theme_clean(plot_font) +
  theme(
    plot.subtitle = element_text(color = "grey30"),
    axis.line.y = element_line(color = "black", linewidth = 0.5),
    axis.line.x = element_line(color = "black", linewidth = 0.5),
    panel.grid.major.x = element_line(color = "grey92", linewidth = 0.4),
    legend.position = c(0.24, 0.10),
    legend.background = element_rect(fill = "white", color = "grey80", linewidth = 0.3),
    legend.margin = margin(3, 6, 3, 6)
  )

# Panel B: Pr(Poster is Best | Judge Effect = 0)
p_best <- ggplot(plot_df, aes(x = prob_best, y = poster_label)) +
  geom_col(width = 0.62, fill = "#2C5E4F", color = "black", linewidth = 0.3) +
  geom_text(
    aes(label = ifelse(prob_best >= 0.01, sprintf("%.1f%%", 100 * prob_best), "")),
    hjust = -0.18, size = 3.1, family = plot_font, color = "black"
  ) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, max(plot_df$prob_best) * 1.22),
    expand = expansion(mult = c(0, 0.02))
  ) +
  labs(
    x = "Pr(Best Poster | Judge = 0)",
    y = NULL,
    title = "B. Posterior Probability of Rank #1",
    subtitle = "Share of posterior draws with highest average"
  ) +
  theme_clean(plot_font) +
  theme(
    plot.subtitle = element_text(color = "grey30"),
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank(),
    axis.line.y = element_blank(),
    panel.grid.major.x = element_line(color = "grey92", linewidth = 0.4)
  )

# Combine with cowplot
final_plot <- plot_grid(
  p_scores, p_best,
  ncol = 2,
  align = "h",
  axis = "tb",
  rel_widths = c(1.55, 1)
)

print(final_plot)