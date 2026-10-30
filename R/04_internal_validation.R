# 04_internal_validation.R
#
# Internal validation of the Cox model with the bootstrap (TRIPOD item 10b).
#
# A model always looks better on the patients it was fitted to. The bootstrap
# estimates by how much: the whole model is refitted in each of 500 resamples
# of the Rotterdam data, tested on the original data, and the average drop in
# performance (the optimism) is subtracted from the apparent performance.
#
#   C-index: how well the model ranks patients (0.5 = chance, 1 = perfect).
#   Calibration slope: below 1 means predictions are too extreme and would
#     need shrinking towards the average for new patients.
#   Calibration at 5 years: predicted against observed 5-year risk, corrected
#     for optimism, using a flexible hazard regression (hare).
#
# Run from the project root after 03_develop_model.R:
#   Rscript R/04_internal_validation.R
#
# Outputs:
#   output/tables/internal_validation.csv
#   output/tables/internal_calibration.csv
#   output/figures/calibration_internal.png

suppressPackageStartupMessages({
  library(survival)
  library(rms)
  library(dplyr)
  library(tibble)
  library(readr)
  library(ggplot2)
})

source(file.path("R", "plot_theme.R"))
source(file.path("R", "model_setup.R"))

development <- load_development()
fit <- readRDS(file.path("data", "processed", "cox_model.rds"))

B <- 500

# ---------------------------------------------------------------------------
# Optimism in discrimination and calibration slope
# ---------------------------------------------------------------------------
set.seed(2026)
v <- validate(fit, B = B)

dxy_to_c <- function(dxy) (dxy + 1) / 2
internal <- tibble(
  measure    = c("C-index", "Calibration slope", "Nagelkerke R-squared"),
  apparent   = c(dxy_to_c(v["Dxy", "index.orig"]), v["Slope", "index.orig"], v["R2", "index.orig"]),
  optimism   = c(v["Dxy", "optimism"] / 2, v["Slope", "optimism"], v["R2", "optimism"]),
  corrected  = c(dxy_to_c(v["Dxy", "index.corrected"]), v["Slope", "index.corrected"], v["R2", "index.corrected"])
) |>
  mutate(across(where(is.numeric), ~ round(.x, 3)), bootstrap_samples = B)

dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(internal, file.path("output", "tables", "internal_validation.csv"))

# ---------------------------------------------------------------------------
# Calibration of 5-year predictions, corrected for optimism
# ---------------------------------------------------------------------------
set.seed(2026)
cal <- calibrate(fit, u = horizon, B = B, cmethod = "hare")

curve <- tibble(
  predicted_rfs = cal[, "pred"],
  observed_apparent  = cal[, "calibrated"],
  observed_corrected = cal[, "calibrated.corrected"]
) |>
  mutate(predicted_risk = 1 - predicted_rfs,
         observed_risk  = 1 - observed_corrected) |>
  filter(!is.na(observed_risk))

write_csv(curve |> mutate(across(everything(), ~ round(.x, 4))),
          file.path("output", "tables", "internal_calibration.csv"))

# Average and 90th percentile absolute calibration error over the patients'
# own predictions (ICI and E90), from the optimism-corrected curve
patient_pred <- 1 - survest(fit, newdata = development, times = horizon)$surv
patient_obs  <- approx(curve$predicted_risk, curve$observed_risk,
                       xout = patient_pred, rule = 2)$y
abs_err <- abs(patient_obs - patient_pred)
ici <- mean(abs_err)
e90 <- unname(quantile(abs_err, 0.9))

internal <- internal |>
  bind_rows(tibble(measure = c("Mean absolute calibration error at 5 years (ICI)",
                               "90th percentile absolute calibration error (E90)"),
                   apparent = NA, optimism = NA,
                   corrected = round(c(ici, e90), 3), bootstrap_samples = B))
write_csv(internal, file.path("output", "tables", "internal_validation.csv"))

# ---------------------------------------------------------------------------
# Figure: optimism-corrected calibration at 5 years
# ---------------------------------------------------------------------------
c_app  <- internal$apparent[1]
c_corr <- internal$corrected[1]
slope_corr <- internal$corrected[2]

dens <- tibble(predicted_risk = patient_pred)

p <- ggplot(curve, aes(predicted_risk, observed_risk)) +
  geom_abline(slope = 1, intercept = 0, colour = col_mid, linewidth = 0.6,
              linetype = "dashed") +
  annotate("text", x = 0.86, y = 0.93, label = "Perfect calibration",
           colour = col_muted, size = 3.2, angle = 45) +
  geom_rug(data = dens, aes(x = predicted_risk), inherit.aes = FALSE,
           sides = "b", alpha = 0.15, colour = col_indigo, length = unit(0.03, "npc")) +
  geom_line(colour = col_indigo, linewidth = 1.1) +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1), breaks = seq(0, 1, 0.2),
                     expand = expansion(mult = c(0, 0.01))) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1), breaks = seq(0, 1, 0.2),
                     expand = expansion(mult = c(0, 0.01))) +
  coord_equal() +
  labs(
    title = sprintf("Inside Rotterdam, the model holds up: after correcting for optimism its C-index is %.2f (from %.2f) and predicted 5-year risks stay close to observed",
                    c_corr, c_app),
    subtitle = sprintf("Predicted against observed 5-year risk of recurrence or death, corrected for optimism with %d bootstrap samples. Ticks along the bottom show each patient's predicted risk. Calibration slope %.2f; mean absolute error %.1f percentage points.",
                       B, slope_corr, 100 * ici),
    x = "Predicted 5-year risk", y = "Observed 5-year risk",
    caption = source_note
  ) +
  theme_project()

save_figure(p, "calibration_internal", width = 7.5, height = 8.2,
            title_width = 62, subtitle_width = 80, caption_width = 95)

message(sprintf("C-index: apparent %.3f, optimism %.3f, corrected %.3f",
                internal$apparent[1], internal$optimism[1], internal$corrected[1]))
message(sprintf("Calibration slope (corrected): %.3f", slope_corr))
message(sprintf("5-year calibration error: ICI %.3f, E90 %.3f", ici, e90))
