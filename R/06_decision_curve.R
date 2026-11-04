# 06_decision_curve.R
#
# Decision curve analysis in GBSG 2 (Vickers and Elkin 2006; Vickers et al.
# 2008 for survival outcomes).
#
# Discrimination and calibration say whether predictions are accurate, not
# whether using them leads to better decisions. A decision curve asks: if
# patients whose predicted 5-year risk is at or above a threshold were offered
# additional treatment, would that do more good than offering it to everyone,
# or to no one?
#
# The threshold expresses how a clinician and patient weigh the harms of
# treatment against the harm of a missed recurrence. A threshold of 40% means
# treating 1 patient who would have recurred is worth treating 1.5 who would
# not (odds 0.4 / 0.6).
#
#   Net benefit = true positives / n - false positives / n x pt / (1 - pt)
#
# where "positive" means predicted risk at or above pt, and true and false
# positives are estimated with Kaplan-Meier at 5 years in that group, so
# censored patients are handled correctly.
#
# Net benefit is computed directly here rather than with a package, so every
# step is visible. The analysis is illustrative: the model uses 1980s data and
# today's treatment decisions use more information than these eight variables.
#
# Run from the project root after 05_external_validation.R:
#   Rscript R/06_decision_curve.R
#
# Outputs:
#   output/tables/decision_curve.csv
#   output/tables/decision_curve_summary.csv
#   output/figures/decision_curve.png

suppressPackageStartupMessages({
  library(survival)
  library(dplyr)
  library(tibble)
  library(readr)
  library(ggplot2)
})

source(file.path("R", "plot_theme.R"))
source(file.path("R", "model_setup.R"))

validation <- readRDS(file.path("data", "processed", "validation_predictions.rds"))

# Kaplan-Meier risk of recurrence or death by the horizon
km_risk <- function(d) {
  s <- summary(survfit(Surv(time5, event5) ~ 1, data = d), times = horizon, extend = TRUE)
  1 - s$surv
}

overall_risk <- km_risk(validation)

net_benefit <- function(pt, data = validation) {
  treated <- data$risk >= pt
  p_treated <- mean(treated)
  if (p_treated == 0) return(0)
  risk_treated <- km_risk(data[treated, ])
  tp <- risk_treated * p_treated
  fp <- (1 - risk_treated) * p_treated
  tp - fp * pt / (1 - pt)
}

thresholds <- seq(0.05, 0.80, by = 0.01)
curve <- tibble(threshold = thresholds) |>
  rowwise() |>
  mutate(
    model     = net_benefit(threshold),
    treat_all = overall_risk - (1 - overall_risk) * threshold / (1 - threshold),
    treat_none = 0,
    share_treated_by_model = mean(validation$risk >= threshold)
  ) |>
  ungroup() |>
  mutate(
    # Net reduction in treatments compared with treating everyone, per 100
    # patients, at no cost in missed recurrences
    treatments_avoided_per_100 = 100 * (model - treat_all) / (threshold / (1 - threshold))
  )

dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(curve |> mutate(across(where(is.double), ~ round(.x, 4))),
          file.path("output", "tables", "decision_curve.csv"))

summary_tab <- curve |>
  filter(round(threshold, 2) %in% round(seq(0.1, 0.7, by = 0.1), 2)) |>
  mutate(best = case_when(
    model > pmax(treat_all, 0) + 0.005 ~ "Model",
    treat_all > 0.005 & abs(model - treat_all) <= 0.005 ~ "Model or treat all",
    TRUE ~ "Treat all"
  )) |>
  transmute(threshold = round(threshold, 2),
            net_benefit_model = round(model, 3),
            net_benefit_treat_all = round(treat_all, 3),
            percent_treated_by_model = round(100 * share_treated_by_model),
            treatments_avoided_per_100 = round(treatments_avoided_per_100, 1),
            best)
write_csv(summary_tab, file.path("output", "tables", "decision_curve_summary.csv"))

