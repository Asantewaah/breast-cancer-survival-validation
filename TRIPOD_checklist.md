# TRIPOD+AI checklist

This project develops a prediction model and evaluates it in separate data, so it is reported against the [TRIPOD+AI statement](https://doi.org/10.1136/bmj-2023-078378) (Collins et al., *BMJ* 2024;385:e078378), which replaced TRIPOD 2015. D means the item applies to development, E to evaluation.

"README" refers to sections of the [README](README.md). Items that a portfolio project cannot meet in the way a journal article would, such as ethics approval or a protocol, are answered honestly rather than left out.

| Item | Topic | Applies to | Where it is reported |
|---|---|---|---|
| 1 | Title | D;E | README title and first paragraph: development and external validation of a Cox prognostic model for recurrence-free survival in women with node-positive breast cancer |
| 2 | Abstract | D;E | README, Key findings (a summary rather than a structured abstract) |
| 3a | Background: context | D;E | README introduction; prognostic model; Royston and Altman (2013) is the existing reference model for these data |
| 3b | Background: purpose | D;E | README introduction: estimate 5-year risk of recurrence or death after surgery, for clinicians and patients deciding on further treatment |
| 3c | Background: inequalities | D;E | Not addressed: the data hold no sociodemographic variables (see item 14) |
| 4 | Objectives | D;E | README introduction: develop in Rotterdam, evaluate in GBSG 2 |
| 5a | Data sources | D;E | README, Data; both datasets from the `survival` R package |
| 5b | Data dates | D;E | README, Data: Rotterdam surgery 1978 to 1993; GBSG 2 recruitment 1984 to 1989; follow-up to 19.2 and 7.3 years |
| 6a | Setting | D;E | README, Data: Rotterdam tumour bank (single centre, Netherlands); GBSG 2 multicentre trial (Germany). Number of GBSG 2 centres not available in these data |
| 6b | Eligibility | D;E | README, Definitions: women with node-positive breast cancer; Rotterdam restricted to node-positive to match GBSG 2 |
| 6c | Treatments | D;E | README, Definitions and Model: hormonal therapy is a predictor; chemotherapy is recorded in Rotterdam only and cannot be used; GBSG 2 randomised tamoxifen |
| 7 | Data preparation | D;E | `R/01_prepare_data.R` with checks written to `output/tables/data_checks.csv`; README, Definitions (size bands, grade coding, late deaths) |
| 8a | Outcome | D;E | README, Definitions: recurrence-free survival (recurrence or death from any cause), predicted at 5 years |
| 8b | Outcome assessors | D;E | Not available in these data |
| 8c | Outcome blinding | D;E | Not available in these data |
| 9a | Initial predictors | D | README, The prognostic model: all eight predictors available in both cohorts, chosen in advance; no data-driven selection |
| 9b | Predictor definitions | D;E | README, Definitions; `R/model_setup.R` (coding of grade, nodes, receptors) |
| 9c | Predictor assessors | D;E | Not available in these data; grade may have been recorded differently in the two cohorts (README, The two cohorts) |
| 10 | Sample size | D;E | README, The prognostic model: 853 events and 12 parameters, about 71 events per parameter. GBSG 2: 285 events within 5 years, above the 100 to 200 events usually recommended for external validation |
| 11 | Missing data | D;E | README, Definitions: no missing values in either dataset |
| 12a | Data use | D | Rotterdam for development and bootstrap internal validation only; GBSG 2 for evaluation only |
| 12b | Predictor handling | D | README, The prognostic model: restricted cubic splines (3 knots) for age, nodes (capped at 20) and log progesterone receptor; log oestrogen receptor |
| 12c | Model building | D | README, The prognostic model and Internal validation: Cox proportional hazards model, follow-up censored at 5 years, 500 bootstrap samples for optimism |
| 12d | Cluster heterogeneity | D;E | Not examined: centre is not recorded |
| 12e | Performance measures | D;E | README, Internal and External validation: Harrell's and Uno's C-index, observed/expected, calibration slope, flexible calibration curve, risk-group curves, net benefit |
| 12f | Model updating | E | No updating: the model was evaluated exactly as developed |
| 12g | Prediction calculation | E | `R/05_external_validation.R`: 5-year risk from the Cox model's baseline survival and linear predictor |
| 13 | Class imbalance | D;E | Not applicable: no resampling or reweighting; about half of patients have the outcome |
| 14 | Fairness | D;E | Performance checked by menopausal status and hormonal therapy (README, External validation). No sociodemographic variables are available, so fairness across groups such as ethnicity or deprivation cannot be assessed |
| 15 | Model output | D | Predicted 5-year risk of recurrence or death; no classification threshold is set, and the decision curve shows the consequences of a range of thresholds |
| 16 | Data differences | D;E | README, The two cohorts: GBSG 2 has fewer large and grade 3 tumours, lower oestrogen receptor levels, more hormonal therapy and shorter follow-up |
| 17 | Ethics | D;E | Secondary analysis of anonymised, publicly available data distributed with the `survival` R package; no ethics approval was sought |
| 18a | Funding | D;E | None: an independent portfolio project |
| 18b | Conflicts of interest | D;E | None |
| 18c | Protocol | D;E | No formal protocol; the analysis plan is the numbered sequence of scripts, committed step by step with dates in the Git history |
| 18d | Registration | D;E | Not registered |
| 18e | Data sharing | D;E | Data are in the `survival` R package |
| 18f | Code sharing | D;E | All code in this repository; package versions pinned with renv |
| 19 | Patient and public involvement | D;E | None |
| 20a | Participant flow | D;E | README, Data: 2,982 Rotterdam patients, 1,546 node-positive included; 686 GBSG 2 patients; events and follow-up in Table 1 |
| 20b | Participant characteristics | D;E | README, Table 1 |
| 20c | Evaluation data distribution | E | README, Table 1 and The two cohorts |
| 21 | Analysis counts | D;E | README: 853 events within 5 years for development; 285 for evaluation |
| 22 | Full model | D | `output/tables/model_coefficients.csv`: coefficients, spline knots, baseline 5-year survival and centring constant |
| 23a | Performance estimates | D;E | README, Internal and External validation, with 95% CIs; subgroups in `output/tables/subgroup_performance.csv` |
| 23b | Cluster performance | D;E | Not examined (see 12d) |
| 24 | Model updating results | E | Not applicable (see 12f) |
| 25 | Interpretation | D;E | README, Key findings and External validation |
| 26 | Limitations | D;E | README, Limitations |
| 27a | Poor-quality inputs | D | README, Limitations: grade recording differs between centres; the model expects the same predictor definitions |
| 27b | User requirements | D | Inputs are routine pathology and clinical variables; using the model needs the coefficients file or this code |
| 27c | Next steps | D;E | README, Limitations: validation in a contemporary cohort with modern treatment |
