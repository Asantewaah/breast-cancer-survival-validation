# model_setup.R
#
# Shared settings and helpers for the modelling scripts (03 to 06), so the
# development and validation data are always coded the same way. Sourced by
# the analysis scripts; not run on its own.

suppressPackageStartupMessages({
  library(dplyr)
  library(rms)
})

horizon <- 5  # prediction horizon, years

# Predictor coding used by the model
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

# Development data, coded and censored at the horizon, with the rms datadist
# set so model summaries use its ranges
load_development <- function() {
  d <- readRDS(file.path("data", "processed", "development.rds")) |>
    add_model_vars()
  cens <- censor_at(d$rfs_time, d$rfs_event)
  d$time5  <- cens$time
  d$event5 <- cens$event
  assign("dd", datadist(d), envir = globalenv())
  options(datadist = "dd")
  d
}

# Harrell's C-index from an rms fit
c_index <- function(f) unname((f$stats["Dxy"] + 1) / 2)
