# 02_describe_cohorts.R
#
# Describes the development (Rotterdam) and validation (GBSG 2) cohorts side
# by side (TRIPOD items 13 and 14), and compares their recurrence-free
# survival. Differences in case mix matter: a model can only be expected to
# transport to patients who look like the ones it was built on.
#
# Run from the project root after 01_prepare_data.R:
#   Rscript R/02_describe_cohorts.R
#
# Outputs:
#   output/tables/table1_cohorts.csv
#   output/tables/table1_cohorts.md
#   output/tables/rfs_by_cohort.csv
#   output/figures/rfs_by_cohort.png

suppressPackageStartupMessages({
  library(survival)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})

source(file.path("R", "plot_theme.R"))

development <- readRDS(file.path("data", "processed", "development.rds"))
validation  <- readRDS(file.path("data", "processed", "validation.rds"))
both <- bind_rows(development, validation) |>
  mutate(cohort = factor(cohort, levels = c(unique(development$cohort),
                                            unique(validation$cohort))))

horizon <- 5  # years

# ---------------------------------------------------------------------------
# Table 1
# ---------------------------------------------------------------------------
fmt_n_pct <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return("Not recorded")
  sprintf("%s (%.0f%%)", format(sum(x), big.mark = ","), 100 * mean(x))
}
fmt_median_iqr <- function(x, digits = 0) {
  q <- quantile(x, c(0.5, 0.25, 0.75))
  sprintf(paste0("%.", digits, "f (%.", digits, "f to %.", digits, "f)"),
          q[1], q[2], q[3])
}

# Median follow-up by the reverse Kaplan-Meier method (censoring as the event)
median_followup <- function(d) {
  fit <- survfit(Surv(rfs_time, 1 - rfs_event) ~ 1, data = d)
  unname(summary(fit)$table["median"])
}

# Kaplan-Meier recurrence-free survival at the horizon, with 95% CI
rfs_at <- function(d, t = horizon) {
  s <- summary(survfit(Surv(rfs_time, rfs_event) ~ 1, data = d), times = t)
  c(est = s$surv, lower = s$lower, upper = s$upper)
}

describe <- function(d) {
  r <- rfs_at(d)
  tibble(
    characteristic = c(
      "Patients",
      "Age, years, median (IQR)",
      "Postmenopausal, n (%)",
      "Tumour size 20 mm or less, n (%)",
      "Tumour size 21 to 50 mm, n (%)",
      "Tumour size over 50 mm, n (%)",
      "Grade 3, n (%)",
      "Positive lymph nodes, median (IQR)",
      "1 to 3 positive nodes, n (%)",
      "4 to 9 positive nodes, n (%)",
      "10 or more positive nodes, n (%)",
      "Progesterone receptor, fmol/l, median (IQR)",
      "Oestrogen receptor, fmol/l, median (IQR)",
      "Hormonal therapy, n (%)",
      "Chemotherapy, n (%)",
      "Recurrences or deaths, n",
      "Median follow-up, years",
      sprintf("Recurrence-free at %d years, %% (95%% CI)", horizon)
    ),
    value = c(
      format(nrow(d), big.mark = ","),
      fmt_median_iqr(d$age),
      fmt_n_pct(d$meno == 1),
      fmt_n_pct(d$size == "<=20"),
      fmt_n_pct(d$size == "20-50"),
      fmt_n_pct(d$size == ">50"),
      fmt_n_pct(d$grade == 3),
      fmt_median_iqr(d$nodes),
      fmt_n_pct(d$nodes <= 3),
      fmt_n_pct(d$nodes >= 4 & d$nodes <= 9),
      fmt_n_pct(d$nodes >= 10),
      fmt_median_iqr(d$pgr),
      fmt_median_iqr(d$er),
      fmt_n_pct(d$hormon == 1),
      fmt_n_pct(d$chemo == 1),
      format(sum(d$rfs_event), big.mark = ","),
      sprintf("%.1f", median_followup(d)),
      sprintf("%.0f (%.0f to %.0f)", 100 * r["est"], 100 * r["lower"], 100 * r["upper"])
    )
  )
}

