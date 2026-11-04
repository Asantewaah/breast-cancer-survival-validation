# 05_external_validation.R
#
# External validation of the Rotterdam model in the GBSG 2 trial patients,
# who played no part in building it (TRIPOD items 10c and 16). The model is
# applied exactly as fitted: no coefficient or baseline is re-estimated.
#
# Follow-up in GBSG 2 is censored at 5 years, the prediction horizon.
#
#   Discrimination: Harrell's C-index, and Uno's C-index, which is less
#     affected by how much follow-up a cohort has.
#   Calibration-in-the-large: observed 5-year risk (Kaplan-Meier) divided by
#     the average predicted risk (O/E). Above 1 means the model underpredicts.
#   Calibration slope: the coefficient of the linear predictor in a Cox model
#     fitted to GBSG 2. 1 is ideal; below 1 means predictions are too extreme.
#   Calibration curve at 5 years: observed against predicted risk, from a
#     flexible hazard regression (hare) on the complementary log-log of the
#     predicted risk (Austin, Harrell and van Klaveren 2020), with deciles of
#     predicted risk shown as points.
#   Model misspecification: does adding the predictors back on top of the
#     linear predictor improve the fit in GBSG 2? (Royston and Altman 2013).
#   Risk groups: Kaplan-Meier curves in GBSG 2 for low, middle and high risk
#     groups defined by the Rotterdam tertiles, against the model's average
#     predicted curve for each group.
#
# Run from the project root after 03_develop_model.R:
#   Rscript R/05_external_validation.R
#
# Outputs:
#   data/processed/validation_predictions.rds
#   output/tables/external_validation.csv
#   output/tables/external_calibration_groups.csv
#   output/tables/misspecification_test.csv
#   output/figures/calibration_external.png
#   output/figures/risk_groups_external.png

suppressPackageStartupMessages({
  library(survival)
  library(rms)
  library(polspline)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(readr)
  library(ggplot2)
})

source(file.path("R", "plot_theme.R"))
source(file.path("R", "model_setup.R"))

development <- load_development()
fit <- readRDS(file.path("data", "processed", "cox_model.rds"))

validation <- readRDS(file.path("data", "processed", "validation.rds")) |>
  add_model_vars()
cens <- censor_at(validation$rfs_time, validation$rfs_event)
validation$time5  <- cens$time
validation$event5 <- cens$event

# Predictions from the Rotterdam model, applied unchanged
validation$lp   <- predict(fit, newdata = validation, type = "lp")
validation$risk <- 1 - survest(fit, newdata = validation, times = horizon)$surv
saveRDS(validation, file.path("data", "processed", "validation_predictions.rds"))

ci <- function(est, se, z = qnorm(0.975)) c(est, est - z * se, est + z * se)

# ---------------------------------------------------------------------------
# Discrimination
# ---------------------------------------------------------------------------
harrell <- concordance(Surv(time5, event5) ~ lp, data = validation, reverse = TRUE)
uno     <- concordance(Surv(time5, event5) ~ lp, data = validation, reverse = TRUE,
                       timewt = "n/G2")
c_harrell <- ci(harrell$concordance, sqrt(harrell$var))
c_uno     <- ci(uno$concordance, sqrt(uno$var))

# ---------------------------------------------------------------------------
# Calibration-in-the-large: observed / expected at 5 years
# ---------------------------------------------------------------------------
km5 <- summary(survfit(Surv(time5, event5) ~ 1, data = validation), times = horizon)
observed <- 1 - km5$surv
expected <- mean(validation$risk)
oe <- observed / expected
# CI from the Kaplan-Meier standard error, on the log scale (Riley et al. 2024)
oe_se_log <- km5$std.err / observed
oe_ci <- c(oe, oe * exp(-1.96 * oe_se_log), oe * exp(1.96 * oe_se_log))

# ---------------------------------------------------------------------------
# Calibration slope
# ---------------------------------------------------------------------------
slope_fit <- coxph(Surv(time5, event5) ~ lp, data = validation)
slope <- ci(unname(coef(slope_fit)), sqrt(vcov(slope_fit)[1, 1]))

# ---------------------------------------------------------------------------
# Flexible calibration curve at 5 years
# ---------------------------------------------------------------------------
validation$cll <- log(-log(1 - validation$risk))
hare_fit <- hare(data = validation$time5, delta = validation$event5,
                 cov = as.matrix(validation$cll))
validation$observed_smooth <- phare(horizon, validation$cll, hare_fit)
abs_err <- abs(validation$observed_smooth - validation$risk)
ici <- mean(abs_err)
e50 <- median(abs_err)
e90 <- unname(quantile(abs_err, 0.9))

grid <- tibble(risk = seq(quantile(validation$risk, 0.01),
                          quantile(validation$risk, 0.99), length.out = 200)) |>
  mutate(observed = phare(horizon, log(-log(1 - risk)), hare_fit))

