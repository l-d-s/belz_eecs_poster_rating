library(cmdstanr)
library(posterior)
library(dplyr)
library(tidyr)
library(ggplot2)
library(cowplot)

set.seed(2026)

# -------------------------------------------------------------------------
# 1. Load real poster judging data
# -------------------------------------------------------------------------
raw_data <- read.csv("input_data/ecss-raw-scores-2026-11-17.csv", stringsAsFactors = FALSE)

cat("Data loaded from: input_data/ecss-raw-scores-2026-11-17.csv\n")
cat("Total evaluations:", nrow(raw_data), "\n")
cat("Unique posters:", n_distinct(raw_data$poster_id), "\n")
cat("Unique judges:", n_distinct(raw_data$judge_id), "\n\n")

# Create mappings from string IDs to integers
poster_map <- tibble(
  poster_id = unique(raw_data$poster_id),
  poster_id_int = seq_along(unique(raw_data$poster_id))
)

judge_map <- tibble(
  judge_id = unique(raw_data$judge_id),
  judge_id_int = seq_along(unique(raw_data$judge_id))
)

P <- nrow(poster_map)   # Number of posters
J <- nrow(judge_map)    # Number of judges

cat("Number of posters (P):", P, "\n")
cat("Number of judges (J):", J, "\n\n")

# Prepare data for Stan
eval_df <- raw_data %>%
  left_join(poster_map, by = "poster_id") %>%
  left_join(judge_map, by = "judge_id") %>%
  select(
    poster_id = poster_id_int,
    judge_id = judge_id_int,
    science_score,
    presentation_score
  ) %>%
  mutate(
    science_score = as.integer(science_score),
    presentation_score = as.integer(presentation_score)
  )

# Save poster metadata for later visualization
poster_info <- raw_data %>%
  left_join(poster_map, by = "poster_id") %>%
  select(poster_id_int, poster_code = poster_id, poster_title, author) %>%
  distinct() %>%
  rename(poster_id = poster_id_int)

# -------------------------------------------------------------------------
# 2. Compile and fit the Stan model
# -------------------------------------------------------------------------
cat("Compiling Stan model...\n")
mod <- cmdstan_model("rating_model/rating_model.stan")

stan_data <- list(
  N = nrow(eval_df),
  P = P,
  J = J,
  poster_id = eval_df$poster_id,
  judge_id = eval_df$judge_id,
  science_score = eval_df$science_score,
  presentation_score = eval_df$presentation_score
)

cat("Fitting model with", stan_data$N, "observations...\n")
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
  adapt_delta = 0.95,
  refresh = 0
)

# Quick diagnostic check on hyperparameters
cat("\n========== Model Summary (Hyperparameters) ==========\n")
print(fit$summary(variables = c("tau", "rho_judge", "phi")))

