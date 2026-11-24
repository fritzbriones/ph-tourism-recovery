# Has Philippine Tourism Recovered?

**Live dashboard:** https://fritzbriones.github.io/ph-tourism-recovery/

Monthly international visitor arrivals to the Philippines fell from hundreds of thousands a month to almost zero when the borders closed in 2020, and the country reopened to tourists on 10 February 2022. This project asks two questions:

1. **How far has tourism recovered** compared with 2019, and compared with where it would have been without COVID-19?
2. **When will arrivals pass their 2019 level?**

## Key findings (data to August 2026)

- **Recovery has stalled at about 79% of 2019.** January–August 2026 had 4,415,860 arrivals vs 5,554,950 in the same months of 2019. The last 12 months total 6.52M vs 8,260,913 in 2019. Growth was only +0.8% in 2025 and +0.8% so far in 2026.
- **The shock:** while the borders were closed (April 2020 – January 2022), arrivals were about 99% below the level the intervention model expects without the closure.
- **The gap:** compared with a no-COVID projection of the 2010–2019 trend, about 44 million visits were lost from March 2020 to August 2026 (95% interval 41–47 million).
- **Passing 2019 is not the likely outcome:** the best-performing forecast gives about a one-in-three chance that a 12-month total passes 2019 by the end of 2030.
- **The recovery is uneven:** Canada (145%), Australia (128%), the United States (122%) and the United Kingdom (106%) are above 2019, while South Korea (57%) and China (25%) are far below. Because 2019 counts include non-resident Filipinos by country of residence and 2022+ counts exclude them, the comparison is partly definitional; China and Korea, with few non-resident Filipinos, are the cleanest.

Every one of the 17 yearly files was checked: monthly totals add up exactly to DOT's reported annual totals, from 3,520,471 (2010) to 6,484,060 (2025).

## What the dashboard shows

| Panel | Question it answers |
|---|---|
| KPI cards | Year-to-date arrivals, share of the same months of 2019, last-12-months vs 2019, and the forecast month when the 12-month total passes 2019 |
| Recovery gap | Actual arrivals vs a no-COVID counterfactual, and the total visitors lost since March 2020 (with a 95% interval) |
| Model comparison | A naive Prophet forecast that knows nothing about COVID vs an intervention ARIMA model, with 80% and 95% intervals |
| Seasonality | Whether the December–March peak has returned to its 2017–2019 shape |
| Source markets | Which of 2019's top 10 markets are back, and which are lagging |

## Methods in brief

- **Counterfactual:** ETS or ARIMA (picked by rolling-origin cross-validation, MASE) trained on Jan 2010 – Feb 2020 only, then simulated forward 1,000 times. ARIMA won.
- **Measuring the shock (interrupted time series):** regression with ARIMA errors on log arrivals, with terms for the March 2020 partial month, the border closure (Apr 2020 – Jan 2022), a level shift after reopening, and an exponentially shrinking post-reopening gap whose speed is chosen by AICc.
- **Forecasting:** three models scored on the last 12 months. The post-reopening ARIMA (fitted on 2023 onward) has a 4.9% MAPE; the intervention ARIMA, which assumes a return to pre-COVID growth, has 20%; the naive Prophet model, 214%. The post-reopening model is the headline forecast; the others are shown for comparison.
- **"Passing 2019":** cumulative arrivals since 2020 can never catch up, so the target is the rolling 12-month total passing the 2019 calendar-year total, estimated across 1,000 simulated future paths.
- **Checks:** Ljung–Box and ACF residual diagnostics (the post-reopening model passes, the intervention model does not, and the methods page says so), and a CausalImpact (Bayesian structural time series) cross-check when that package is installed.
- **Missing month:** DOT did not collect January 2022 (reporting restarted in February). It stays blank in the published data and is interpolated only inside the intervention model.

Full details: [Methods and diagnostics](https://fritzbriones.github.io/ph-tourism-recovery/methods.html).

## Data

**Source:** Department of Tourism, [Philippine Tourism Data Dashboard](https://www.tourism.gov.ph/dot/data/), yearly files of monthly visitor arrivals, 2010 onward (CC BY 4.0).

**Classification change:** the 2010–2021 files count arrivals by **country of residence**, and the 2022 onward files by **country of citizenship**. The national total is comparable across the break and is what the models use. The source market panel crosses the break, so its comparisons are partly definitional; the dashboard notes this under the chart.

Outputs:

| File | Contents |
|---|---|
| `data/raw/` | The 17 DOT yearly CSVs, unchanged |
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

# 2. The DOT yearly CSVs are already in data/raw/.
#    To refresh them with a new month, replace the latest file (or run R/download.R)

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
R/markets.R         market-name crosswalk across the 2022 classification change
R/download.R        optional helper to fetch new DOT files
R/placeholder.R     synthetic test data (used only if data/raw/ is empty)
index.qmd           dashboard
methods.qmd         methods and diagnostics
data/raw/           DOT files, unchanged
```

## Limitations

- The counterfactual assumes the 2010–2019 trend would have continued. Exchange rates, airline capacity, visa rules and one-off events (such as the 2018 Boracay closure) aren't modelled.
- Forecast intervals assume the post-reopening pattern holds; a new shock would invalidate them.
