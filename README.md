# Has Philippine Tourism Recovered?

**Live dashboard:** https://fritzbriones.github.io/ph-tourism-recovery/

Monthly international visitor arrivals to the Philippines fell from hundreds of thousands a month to almost zero when the borders closed in 2020, and the country reopened to tourists on 10 February 2022. This project asks two questions:

1. **How far has tourism recovered** compared with 2019, and compared with where it would have been without COVID-19?
2. **When will arrivals pass their 2019 level?**

> **Status:** the pipeline currently runs on a SYNTHETIC placeholder series. The dashboard says so in a banner until the real DOT files are added to `data/raw/`.

## What the dashboard shows

| Panel | Question it answers |
|---|---|
| KPI cards | Year-to-date arrivals, share of the same months of 2019, last-12-months vs 2019, and the forecast month when the 12-month total passes 2019 |
| Recovery gap | Actual arrivals vs a no-COVID counterfactual, and the total visitors lost since March 2020 (with a 95% interval) |
| Model comparison | A naive Prophet forecast that knows nothing about COVID vs an intervention ARIMA model, with 80% and 95% intervals |
| Seasonality | Whether the December–March peak has returned to its 2017–2019 shape |
| Source markets | Which of 2019's top 10 markets are back, and which are lagging |

## Methods in brief

- **Counterfactual:** ETS or ARIMA (picked by rolling-origin cross-validation, MASE) trained on Jan 2010 – Feb 2020 only, then simulated forward 1,000 times.
- **Intervention model:** regression with ARIMA errors on log arrivals, with terms for the March 2020 partial month, the border closure (Apr 2020 – Jan 2022), a level shift after reopening, and an exponentially shrinking post-reopening gap whose speed is chosen by AICc.
- **"Passing 2019":** cumulative arrivals since 2020 can never catch up, so the target is the rolling 12-month total passing the 2019 calendar-year total, estimated across simulated future paths.
- **Checks:** a 12-month hold-out test (RMSE, MAE, MAPE, MASE), Ljung–Box and ACF residual diagnostics, and a CausalImpact (Bayesian structural time series) cross-check.

Full details: [Methods and diagnostics](https://fritzbriones.github.io/ph-tourism-recovery/methods.html).

## Data

**Source:** Department of Tourism, [Philippine Tourism Data Dashboard](https://www.tourism.gov.ph/dot/data/), yearly files of monthly visitor arrivals, 2010 onward (CC BY 4.0).

**Classification change:** the 2010–2021 files count arrivals by **country of residence**, and the 2022 onward files by **country of citizenship**. The national total is comparable across the break and is what the models use. The source market panel crosses the break, so its comparisons are partly definitional; the dashboard notes this under the chart.

Outputs:

| File | Contents |
|---|---|
| `data/dot_arrivals_clean.csv` | National monthly total: `month`, `arrivals`, `classification`, `total_source` |
| `data/dot_arrivals_by_market.csv` | Monthly arrivals by market |
| `output/validation_report.csv` | Result of every validation check |

The pipeline stops if a month is missing, a row is duplicated or a value is negative, and it flags months where a file's total row doesn't match the sum of its markets.

## Reproduce

```r
# 1. Install the packages listed in DESCRIPTION, or restore renv.lock if present
install.packages(c("targets", "tarchetypes", "fable", "fable.prophet", "fabletools",
                   "feasts", "tsibble", "CausalImpact", "plotly", "quarto",
                   "tidyverse", "jsonlite", "urca"))

# 2. Put the DOT yearly CSV files in data/raw/

# 3. Run everything: ingest, validate, model, render the dashboard
targets::tar_make()

targets::tar_visnetwork()   # see the pipeline graph
```

The site is written to `_site/`. Pushing to `main` runs the same pipeline on GitHub Actions and publishes it to GitHub Pages.

## Repository layout

```
_targets.R          pipeline definition
R/ingest.R          read and bind the yearly DOT files
R/validate.R        data checks
R/models.R          counterfactual, naive Prophet, intervention ARIMA, CausalImpact
R/kpis.R            recovery metrics, crossing date, markets, seasonality
R/placeholder.R     synthetic test data (used only while data/raw/ is empty)
index.qmd           dashboard
methods.qmd         methods and diagnostics
data/raw/           DOT files, unchanged
```

## Limitations

- The counterfactual assumes the 2010–2019 trend would have continued. Exchange rates, airline capacity, visa rules and one-off events (such as the 2018 Boracay closure) aren't modelled.
- Forecast intervals assume the post-reopening pattern holds; a new shock would invalidate them.