# Lowest threshold from which the model beats both alternatives throughout
beats <- curve$model > pmax(curve$treat_all, curve$treat_none) + 0.005
from_idx <- max(which(!beats)) + 1
useful_from <- curve$threshold[from_idx]

at50 <- curve |> filter(abs(threshold - 0.5) < 1e-9)

# ---------------------------------------------------------------------------
# Figure
# ---------------------------------------------------------------------------
long <- bind_rows(
  curve |> transmute(threshold, net_benefit = model, strategy = "Use the model"),
  curve |> transmute(threshold, net_benefit = treat_all, strategy = "Treat everyone"),
  curve |> transmute(threshold, net_benefit = treat_none, strategy = "Treat no one")
)
strategy_cols <- c("Use the model" = col_indigo, "Treat everyone" = col_marigold,
                   "Treat no one" = col_mid)

y_floor <- -0.05
labels <- tibble(
  strategy = c("Use the model", "Treat everyone", "Treat no one"),
  threshold = c(0.62, 0.09, 0.08),
  net_benefit = c(net_benefit(0.62) + 0.035, overall_risk - (1 - overall_risk) * 0.09 / 0.91 + 0.03, 0.018),
  hjust = c(0, 0, 0)
)

p <- ggplot(long, aes(threshold, net_benefit, colour = strategy)) +
  annotate("rect", xmin = useful_from, xmax = 0.8, ymin = -Inf, ymax = Inf,
           fill = "#F1F0F5") +
  annotate("text", x = useful_from + 0.01, y = 0.5, hjust = 0, vjust = 1, size = 3.2,
           colour = col_muted,
           label = sprintf("Model better than both\nalternatives from %.0f%%", 100 * useful_from)) +
  # Model drawn first, so the dashed treat-everyone line stays visible where
  # the two overlap at low thresholds
  geom_line(data = filter(long, strategy == "Use the model"), linewidth = 1.3) +
  geom_line(data = filter(long, strategy == "Treat no one"), linewidth = 0.8) +
  geom_line(data = filter(long, strategy == "Treat everyone"), linewidth = 1,
            linetype = "dashed") +
  geom_text(data = labels, aes(label = strategy, hjust = hjust), colour = col_text,
            size = 3.6, fontface = "bold") +
  scale_colour_manual(values = strategy_cols) +
  scale_x_continuous(labels = scales::percent, breaks = seq(0, 0.8, 0.1),
                     limits = c(0.05, 0.8), expand = expansion(mult = c(0, 0.01))) +
  scale_y_continuous(breaks = seq(0, 0.5, 0.1)) +
  coord_cartesian(ylim = c(y_floor, 0.5)) +
  labs(
    title = sprintf("Using the model to decide who gets extra treatment beats treating everyone once the threshold is %.0f%% or more: at 50%%, it avoids %.0f unnecessary treatments per 100 patients",
                    100 * useful_from, at50$treatments_avoided_per_100),
    subtitle = sprintf("Net benefit in GBSG 2 (n = %d) if patients with a predicted 5-year risk at or above the threshold were treated. Higher is better. The threshold is the risk at which a patient and clinician would choose treatment. Treating everyone is dashed.",
                       nrow(validation)),
    x = "Risk threshold for treatment", y = "Net benefit",
    caption = paste(source_note, "Illustrative: today's decisions use more information than these eight variables.")
  ) +
  theme_project()

save_figure(p, "decision_curve", width = 9.5, height = 6)

message(sprintf("5-year risk in GBSG 2 (Kaplan-Meier): %.3f", overall_risk))
message(sprintf("Model beats treat-all and treat-none from a threshold of %.0f%%", 100 * useful_from))
message(sprintf("At 50%%: model treats %.0f%% of patients and avoids %.1f treatments per 100 compared with treating everyone",
                100 * at50$share_treated_by_model, at50$treatments_avoided_per_100))
print(summary_tab)
