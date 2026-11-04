# 07_summary.R
#
# Final step: checks performance in key subgroups of GBSG 2 (TRIPOD+AI items
# 14 and 23a) and collects the headline numbers from every earlier step into
# one file, so the README and any talk about the project quote the same
# figures.
#
# Subgroups are menopausal status and hormonal therapy, the only patient
# groupings available in both datasets. The data hold no sociodemographic
# information such as ethnicity or deprivation, so fairness across those
# groups cannot be assessed.
#
# Run from the project root after 06_decision_curve.R:
#   Rscript R/07_summary.R
#
# Outputs:
#   output/tables/subgroup_performance.csv
#   output/key_numbers.md

suppressPackageStartupMessages({
  library(survival)
  library(dplyr)
  library(tibble)
  library(readr)
})

source(file.path("R", "model_setup.R"))

validation <- readRDS(file.path("data", "processed", "validation_predictions.rds"))
tab <- function(name) read_csv(file.path("output", "tables", paste0(name, ".csv")),
                               show_col_types = FALSE)

# ---------------------------------------------------------------------------
# Subgroup performance in GBSG 2
# ---------------------------------------------------------------------------
performance <- function(d) {
  cc <- concordance(Surv(time5, event5) ~ lp, data = d, reverse = TRUE)
  km <- summary(survfit(Surv(time5, event5) ~ 1, data = d), times = horizon)
  observed <- 1 - km$surv
  oe <- observed / mean(d$risk)
  se_log_oe <- km$std.err / observed
  sl <- coxph(Surv(time5, event5) ~ lp, data = d)
  tibble(
    patients = nrow(d), events_5y = sum(d$event5),
    c_index = cc$concordance,
    c_lower = cc$concordance - 1.96 * sqrt(cc$var),
    c_upper = cc$concordance + 1.96 * sqrt(cc$var),
    observed_risk = observed, predicted_risk = mean(d$risk),
    oe = oe, oe_lower = oe * exp(-1.96 * se_log_oe), oe_upper = oe * exp(1.96 * se_log_oe),
    slope = unname(coef(sl)),
    slope_lower = unname(coef(sl) - 1.96 * sqrt(vcov(sl)[1, 1])),
    slope_upper = unname(coef(sl) + 1.96 * sqrt(vcov(sl)[1, 1]))
  )
}

subgroups <- bind_rows(
  performance(validation) |> mutate(subgroup = "All GBSG 2 patients"),
  performance(filter(validation, meno == 0)) |> mutate(subgroup = "Premenopausal"),
  performance(filter(validation, meno == 1)) |> mutate(subgroup = "Postmenopausal"),
  performance(filter(validation, hormon == 0)) |> mutate(subgroup = "No hormonal therapy"),
  performance(filter(validation, hormon == 1)) |> mutate(subgroup = "Hormonal therapy")
) |>
  relocate(subgroup) |>
  mutate(across(where(is.double), ~ round(.x, 3)))

write_csv(subgroups, file.path("output", "tables", "subgroup_performance.csv"))

# ---------------------------------------------------------------------------
# Key numbers
# ---------------------------------------------------------------------------
checks   <- tab("data_checks")
rfs      <- tab("rfs_by_cohort")
hr       <- tab("model_hazard_ratios")
internal <- tab("internal_validation")
external <- tab("external_validation")
groups   <- tab("external_risk_groups")
misspec  <- tab("misspecification_test")
dca      <- tab("decision_curve_summary")
dca_all  <- tab("decision_curve")

get <- function(d, col, key, value = "estimate") d[[value]][d[[col]] == key]
pct <- function(x, digits = 0) sprintf(paste0("%.", digits, "f%%"), 100 * x)
ci3 <- function(e, l, u) sprintf("%.2f (95%% CI %.2f to %.2f)", e + 1e-9, l + 1e-9, u + 1e-9)

nodes <- hr |> filter(predictor == "Positive lymph nodes")
beats <- dca_all$model > pmax(dca_all$treat_all, 0) + 0.005
useful_from <- dca_all$threshold[max(which(!beats)) + 1]