# -------------------------------------------------------------------------
# 3. Summarize posterior expectations and Pr(Poster is Best)
# -------------------------------------------------------------------------
obs_summary <- eval_df %>%
  mutate(obs_sum = science_score + presentation_score) %>%
  group_by(poster_id) %>%
  summarise(
    n_judges = n(),
    raw_mean_science = mean(science_score, na.rm = TRUE),
    raw_mean_presentation = mean(presentation_score, na.rm = TRUE),
    raw_mean_sum = mean(obs_sum, na.rm = TRUE),
    raw_se_sum   = sd(obs_sum, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  )

post_exp <- fit$summary(
  variables = "exp_sum",
  mean, median,
  # Equal-tailed intervals from posterior draws of the expected total at judge effect 0.
  ~quantile(.x, probs = c(0.05, 0.25, 0.75, 0.95))
) %>%
  mutate(poster_id = as.integer(gsub("exp_sum\\[|\\]", "", variable))) %>%
  rename(
    adj_mean = mean,
    adj_median = median,
    q05 = `5%`,
    q25 = `25%`,
    q75 = `75%`,
    q95 = `95%`
  ) %>%
  select(poster_id, adj_mean, adj_median, q05, q25, q75, q95)

post_best <- fit$summary(variables = "is_best", prob_best = mean) %>%
  mutate(poster_id = as.integer(gsub("is_best\\[|\\]", "", variable))) %>%
  select(poster_id, prob_best)

post_domains <- fit$summary(variables = c("exp_science", "exp_presentation"), mean) %>%
  extract(variable, c("domain", "poster_id"),
          "^(exp_science|exp_presentation)\\[([0-9]+)\\]$", convert = TRUE) %>%
  pivot_wider(names_from = domain, values_from = mean) %>%
  rename(adj_mean_science = exp_science, adj_mean_presentation = exp_presentation)

plot_df <- obs_summary %>%
  left_join(post_exp, by = "poster_id") %>%
  left_join(post_best, by = "poster_id") %>%
  left_join(post_domains, by = "poster_id") %>%
  left_join(poster_info, by = "poster_id") %>%
  arrange(desc(adj_mean)) %>%
  mutate(
    poster_label = sprintf("%s    %.1f (n=%d)", poster_code, raw_mean_sum, n_judges),
    poster_label = factor(poster_label, levels = rev(poster_label))
  )

# -------------------------------------------------------------------------
# 4. Classical aesthetic two-panel plot using ggplot2 + cowplot
# -------------------------------------------------------------------------
# Panel A: Observed Raw Mean vs. Judge-Adjusted Posterior Sum (2-20 scale)
p_scores <- ggplot(plot_df, aes(y = poster_label)) +
  geom_segment(
    aes(x = raw_mean_sum, xend = adj_mean, yend = poster_label),
    color = "grey65", linetype = "dotted", linewidth = 0.6
  ) +
  geom_segment(
    aes(x = q05, xend = q95, yend = poster_label),
    color = "#1B365D", linewidth = 0.6
  ) +
  geom_segment(
    aes(x = q25, xend = q75, yend = poster_label),
    color = "#1B365D", linewidth = 2
  ) +
  geom_point(
    aes(x = adj_mean, color = "Adjusted posterior mean", shape = "Adjusted posterior mean"),
    size = 2.8
  ) +
  geom_point(
    aes(x = raw_mean_sum, color = "Observed mean sum", shape = "Observed mean sum"),
    size = 4
  ) +
  scale_color_manual(
    name = NULL,
    values = c("Observed mean sum" = "#B24A00", "Adjusted posterior mean" = "#1B365D"),
    breaks = c("Observed mean sum", "Adjusted posterior mean")
  ) +
  scale_shape_manual(
    name = NULL,
    values = c("Observed mean sum" = 18, "Adjusted posterior mean" = 16),
    breaks = c("Observed mean sum", "Adjusted posterior mean")
  ) +
  scale_x_continuous(limits = c(2, 20), breaks = seq(2, 20, by = 2)) +
  labs(
    title = "A. Observed and adjusted scores",
    subtitle = "Posterior draw percentiles (judge effect = 0):\n50% thick: 25th–75th; 90% thin: 5th–95th",
    x = "Science + presentation score (2–20)",
    y = "Poster    observed mean (n)"
  ) +
  theme_cowplot(font_size = 11) +
  theme(
    panel.grid.major.x = element_line(color = "grey92", linewidth = 0.4),
    legend.position = "bottom",
    plot.title = element_text(face = "bold"),
    plot.subtitle = element_text(size = 9)
  )

# Panel B: Pr(Poster is Best)
p_best <- ggplot(plot_df, aes(x = prob_best, y = poster_label)) +
  geom_col(fill = "#2C5E4F", color = "black", linewidth = 0.3, width = 0.62) +
  scale_x_continuous(
    limits = c(0, 1),
    breaks = seq(0, 1, 0.2),
    labels = scales::percent_format(accuracy = 1)
  ) +
  labs(
    title = "B. Probability of best poster",
    subtitle = "Share of posterior draws with the highest\nexpected total; judge effect = 0",
    x = "Pr(best poster)",
    y = NULL
  ) +
  theme_cowplot(font_size = 11) +
  theme(
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank(),
    panel.grid.major.x = element_line(color = "grey92", linewidth = 0.4),
    plot.title = element_text(face = "bold"),
    plot.subtitle = element_text(size = 9)
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

# Save the plot
ggsave(file.path(output_dir, "poster_ratings_analysis.pdf"), final_plot, width = 14, height = 6)
cat("\nPlot saved to:", file.path(output_dir, "poster_ratings_analysis.pdf"), "\n")

# Bivariate observed means and posterior expectations on the 1-10 score scale
mean_score_lines <- data.frame(mean_score = c(2, 4, 6, 8)) %>%
  mutate(
    label_x = pmax(1.15, 2 * mean_score - 9.6),
    label_y = 2 * mean_score - label_x
  )

p_bivariate <- ggplot(plot_df) +
  geom_abline(
    data = mean_score_lines,
    aes(slope = -1, intercept = 2 * mean_score),
    color = "grey80", linewidth = 0.4, linetype = "dashed"
  ) +
  geom_text(
    data = mean_score_lines,
    aes(x = label_x, y = label_y, label = paste("Mean", mean_score)),
    color = "grey40", size = 3, hjust = 0, vjust = -0.3
  ) +
  geom_segment(
    aes(x = raw_mean_science, y = raw_mean_presentation,
        xend = adj_mean_science, yend = adj_mean_presentation),
    color = "grey55", linewidth = 0.6,
    arrow = grid::arrow(length = grid::unit(0.1, "inches"), type = "closed")
  ) +
  geom_point(
    aes(x = raw_mean_science, y = raw_mean_presentation,
        color = "Observed mean", shape = "Observed mean"),
    size = 4
  ) +
  geom_point(
    aes(x = adj_mean_science, y = adj_mean_presentation,
        color = "Adjusted posterior mean", shape = "Adjusted posterior mean"),
    size = 2.8
  ) +
  geom_text(
    aes(x = adj_mean_science, y = adj_mean_presentation, label = poster_code),
    nudge_y = 0.25, size = 3, check_overlap = TRUE
  ) +
  scale_color_manual(
    name = NULL,
    values = c("Observed mean" = "#B24A00", "Adjusted posterior mean" = "#1B365D"),
    breaks = c("Observed mean", "Adjusted posterior mean")
  ) +
  scale_shape_manual(
    name = NULL,
    values = c("Observed mean" = 18, "Adjusted posterior mean" = 16),
    breaks = c("Observed mean", "Adjusted posterior mean")
  ) +
  scale_x_continuous(breaks = 1:10) +
  scale_y_continuous(breaks = 1:10) +
  coord_equal(xlim = c(0.5, 10.5), ylim = c(0.5, 10.5)) +
  labs(
    title = "Observed and adjusted poster scores",
    subtitle = "Arrows: observed means to posterior expectations at judge effect = 0",
    x = "Science score",
    y = "Presentation score",
    caption = "Diagonal lines show (science + presentation) / 2.\nPoster labels identify adjusted points; overlapping labels may be omitted."
  ) +
  theme_cowplot(font_size = 11) +
  theme(
    panel.grid.major = element_line(color = "grey92", linewidth = 0.4),
    legend.position = "bottom",
    plot.title = element_text(face = "bold")
  )

print(p_bivariate)
ggsave(file.path(output_dir, "poster_ratings_bivariate.pdf"), p_bivariate, width = 8, height = 8)
cat("Plot saved to:", file.path(output_dir, "poster_ratings_bivariate.pdf"), "\n")

# -------------------------------------------------------------------------
# 5. Summary Table
# -------------------------------------------------------------------------
summary_table <- plot_df %>%
  select(
    poster_id, poster_code, poster_title, author, 
    n_judges, raw_mean_sum, adj_mean, prob_best
  ) %>%
  rename(
    "Poster" = poster_id,
    "ID" = poster_code,
    "Title" = poster_title,
    "Author" = author,
    "N Judges" = n_judges,
    "Raw Mean" = raw_mean_sum,
    "Adjusted Mean" = adj_mean,
    "Pr(Best)" = prob_best
  )

cat("\n========== Poster Ratings Summary Table ==========\n")
print(summary_table, n = P)

cat("\nAnalysis complete!\n")
