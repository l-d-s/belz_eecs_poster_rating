functions {
  // Log PMF for interval-censored Beta on {1, ..., 10}
  real interval_beta_lpmf(int y, real mu, real phi) {
    real alpha = mu * phi;
    real beta_param = (1.0 - mu) * phi;
    real pupper = (y == 10) ? 1.0 : beta_cdf(y / 10.0 | alpha, beta_param);
    real plower = (y == 1)  ? 0.0 : beta_cdf((y - 1.0) / 10.0 | alpha, beta_param);
    
    // Guard against numerical underflow in extreme tails
    return log(fmax(pupper - plower, 1e-16));
  }

  // Exact expected discrete score on 1-10 scale given (mu, phi)
  real expected_discrete_beta(real mu, real phi) {
    real alpha = mu * phi;
    real beta_param = (1.0 - mu) * phi;
    real ev = 10.0;
    for (k in 1:9) {
      ev -= beta_cdf(k / 10.0 | alpha, beta_param);
    }
    return ev;
  }
}

data {
  int<lower=1> N;                          // Number of evaluation rows
  int<lower=1> P;                          // Number of posters
  int<lower=1> J;                          // Number of judges
  array[N] int<lower=1, upper=P> poster_id;
  array[N] int<lower=1, upper=J> judge_id;
  // Scores 1..10 (use -1 for missing score in one domain)
  array[N] int<lower=-1, upper=10> science_score;
  array[N] int<lower=-1, upper=10> presentation_score;
}

parameters {
  // Flat/uniform prior on (0, 1) latent poster quality
  matrix<lower=0, upper=1>[P, 2] theta;

  // Non-centered correlated random effects for judges
  vector<lower=0>[2] tau;                  // Judge SDs (science, presentation)
  cholesky_factor_corr[2] L_Omega;         // Cholesky factor of correlation matrix
  matrix[2, J] z_judge;                    // Standard normal latent variables

  // Domain-specific Beta precision (concentration)
  vector<lower=0>[2] phi;
}

transformed parameters {
  matrix[P, 2] eta = logit(theta);         // Latent poster quality on logit scale
  matrix[J, 2] b_judge;                    // Judge bias on logit scale (J x 2)

  b_judge = (diag_pre_multiply(tau, L_Omega) * z_judge)';
}

model {
  // Priors
  // Note: theta ~ uniform(0, 1) is implicit from <lower=0, upper=1> bounds
  tau ~ normal(0, 1);
  L_Omega ~ lkj_corr_cholesky(2.0);
  to_vector(z_judge) ~ std_normal();
  phi ~ gamma(2.0, 0.1);

  // Likelihood
  for (i in 1:N) {
    int p = poster_id[i];
    int j = judge_id[i];

    if (science_score[i] != -1) {
      real mu_sci = inv_logit(eta[p, 1] + b_judge[j, 1]);
      science_score[i] ~ interval_beta(mu_sci, phi[1]);
    }
    if (presentation_score[i] != -1) {
      real mu_pres = inv_logit(eta[p, 2] + b_judge[j, 2]);
      presentation_score[i] ~ interval_beta(mu_pres, phi[2]);
    }
  }
}

generated quantities {
  corr_matrix[2] Omega = multiply_lower_tri_self_transpose(L_Omega);
  real rho_judge = Omega[1, 2];

  vector[P] exp_science;
  vector[P] exp_presentation;
  vector[P] exp_mean;
  array[P] int<lower=0, upper=1> is_best;

  real max_mean = negative_infinity();
  for (p in 1:P) {
    exp_science[p] = expected_discrete_beta(theta[p, 1], phi[1]);
    exp_presentation[p] = expected_discrete_beta(theta[p, 2], phi[2]);
    exp_mean[p] = (exp_science[p] + exp_presentation[p]) / 2;
    if (exp_mean[p] > max_mean) {
      max_mean = exp_mean[p];
    }
  }

  for (p in 1:P) {
    is_best[p] = (exp_mean[p] >= max_mean - 5e-13) ? 1 : 0;
  }
}