key <- c(
  "# Key numbers",
  "",
  paste0("Generated ", format(Sys.Date(), "%d %B %Y"), " by `R/07_summary.R` from the tables in `output/tables/`."),
  "",
  "## Data",
  sprintf("- Development: Rotterdam, %s node-positive patients, %s recurrence-free survival events.",
          format(checks$patients[1], big.mark = ","), format(checks$rfs_events[1], big.mark = ",")),
  sprintf("- Validation: GBSG 2, %s patients, %s events.", checks$patients[2], checks$rfs_events[2]),
  sprintf("- 5-year recurrence-free survival: Rotterdam %s, GBSG 2 %s.", pct(rfs$est[1]), pct(rfs$est[2])),
  "",
  "## Model",
  sprintf("- Strongest predictor: positive lymph nodes, %s, hazard ratio %.2f (95%% CI %.2f to %.2f).",
          nodes$comparison, nodes$hr, nodes$hr_lower, nodes$hr_upper),
  sprintf("- C-index in Rotterdam: apparent %.3f, optimism-corrected %.3f.",
          get(internal, "measure", "C-index", "apparent"), get(internal, "measure", "C-index", "corrected")),
  sprintf("- Optimism-corrected calibration slope: %.3f.", get(internal, "measure", "Calibration slope", "corrected")),
  "",
  "## External validation in GBSG 2",
  sprintf("- Harrell's C-index %s; Uno's %.2f.",
          ci3(get(external, "measure", "Harrell's C-index"), get(external, "measure", "Harrell's C-index", "lower"),
              get(external, "measure", "Harrell's C-index", "upper")),
          get(external, "measure", "Uno's C-index")),
  sprintf("- Observed 5-year risk %s against %s predicted; observed/expected %s.",
          pct(get(external, "measure", "Observed 5-year risk (Kaplan-Meier)")),
          pct(get(external, "measure", "Mean predicted 5-year risk")),
          ci3(get(external, "measure", "Observed / expected (O/E)"),
              get(external, "measure", "Observed / expected (O/E)", "lower"),
              get(external, "measure", "Observed / expected (O/E)", "upper"))),
  sprintf("- Calibration slope %s.",
          ci3(get(external, "measure", "Calibration slope"), get(external, "measure", "Calibration slope", "lower"),
              get(external, "measure", "Calibration slope", "upper"))),
  sprintf("- Mean absolute calibration error %.1f percentage points.",
          100 * get(external, "measure", "Mean absolute calibration error (ICI)")),
  sprintf("- Recurrence-free at 5 years: low-risk group %s observed (%s predicted); high-risk group %s (%s).",
          pct(groups$observed_rfs[1]), pct(groups$predicted_rfs[1]),
          pct(groups$observed_rfs[3]), pct(groups$predicted_rfs[3])),
  sprintf("- Misspecification test: all predictors p = %s; progesterone receptor p = %s; grade p = %s.",
          misspec$p[1], misspec$p[3], misspec$p[2]),
  "",
  "## Subgroups in GBSG 2",
  sprintf("- %s: C-index %.2f, O/E %.2f, calibration slope %.2f (%d patients).",
          subgroups$subgroup[-1], subgroups$c_index[-1], subgroups$oe[-1], subgroups$slope[-1],
          subgroups$patients[-1]),
  "",
  "## Decision curve",
  sprintf("- The model beats treating everyone and treating no one from a %s risk threshold.", pct(useful_from)),
  sprintf("- At %s: treats %d%% of patients, net %.1f unnecessary treatments avoided per 100.",
          pct(dca$threshold), dca$percent_treated_by_model, dca$treatments_avoided_per_100)
)

writeLines(key, file.path("output", "key_numbers.md"))
message("Saved output/tables/subgroup_performance.csv and output/key_numbers.md")
print(subgroups |> select(subgroup, patients, c_index, oe, slope))