# Deciles of predicted risk, with Kaplan-Meier observed risk and 95% CI
groups <- validation |>
  mutate(decile = ntile(risk, 10)) |>
  group_by(decile) |>
  group_modify(~ {
    s <- summary(survfit(Surv(time5, event5) ~ 1, data = .x), times = horizon, extend = TRUE)
    tibble(n = nrow(.x), predicted = mean(.x$risk), observed = 1 - s$surv,
           lower = 1 - s$upper, upper = 1 - s$lower)
  }) |>
  ungroup()
write_csv(groups |> mutate(across(c(predicted, observed, lower, upper), ~ round(.x, 3))),
          file.path("output", "tables", "external_calibration_groups.csv"))

# ---------------------------------------------------------------------------
# Model misspecification (Royston and Altman 2013)
# ---------------------------------------------------------------------------
m0 <- coxph(Surv(time5, event5) ~ offset(lp), data = validation)
m_all <- coxph(Surv(time5, event5) ~ offset(lp) + age + meno + size + grade3 +
                 nodes20 + lpgr + ler + hormon, data = validation)
lr_all <- anova(m0, m_all)
m_grade <- coxph(Surv(time5, event5) ~ offset(lp) + grade3, data = validation)
m_pgr   <- coxph(Surv(time5, event5) ~ offset(lp) + lpgr, data = validation)

misspec <- tibble(
  test = c("All predictors added to the linear predictor",
           "Grade 3 added", "Log progesterone receptor added"),
  df = c(lr_all$Df[2], 1, 1),
  chisq = c(lr_all$Chisq[2], anova(m0, m_grade)$Chisq[2], anova(m0, m_pgr)$Chisq[2]),
  p = c(lr_all$`Pr(>|Chi|)`[2], anova(m0, m_grade)$`Pr(>|Chi|)`[2],
        anova(m0, m_pgr)$`Pr(>|Chi|)`[2]),
  extra_log_hr = c(NA, coef(m_grade)[["grade3"]], coef(m_pgr)[["lpgr"]])
) |>
  mutate(across(c(chisq, extra_log_hr), ~ round(.x, 3)), p = signif(p, 2))
write_csv(misspec, file.path("output", "tables", "misspecification_test.csv"))

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------
fmt3 <- function(x) round(x, 3)
external <- tibble(
  measure = c("Harrell's C-index", "Uno's C-index", "Observed 5-year risk (Kaplan-Meier)",
              "Mean predicted 5-year risk", "Observed / expected (O/E)",
              "Calibration slope", "Mean absolute calibration error (ICI)",
              "Median absolute calibration error (E50)",
              "90th percentile absolute calibration error (E90)"),
  estimate = fmt3(c(c_harrell[1], c_uno[1], observed, expected, oe_ci[1], slope[1], ici, e50, e90)),
  lower = fmt3(c(c_harrell[2], c_uno[2], 1 - km5$upper, NA, oe_ci[2], slope[2], NA, NA, NA)),
  upper = fmt3(c(c_harrell[3], c_uno[3], 1 - km5$lower, NA, oe_ci[3], slope[3], NA, NA, NA))
)
dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(external, file.path("output", "tables", "external_validation.csv"))

# ---------------------------------------------------------------------------
# Figure 1: calibration at 5 years in GBSG 2
# ---------------------------------------------------------------------------
p_cal <- ggplot() +
  geom_abline(slope = 1, intercept = 0, colour = col_mid, linewidth = 0.6, linetype = "dashed") +
  annotate("text", x = 0.86, y = 0.93, label = "Perfect calibration",
           colour = col_muted, size = 3.2, angle = 45) +
  geom_rug(data = validation, aes(x = risk), sides = "b", alpha = 0.2,
           colour = col_marigold, length = unit(0.03, "npc")) +
  geom_line(data = grid, aes(risk, observed), colour = col_marigold, linewidth = 1.1) +
  geom_errorbar(data = groups, aes(x = predicted, ymin = lower, ymax = upper),
                width = 0, colour = col_indigo, linewidth = 0.5) +
  geom_point(data = groups, aes(predicted, observed), colour = col_indigo, size = 2.4) +
  annotate("text", x = 0.03, y = 0.95, hjust = 0, vjust = 1, colour = col_text, size = 3.4,
           lineheight = 1.1,
           label = sprintf("C-index %.2f (%.2f to %.2f)\nCalibration slope %.2f (%.2f to %.2f)\nObserved / expected %.2f (%.2f to %.2f)",
                           c_harrell[1], c_harrell[2], c_harrell[3],
                           slope[1], slope[2], slope[3], oe_ci[1], oe_ci[2], oe_ci[3])) +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1), breaks = seq(0, 1, 0.2),
                     expand = expansion(mult = c(0, 0.01))) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1), breaks = seq(0, 1, 0.2),
                     expand = expansion(mult = c(0, 0.01))) +
  coord_equal() +
  labs(
    title = sprintf("On patients it had never seen, the model still predicted well: %.0f%% observed 5-year risk against %.0f%% predicted, and a C-index of %.2f",
                    100 * observed, 100 * expected, c_harrell[1]),
    subtitle = sprintf("GBSG 2 trial patients (n = %d). Line: flexible calibration curve. Points: tenths of predicted risk with Kaplan-Meier observed risk and 95%% CI. Ticks show each patient's predicted risk. Mean absolute error %.1f percentage points.",
                       nrow(validation), 100 * ici),
    x = "Predicted 5-year risk (Rotterdam model)", y = "Observed 5-year risk in GBSG 2",
    caption = source_note
  ) +
  theme_project()

