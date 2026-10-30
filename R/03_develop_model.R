# 03_develop_model.R
#
# Develops the Cox prognostic model for recurrence-free survival in the
# Rotterdam (development) cohort.
#
# Design choices, fixed before looking at validation data:
#
#   Predictors: all eight available in both cohorts, chosen from clinical
#   knowledge rather than by statistical selection, which tends to overfit.
#   Age, number of positive nodes and progesterone receptor get restricted
#   cubic splines (3 knots) because their effects are unlikely to be linear.
#   Oestrogen receptor enters on the log scale. Nodes are capped at 20 so a
#   few extreme counts do not drive the curve.
#
#   Follow-up: censored at 5 years. The model only needs to predict 5-year
#   risk, and hormone receptor effects are known to fade over time, so fitting
#   to the first 5 years keeps the model focused on the period it predicts.
#
#   Hormonal therapy is included as a predictor, as in Royston and Altman
#   (2013). It is a treatment, not a patient characteristic, so its hazard
#   ratio should not be read as the effect of tamoxifen.
#
# With 853 events in 5 years and 12 model parameters, there are about 71
# events per parameter, well above the usual minimum for a Cox model.
#
# Run from the project root after 01_prepare_data.R:
#   Rscript R/03_develop_model.R
#
# Outputs:
#   data/processed/cox_model.rds
#   output/tables/model_hazard_ratios.csv
#   output/tables/model_coefficients.csv
#   output/tables/proportional_hazards.csv
#   output/tables/sensitivity_late_deaths.csv
#   output/figures/hazard_ratios.png

suppressPackageStartupMessages({
  library(survival)
  library(rms)
  library(dplyr)
  library(tibble)
  library(readr)
  library(ggplot2)
})

source(file.path("R", "plot_theme.R"))

horizon <- 5  # years

# Predictor coding, shared with the validation scripts
add_model_vars <- function(d) {
  d |>
    mutate(
      grade3  = as.integer(grade == 3),
      nodes20 = pmin(nodes, 20),
      lpgr    = log(pgr + 1),
      ler     = log(er + 1)
    )
}

# Administrative censoring at the prediction horizon
censor_at <- function(time, event, h = horizon) {
  list(time = pmin(time, h), event = ifelse(time > h, 0L, as.integer(event)))
}

development <- readRDS(file.path("data", "processed", "development.rds")) |>
  add_model_vars()

cens <- censor_at(development$rfs_time, development$rfs_event)
development$time5  <- cens$time
development$event5 <- cens$event

dd <- datadist(development)
options(datadist = "dd")

model_formula <- Surv(time5, event5) ~ rcs(age, 3) + meno + size + grade3 +
  rcs(nodes20, 3) + rcs(lpgr, 3) + ler + hormon

fit <- cph(model_formula, data = development, x = TRUE, y = TRUE,
           surv = TRUE, time.inc = horizon)

n_events <- sum(development$event5)
n_params <- length(coef(fit))

# ---------------------------------------------------------------------------
# Hazard ratios (interquartile range for continuous predictors)
# ---------------------------------------------------------------------------
s <- summary(fit, size = "<=20")
hr_rows <- which(rownames(s) == " Hazard Ratio")
hr <- tibble(
  term     = rownames(s)[hr_rows - 1],
  low      = s[hr_rows - 1, "Low"],
  high     = s[hr_rows - 1, "High"],
  hr       = s[hr_rows, "Effect"],
  hr_lower = s[hr_rows, "Lower 0.95"],
  hr_upper = s[hr_rows, "Upper 0.95"]
)

labels <- c(
  "age"     = "Age",
  "meno"    = "Postmenopausal",
  "grade3"  = "Grade 3",
  "nodes20" = "Positive lymph nodes",
  "lpgr"    = "Progesterone receptor",
  "ler"     = "Oestrogen receptor",
  "hormon"  = "Hormonal therapy"
)

hr <- hr |>
  mutate(
    predictor = case_when(
      term == "size - 20-50:<=20" ~ "Tumour 21 to 50 mm",
      term == "size - >50:<=20"   ~ "Tumour over 50 mm",
      TRUE ~ unname(labels[term])
    ),
    comparison = case_when(
      term == "age"     ~ sprintf("%.0f vs %.0f years", high, low),
      term == "nodes20" ~ sprintf("%.0f vs %.0f nodes", high, low),
      term == "lpgr"    ~ sprintf("%.0f vs %.0f fmol/l", exp(high) - 1, exp(low) - 1),
      term == "ler"     ~ sprintf("%.0f vs %.0f fmol/l", exp(high) - 1, exp(low) - 1),
      grepl("^size", term) ~ "vs 20 mm or less",
      TRUE ~ "yes vs no"
    )
  ) |>
  select(predictor, comparison, hr, hr_lower, hr_upper)

dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(hr |> mutate(across(where(is.numeric), ~ round(.x, 3))),
          file.path("output", "tables", "model_hazard_ratios.csv"))

# ---------------------------------------------------------------------------
# Full model, so anyone can reproduce its predictions (TRIPOD item 15)
# ---------------------------------------------------------------------------
# Predicted 5-year RFS for a patient is S0_5 ^ exp(LP - centre), where LP is
# the sum of coefficients times the patient's predictor values (splines use
# the rms restricted cubic spline basis with the knots below).
lp_centre <- fit$center
S0_5 <- as.numeric(summary(survfit(fit), times = horizon)$surv)

