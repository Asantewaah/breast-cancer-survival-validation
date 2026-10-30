# Does a breast cancer prognostic model still work on new patients?

A model that predicts how likely a breast cancer is to come back can look excellent in the hospital where it was built and still mislead clinicians somewhere else. This project builds a Cox prognostic model for recurrence-free survival in one cohort of women with node-positive breast cancer, then tests it on patients from a separate clinical trial it has never seen: how well it ranks patients, whether its predicted risks match what actually happened, and whether using it would lead to better treatment decisions than treating everyone or no one.

> Work in progress. This README grows as each stage of the analysis is completed.

## Data

Both datasets ship with the [`survival`](https://cran.r-project.org/package=survival) R package, so nothing needs downloading. Using them for development and validation follows Royston and Altman (2013), [External validation of a Cox prognostic model: principles and methods](https://doi.org/10.1186/1471-2288-13-33), *BMC Medical Research Methodology* 13:33.

| Role | Cohort | Patients | Recurrence-free survival events |
|---|---|---|---|
| Development | Rotterdam tumour bank, node-positive patients, surgery 1978 to 1993 | 1,546 | 1,059 |
| External validation | German Breast Cancer Study Group (GBSG 2) trial, recruited 1984 to 1989 | 686 | 299 |

### Definitions and data notes

- **Outcome:** recurrence-free survival (RFS), the time to the first of breast cancer recurrence or death from any cause.
- **Same population:** GBSG 2 only recruited women with cancer in at least one lymph node, so the model is developed on the node-positive Rotterdam patients only.
- **Late deaths:** in Rotterdam, 21 node-positive patients died without a recorded recurrence but after their last recurrence check. A recurrence in that gap could have gone unrecorded, so they are censored at their last check, as in the `survival` package's own example. A sensitivity analysis counts them as events at death instead.
- **Tumour size:** GBSG records size in mm, Rotterdam in three bands (20 mm or less, 21 to 50 mm, over 50 mm), so GBSG sizes are put into the same bands.
- **Grade:** Rotterdam has no grade 1 tumours, so grade enters the model as grade 3 against grades 1 to 2.
- **Chemotherapy:** GBSG has no chemotherapy variable, so it cannot be a predictor.
- **Follow-up:** GBSG follow-up ends at 7.3 years, so predictions are assessed at 5 years.
- No values are missing in either dataset.

## Approach

Reported following the [TRIPOD](https://www.tripod-statement.org/) guideline for prediction model studies.

1. Prepare the development and validation data
2. Describe both cohorts and compare their case mix
3. Develop a Cox model for recurrence-free survival in Rotterdam
4. Internal validation with bootstrapping, to estimate optimism
5. External validation in GBSG 2: discrimination (C-index) and calibration (calibration slope and calibration plot at 5 years)
6. Decision curve analysis: is the model useful for deciding who needs further treatment?
7. Write-up of findings and the TRIPOD checklist

## Progress

- [x] Project setup
- [x] Data preparation
- [ ] Cohort description
- [ ] Model development
- [ ] Internal validation
- [ ] External validation
- [ ] Decision curve analysis
- [ ] Write-up of findings

## Repository structure

```
R/                 analysis scripts, run in numbered order
data/processed/    analysis datasets built by script (not tracked)
output/figures/    charts used in this README
output/tables/     summary tables and model results
```

## Reproducing the analysis

Requires R 4.3 or later. Package versions are pinned with [renv](https://rstudio.github.io/renv/).

From the project root:

```r
renv::restore()
```

```bash
Rscript R/01_prepare_data.R   # build the development and validation datasets
```

## Author

Juliet Asantewaa Sarpong, PhD researcher in Statistics, University of Edinburgh. [Portfolio](https://asantewaah.github.io)