save_figure(p_cal, "calibration_external", width = 7.5, height = 8.4,
            title_width = 62, subtitle_width = 80, caption_width = 95)

# ---------------------------------------------------------------------------
# Figure 2: observed and predicted survival by risk group
# ---------------------------------------------------------------------------
cuts <- quantile(predict(fit, type = "lp"), c(1 / 3, 2 / 3))
group_levels <- c("Low risk", "Middle risk", "High risk")
validation$group <- factor(cut(validation$lp, c(-Inf, cuts, Inf), labels = group_levels),
                           levels = group_levels)
group_cols <- c("Low risk" = col_marigold, "Middle risk" = "#8C8AA8", "High risk" = col_indigo)

km_g <- survfit(Surv(time5, event5) ~ group, data = validation)
obs_curves <- tibble(
  group = rep(sub("group=", "", names(km_g$strata)), km_g$strata),
  time = km_g$time, surv = km_g$surv
) |>
  group_by(group) |>
  group_modify(~ bind_rows(tibble(time = 0, surv = 1), .x)) |>
  ungroup()

times <- seq(0, horizon, by = 0.05)
pred_surv <- survest(fit, newdata = validation, times = times[-1])$surv
pred_curves <- tibble(group = validation$group) |>
  bind_cols(as_tibble(pred_surv, .name_repair = ~ as.character(times[-1]))) |>
  pivot_longer(-group, names_to = "time", values_to = "surv") |>
  mutate(time = as.numeric(time)) |>
  group_by(group, time) |>
  summarise(surv = mean(surv), .groups = "drop") |>
  bind_rows(tibble(group = factor(group_levels, levels = group_levels), time = 0, surv = 1))

group_summary <- validation |>
  group_by(group) |>
  group_modify(~ {
    s <- summary(survfit(Surv(time5, event5) ~ 1, data = .x), times = horizon, extend = TRUE)
    tibble(n = nrow(.x), predicted_rfs = mean(1 - .x$risk), observed_rfs = s$surv)
  }) |>
  ungroup()
write_csv(group_summary |> mutate(across(where(is.double), ~ round(.x, 3))),
          file.path("output", "tables", "external_risk_groups.csv"))

labels_g <- group_summary |>
  mutate(time = horizon, surv = observed_rfs,
         label = sprintf("%s: %.0f%% observed, %.0f%% predicted", group,
                         100 * observed_rfs, 100 * predicted_rfs))

obs_curves$group  <- factor(obs_curves$group, levels = group_levels)
pred_curves$group <- factor(pred_curves$group, levels = group_levels)

p_groups <- ggplot() +
  geom_line(data = pred_curves, aes(time, surv, colour = group), linewidth = 0.8,
            linetype = "dashed") +
  geom_step(data = obs_curves, aes(time, surv, colour = group), linewidth = 1) +
  geom_text(data = labels_g, aes(time, surv, label = label), colour = col_text,
            hjust = 0, nudge_x = 0.08, size = 3.4, fontface = "bold") +
  scale_colour_manual(values = group_cols) +
  scale_x_continuous(breaks = 0:5, limits = c(0, 8.4), expand = expansion(mult = c(0, 0))) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1), breaks = seq(0, 1, 0.25),
                     expand = expansion(mult = c(0, 0.02))) +
  labs(
    title = sprintf("The model separates GBSG 2 patients into clearly different outcomes: %.0f%% of the low-risk group were recurrence-free at 5 years, against %.0f%% of the high-risk group",
                    100 * group_summary$observed_rfs[1], 100 * group_summary$observed_rfs[3]),
    subtitle = "Recurrence-free survival in GBSG 2 by risk group (thirds of the Rotterdam linear predictor). Solid: observed (Kaplan-Meier). Dashed: average predicted by the model.",
    x = "Years since surgery", y = "Alive without recurrence",
    caption = source_note
  ) +
  theme_project()

save_figure(p_groups, "risk_groups_external", width = 9.5, height = 5.8)

message(sprintf("Harrell's C %.3f (%.3f to %.3f); Uno's C %.3f", c_harrell[1], c_harrell[2], c_harrell[3], c_uno[1]))
message(sprintf("O/E %.3f (%.3f to %.3f): observed %.3f, predicted %.3f", oe_ci[1], oe_ci[2], oe_ci[3], observed, expected))
message(sprintf("Calibration slope %.3f (%.3f to %.3f)", slope[1], slope[2], slope[3]))
message(sprintf("ICI %.3f, E50 %.3f, E90 %.3f", ici, e50, e90))
message(sprintf("Misspecification test: all predictors p = %s; grade p = %s; PgR p = %s",
                misspec$p[1], misspec$p[2], misspec$p[3]))
