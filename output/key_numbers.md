# Key numbers

Generated 04 November 2026 by `R/07_summary.R` from the tables in `output/tables/`.

## Data
- Development: Rotterdam, 1,546 node-positive patients, 1,059 recurrence-free survival events.
- Validation: GBSG 2, 686 patients, 299 events.
- 5-year recurrence-free survival: Rotterdam 44%, GBSG 2 49%.

## Model
- Strongest predictor: positive lymph nodes, 7 vs 2 nodes, hazard ratio 2.29 (95% CI 1.97 to 2.66).
- C-index in Rotterdam: apparent 0.689, optimism-corrected 0.684.
- Optimism-corrected calibration slope: 0.955.

## External validation in GBSG 2
- Harrell's C-index 0.69 (95% CI 0.66 to 0.72); Uno's 0.68.
- Observed 5-year risk 51% against 48% predicted; observed/expected 1.06 (95% CI 0.97 to 1.15).
- Calibration slope 0.99 (95% CI 0.81 to 1.18).
- Mean absolute calibration error 3.4 percentage points.
- Recurrence-free at 5 years: low-risk group 65% observed (69% predicted); high-risk group 19% (21%).
- Misspecification test: all predictors p = 0.037; progesterone receptor p = 0.0056; grade p = 0.36.

## Subgroups in GBSG 2
- Premenopausal: C-index 0.71, O/E 0.99, calibration slope 1.22 (290 patients).
- Postmenopausal: C-index 0.68, O/E 1.10, calibration slope 0.86 (396 patients).
- No hormonal therapy: C-index 0.67, O/E 1.08, calibration slope 0.85 (440 patients).
- Hormonal therapy: C-index 0.72, O/E 1.03, calibration slope 1.45 (246 patients).

## Decision curve
- The model beats treating everyone and treating no one from a 27% risk threshold.
- At 10%: treats 100% of patients, net 0.0 unnecessary treatments avoided per 100.
- At 20%: treats 97% of patients, net -0.5 unnecessary treatments avoided per 100.
- At 30%: treats 78% of patients, net 3.5 unnecessary treatments avoided per 100.
- At 40%: treats 57% of patients, net 5.9 unnecessary treatments avoided per 100.
- At 50%: treats 43% of patients, net 15.9 unnecessary treatments avoided per 100.
- At 60%: treats 31% of patients, net 23.8 unnecessary treatments avoided per 100.
- At 70%: treats 17% of patients, net 30.2 unnecessary treatments avoided per 100.
