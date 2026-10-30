# 01_prepare_data.R
#
# Builds the two analysis datasets for the project:
#
#   Development: Rotterdam tumour bank, node-positive patients (n = 1,546),
#                surgery 1978 to 1993. Used to fit the prognostic model.
#   Validation:  German Breast Cancer Study Group (GBSG 2) trial (n = 686),
#                recruited 1984 to 1989. Used only to test the model.
#
# Both datasets ship with the survival package, so nothing is downloaded.
# Using them this way follows Royston and Altman (2013), "External validation
# of a Cox prognostic model: principles and methods", BMC Medical Research
# Methodology 13:33.
#
# Outcome: recurrence-free survival (RFS), meaning time to the first of
# recurrence or death from any cause, in years.
#
# Run from the project root:
#   Rscript R/01_prepare_data.R
#
# Outputs:
#   data/processed/development.rds
#   data/processed/validation.rds
#   output/tables/data_checks.csv

suppressPackageStartupMessages({
  library(survival)
  library(dplyr)
  library(readr)
})

dir.create(file.path("data", "processed"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)

days_per_year <- 365.25

# ---------------------------------------------------------------------------
# Development data: Rotterdam
# ---------------------------------------------------------------------------
# Rotterdam records recurrence and death separately. RFS is the first of the
# two: a recurrence at its recurrence time, otherwise a death at its death time.
#
# Data note (see help(rotterdam)): some patients died without a recorded
# recurrence but after their last recurrence check (dtime > rtime). Their
# death date was probably added from the health record after follow-up for
# recurrence had stopped, so we cannot assume they were recurrence free up to
# death. Following the survival package's own example, they are censored at
# their last recurrence check. 03_develop_model.R repeats the fit with them
# counted as events at death, as a sensitivity analysis.
rotterdam_all <- survival::rotterdam

development <- rotterdam_all |>
  # GBSG 2 only recruited patients with positive lymph nodes, so the model is
  # developed on the same population it will be validated in.
  filter(nodes > 0) |>
  mutate(
    late_death = recur == 0 & death == 1 & dtime > rtime,
    rfs_event  = ifelse(recur == 1 | late_death, recur, death),
    rfs_time   = ifelse(recur == 1 | late_death, rtime, dtime) / days_per_year,
    # Kept for the sensitivity analysis: late deaths counted as events at death
    rfs_event_alt = pmax(recur, death),
    rfs_time_alt  = ifelse(recur == 1, rtime, dtime) / days_per_year,
    size      = factor(as.character(size), levels = c("<=20", "20-50", ">50")),
    cohort    = "Rotterdam (development)"
  ) |>
  select(pid, cohort, age, meno, size, grade, nodes, pgr, er, hormon, chemo,
         rfs_time, rfs_event, late_death, rfs_time_alt, rfs_event_alt)

late_deaths <- sum(development$late_death)

# ---------------------------------------------------------------------------
# Validation data: GBSG 2
# ---------------------------------------------------------------------------
# GBSG records tumour size in mm; Rotterdam only has three size bands, so the
# validation data are put on the same scale. GBSG has no chemotherapy
# variable, so chemotherapy cannot be a predictor.
validation <- survival::gbsg |>
  mutate(
    rfs_event = status,
    rfs_time  = rfstime / days_per_year,
    size      = cut(size, breaks = c(-Inf, 20, 50, Inf),
                    labels = c("<=20", "20-50", ">50")),
    chemo     = NA_integer_,
    cohort    = "GBSG 2 (validation)"
  ) |>
  select(pid, cohort, age, meno, size, grade, nodes, pgr, er, hormon, chemo,
         rfs_time, rfs_event)

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
check_cohort <- function(d) {
  tibble(
    cohort          = unique(d$cohort),
    patients        = nrow(d),
    rfs_events      = sum(d$rfs_event),
    missing_values  = sum(is.na(select(d, cohort:rfs_event, -chemo))),
    median_followup = round(median(d$rfs_time[d$rfs_event == 0]), 2),
    max_followup    = round(max(d$rfs_time), 2),
    grade_values    = paste(sort(unique(d$grade)), collapse = ", ")
  )
}

checks <- bind_rows(check_cohort(development), check_cohort(validation))

stopifnot(
  nrow(development) == 1546,
  nrow(validation)  == 686,
  all(development$nodes > 0),
  all(validation$nodes > 0),
  checks$missing_values == 0,
  all(development$rfs_time > 0),
  all(validation$rfs_time > 0)
)

saveRDS(development, file.path("data", "processed", "development.rds"))
saveRDS(validation,  file.path("data", "processed", "validation.rds"))
write_csv(checks, file.path("output", "tables", "data_checks.csv"))

message("Development: ", nrow(development), " patients, ",
        sum(development$rfs_event), " RFS events")
message("Validation:  ", nrow(validation), " patients, ",
        sum(validation$rfs_event), " RFS events")
message("Rotterdam deaths after the last recurrence check, censored at that check: ",
        late_deaths)
message("Grade in development: ", checks$grade_values[1],
        "; in validation: ", checks$grade_values[2],
        " (Rotterdam has no grade 1, so grade will enter the model as 3 vs 1 to 2)")
message("Saved data/processed/development.rds, validation.rds and ",
        "output/tables/data_checks.csv")