table1 <- describe(development) |>
  rename(`Rotterdam (development)` = value) |>
  left_join(describe(validation) |> rename(`GBSG 2 (validation)` = value),
            by = "characteristic") |>
  rename(Characteristic = characteristic)

dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(table1, file.path("output", "tables", "table1_cohorts.csv"))

md <- c(
  paste0("| ", paste(names(table1), collapse = " | "), " |"),
  paste0("|", paste(rep("---", ncol(table1)), collapse = "|"), "|"),
  apply(table1, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
)
writeLines(md, file.path("output", "tables", "table1_cohorts.md"))

# ---------------------------------------------------------------------------
# Recurrence-free survival by cohort
# ---------------------------------------------------------------------------
km <- survfit(Surv(rfs_time, rfs_event) ~ cohort, data = both)
max_t <- floor(max(validation$rfs_time) * 2) / 2   # GBSG follow-up ends here

curve <- tibble(
  cohort = rep(levels(both$cohort), km$strata),
  time   = km$time,
  surv   = km$surv,
  lower  = km$lower,
  upper  = km$upper
) |>
  group_by(cohort) |>
  group_modify(~ bind_rows(tibble(time = 0, surv = 1, lower = 1, upper = 1), .x)) |>
  ungroup() |>
  filter(time <= max_t) |>
  mutate(cohort = factor(cohort, levels = levels(both$cohort)))

at_h <- both |>
  group_by(cohort) |>
  group_modify(~ as_tibble(as.list(rfs_at(.x)))) |>
  ungroup()
write_csv(at_h |> mutate(years = horizon), file.path("output", "tables", "rfs_by_cohort.csv"))

dev_pct <- round(100 * at_h$est[1])
val_pct <- round(100 * at_h$est[2])

# Label each curve where the two are furthest apart: validation above its
# curve, development below
# (left-aligned above the higher curve, right-aligned below the lower one, so
# neither label crosses a line)
label_t <- 3.1
ends <- curve |>
  filter(time <= label_t) |>
  group_by(cohort) |>
  slice_max(time, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(is_dev = cohort == levels(cohort)[1],
         time   = label_t,
         surv   = ifelse(is_dev, surv - 0.08, surv + 0.07),
         hjust  = ifelse(is_dev, 1, 0),
         label  = as.character(cohort))

p <- ggplot(curve, aes(time, surv, colour = cohort, fill = cohort)) +
  geom_vline(xintercept = horizon, colour = col_mid, linewidth = 0.5, linetype = "dashed") +
  annotate("text", x = horizon, y = 0.03, label = paste(horizon, "years"),
           colour = col_muted, size = 3.2, hjust = -0.1) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.15, colour = NA) +
  geom_step(linewidth = 1) +
  geom_text(data = ends, aes(label = label, hjust = hjust), colour = col_text,
            size = 3.6, fontface = "bold") +
  scale_colour_manual(values = cohort_cols) +
  scale_fill_manual(values = cohort_cols) +
  scale_x_continuous(breaks = 0:7, limits = c(0, max_t + 0.1),
                     expand = expansion(mult = c(0, 0))) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1),
                     breaks = seq(0, 1, 0.25), expand = expansion(mult = c(0, 0.02))) +
  labs(
    title = sprintf("Five years after surgery, %d%% of Rotterdam patients and %d%% of GBSG 2 patients were alive without recurrence", dev_pct, val_pct),
    subtitle = "Kaplan-Meier recurrence-free survival with 95% confidence bands, women with node-positive breast cancer",
    x = "Years since surgery", y = "Alive without recurrence",
    caption = paste(source_note, "Curves are shown to 7 years, where GBSG 2 follow-up ends.")
  ) +
  theme_project()

save_figure(p, "rfs_by_cohort", width = 9, height = 5.5)

message(sprintf("5-year RFS: Rotterdam %d%%, GBSG 2 %d%%", dev_pct, val_pct))
message("Saved output/tables/table1_cohorts.csv, table1_cohorts.md, ",
        "rfs_by_cohort.csv and output/figures/rfs_by_cohort.png")
