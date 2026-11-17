# Poster ratings

This repository fits a Bayesian model to science and presentation scores,
accounting for differences between judges. The Stan implementation is in
[`rating_model/rating_model.stan`](rating_model/rating_model.stan).

## Model

Let $p=1,\ldots,P$ index posters, $j=1,\ldots,J$ judges, and
$d\in\{1,2\}$ the science and presentation domains. Evaluation $i$
has poster $p_i$, judge $j_i$, and score $y_{id}\in\{1,\ldots,10\}$.

### Poster quality and judge effects

For each poster and domain, the latent quality for a judge with zero
effect is $\theta_{pd}$:

$$
\theta_{pd} \sim \operatorname{Uniform}(0,1), \qquad
\eta_{pd} = \operatorname{logit}(\theta_{pd}).
$$

Judge effects are correlated across the two domains. The model uses a
non-centered parameterization:

$$
\begin{aligned}
z_j &\sim \mathcal{N}_2(\mathbf{0}, I), \\
b_j &= \operatorname{diag}(\tau_1,\tau_2)\,L_\Omega z_j, \\
\Omega &= L_\Omega L_\Omega^\mathsf{T}, \\
\tau_d &\sim \operatorname{HalfNormal}(0,1), \\
\Omega &\sim \operatorname{LKJ}(2).
\end{aligned}
$$

Here $b_{jd}$ is the judge's effect in domain $d$, $\tau_d$ is its
standard deviation, and $\Omega$ is the correlation matrix. Stan directly
parameterizes its Cholesky factor $L_\Omega$.

### Score likelihood

The mean and precision of the latent continuous score are:

$$
\begin{aligned}
\mu_{id} &= \operatorname{logit}^{-1}(\eta_{p_i d}+b_{j_i d}), \\
\phi_d &\sim \operatorname{Gamma}(2,0.1), \\
\alpha_{id} &= \mu_{id}\phi_d, \\
\beta_{id} &= (1-\mu_{id})\phi_d, \\
u_{id} &\sim \operatorname{Beta}(\alpha_{id},\beta_{id}).
\end{aligned}
$$

The Gamma distribution uses shape and **rate**. Conditional on the model
parameters, observed scores are independent. The underlying score is
discretized as $y_{id}=\lceil 10u_{id}\rceil$. If $F_{id}$ is the CDF
of the corresponding Beta distribution, then for $k=1,\ldots,10$:

$$
\Pr(y_{id}=k\mid\mu_{id},\phi_d)
= F_{id}\!\left(\frac{k}{10}\right)
  - F_{id}\!\left(\frac{k-1}{10}\right).
$$

The implementation uses $F_{id}(0)=0$ and $F_{id}(1)=1$, and floors
each interval probability at $10^{-16}$ before taking its logarithm.
This numerical safeguard can make the resulting floored probabilities
sum to slightly more than one. The Stan model treats a score of `-1` as
missing and omits that domain's likelihood contribution; valid observed
scores are 1 through 10. The real-data script does not currently convert
missing CSV values to `-1`.

### Poster summaries

For each posterior draw, the expected discrete score for a hypothetical
judge with zero effect is

$$
e_{pd}
= 10-\sum_{k=1}^{9}
F_{\operatorname{Beta}(\theta_{pd}\phi_d,\,(1-\theta_{pd})\phi_d)}
\!\left(\frac{k}{10}\right),
\qquad
m_p=\frac{e_{p1}+e_{p2}}{2}.
$$

The scripts summarize $m_p$ across posterior draws, on the 1–10 scale.
Observed averages similarly take the mean of science and presentation
scores for each evaluation before averaging over judges. The 50% and 90%
equal-tailed intervals use the 25th–75th and 5th–95th percentiles,
respectively. These are intervals for the expected average at zero judge
effect, not prediction intervals for a future observed score.

The best-poster indicator in each draw is

$$
I_p=\mathbf{1}\!\left\{m_p\geq \max_q m_q-5\cdot10^{-13}\right\}.
$$

Its posterior mean estimates the probability of being best under that
definition. Ties within the tolerance can give multiple posters an
indicator of one in the same draw.

The real-data plots label the five posters with the highest posterior mean
average score at zero judge effect. Ties are broken by the internal poster
index. Other posters remain visible without ID labels; the summary table
retains all poster metadata.

## Running the analyses

Run the scripts from the repository root in an R environment with CmdStanR,
CmdStan, posterior, dplyr, tidyr, ggplot2, cowplot, scales and systemfonts
installed. The Nix
flake describes a development environment, but a read-only CmdStan
installation may need a writable build setup when compilation is required.

- [`analysis.R`](analysis.R) simulates ratings before fitting the model.
- [`analysis_real_data.R`](analysis_real_data.R) reads
  `input_data/ecss-raw-scores-2026-11-17.csv`. The ignored `input_data/`
  directory must be supplied separately.

Both scripts write Stan sampling output to `outputs/`; the real-data script
also writes its plots there. Generated files in `outputs/` are not tracked.
The shared plot helpers are in [`plotting.R`](plotting.R). Plots use Arial
and Cairo PDF output when available; if Arial or Cairo is unavailable, the
scripts warn and use a portable sans-serif font (and standard PDFs if Cairo
is unavailable).

## License

Repository-owned material is dedicated to the public domain under
[CC0 1.0 Universal](LICENSE), with a permissive fallback license where
necessary. CC0 does not grant patent or trademark rights; dependencies and
input data may have their own rights and terms.