# Check the hand formula reproduces the software's predictions
check_rows <- development[1:20, ]
by_hand <- S0_5 ^ exp(predict(fit, newdata = check_rows, type = "lp"))
by_rms  <- survest(fit, newdata = check_rows, times = horizon)$surv
stopifnot(max(abs(by_hand - by_rms)) < 1e-6)

knots <- sapply(c("age", "nodes20", "lpgr"), function(v) {
  paste(round(fit$Design$parms[[v]], 3), collapse = ", ")
})

coefs <- tibble(term = names(coef(fit)), coefficient = unname(coef(fit))) |>
  bind_rows(tibble(
    term = c("linear predictor centre", "baseline 5-year RFS at centre",
             paste("spline knots:", names(knots))),
    coefficient = c(lp_centre, S0_5, NA, NA, NA)
  )) |>
  mutate(note = c(rep(NA_character_, n_params), NA, NA, unname(knots)))

write_csv(coefs, file.path("output", "tables", "model_coefficients.csv"))

# ---------------------------------------------------------------------------
# Proportional hazards check
# ---------------------------------------------------------------------------
zph <- cox.zph(fit)
ph <- tibble(term = rownames(zph$table),
             chisq = round(zph$table[, "chisq"], 2),
             df = zph$table[, "df"],
             p = signif(zph$table[, "p"], 2))
write_csv(ph, file.path("output", "tables", "proportional_hazards.csv"))

# ---------------------------------------------------------------------------
# Sensitivity: late deaths counted as events at death
# ---------------------------------------------------------------------------
cens_alt <- censor_at(development$rfs_time_alt, development$rfs_event_alt)
dev_alt <- development |> mutate(time5 = cens_alt$time, event5 = cens_alt$event)
fit_alt <- cph(model_formula, data = dev_alt, x = TRUE, y = TRUE)

c_index <- function(f) unname((f$stats["Dxy"] + 1) / 2)
sens <- tibble(
  analysis = c("Main: late deaths censored at last recurrence check",
               "Sensitivity: late deaths counted as events at death"),
  events_5y = c(n_events, sum(dev_alt$event5)),
  c_index   = round(c(c_index(fit), c_index(fit_alt)), 3),
  max_abs_coef_change = c(NA, round(max(abs(coef(fit_alt) - coef(fit))), 3))
)
write_csv(sens, file.path("output", "tables", "sensitivity_late_deaths.csv"))

saveRDS(fit, file.path("data", "processed", "cox_model.rds"))

# ---------------------------------------------------------------------------
# Figure: hazard ratios
# ---------------------------------------------------------------------------
order <- c("Age", "Postmenopausal", "Tumour 21 to 50 mm", "Tumour over 50 mm",
           "Grade 3", "Positive lymph nodes", "Progesterone receptor",
           "Oestrogen receptor", "Hormonal therapy")
plot_hr <- hr |>
  arrange(match(predictor, order)) |>
  mutate(label = paste0(predictor, "\n", comparison),
         label = factor(label, levels = rev(label)),
         strongest = predictor == predictor[which.max(abs(log(hr)))])

top <- plot_hr |> filter(strongest)

p <- ggplot(plot_hr, aes(hr, label)) +
  geom_vline(xintercept = 1, colour = col_mid, linewidth = 0.5) +
  geom_errorbarh(aes(xmin = hr_lower, xmax = hr_upper), height = 0,
                 colour = col_indigo, linewidth = 0.8) +
  geom_point(aes(colour = strongest), size = 3) +
  geom_text(aes(label = sprintf("%.2f", hr)), nudge_y = 0.32, size = 3.2,
            colour = col_text) +
  scale_colour_manual(values = c(`TRUE` = col_marigold, `FALSE` = col_indigo)) +
  scale_x_log10(breaks = c(0.5, 0.75, 1, 1.5, 2, 3)) +
  labs(
    title = if (top$predictor == "Positive lymph nodes") {
      sprintf("The number of positive lymph nodes is the strongest predictor: with %s rather than %s nodes, the risk of recurrence or death is %.1f times higher",
              sub(" vs.*", "", top$comparison), sub(".*vs ([0-9]+).*", "\\1", top$comparison), top$hr)
    } else {
      sprintf("%s is the strongest predictor of recurrence or death (hazard ratio %.1f, %s)",
              top$predictor, top$hr, top$comparison)
    },
    subtitle = sprintf("Hazard ratios with 95%% confidence intervals from the Cox model, Rotterdam node-positive patients, first %d years (%s events). Continuous predictors compare the 75th with the 25th percentile.",
                       horizon, format(n_events, big.mark = ",")),
    x = "Hazard ratio (log scale)", y = NULL,
    caption = paste(source_note, "Hormonal therapy is a treatment given to some patients, so its hazard ratio is not the effect of tamoxifen.")
  ) +
  theme_project() +
  theme(axis.text.y = element_text(colour = col_text, size = rel(0.95), hjust = 0),
        panel.grid.major.y = element_blank())

save_figure(p, "hazard_ratios", width = 10, height = 6.5)

message("Model: ", n_params, " parameters, ", n_events, " events in ", horizon,
        " years (", round(n_events / n_params), " per parameter)")
message("Apparent C-index: ", round(c_index(fit), 3))
message("Baseline ", horizon, "-year RFS at the mean linear predictor: ", round(S0_5, 3))
message("Proportional hazards, global test p = ", signif(zph$table["GLOBAL", "p"], 2))
message("Sensitivity (late deaths as events): C-index ", round(c_index(fit_alt), 3),
        ", largest coefficient change ", sens$max_abs_coef_change[2])
