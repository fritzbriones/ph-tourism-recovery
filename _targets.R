# ==============================================================================
# Pipeline: raw DOT files -> validation -> clean data -> models -> dashboard
# Run with targets::tar_make(); view the graph with targets::tar_visnetwork().
# ==============================================================================

library(targets)
library(tarchetypes)

tar_option_set(packages = c("dplyr", "tsibble", "fable", "fabletools", "feasts"))
tar_source("R")

list(
  # ---- Data ------------------------------------------------------------------
  # Re-checked on every run, so adding a file to data/raw/ triggers a rebuild
  tar_target(raw_paths, list_raw_files("data/raw"), cue = tar_cue("always")),
  tar_target(raw_fingerprint, unname(tools::md5sum(raw_paths))),
  tar_target(using_placeholder, length(raw_paths) == 0),
  tar_target(markets, {
    raw_fingerprint
    if (using_placeholder) make_placeholder() else ingest_dot(raw_paths)
  }),
  tar_target(totals, monthly_total(markets)),
  tar_target(validation, validate_dot(markets, totals)),

  # ---- Published data files --------------------------------------------------
  tar_target(clean_csv, {
    validation
    write_csv_file(
      totals |> dplyr::transmute(month = format(date, "%Y-%m"), arrivals,
                                 classification, total_source),
      if (using_placeholder) "data/placeholder/arrivals_SYNTHETIC.csv"
      else "data/dot_arrivals_clean.csv")
  }, format = "file"),
  tar_target(markets_csv, {
    validation
    write_csv_file(
      markets |> dplyr::filter(!is_total) |>
        dplyr::select(year, month, market, dplyr::any_of("market_raw"), is_nrf,
                      arrivals, classification, file),
      if (using_placeholder) "data/placeholder/arrivals_by_market_SYNTHETIC.csv"
      else "data/dot_arrivals_by_market.csv")
  }, format = "file"),
  tar_target(unmatched, unmatched_markets(markets)),
  tar_target(unmatched_csv, write_csv_file(unmatched, "output/unmatched_markets.csv"),
             format = "file"),
  tar_target(validation_csv, write_csv_file(validation, "output/validation_report.csv"),
             format = "file"),

  # ---- Models ----------------------------------------------------------------
  tar_target(arrivals_ts, as_arrivals_ts(totals)),
  tar_target(cv_pre, cv_pre_covid(arrivals_ts)),
  tar_target(cf_fit, fit_counterfactual(arrivals_ts, cv_pre)),
  tar_target(cf_paths, counterfactual_paths(cf_fit, arrivals_ts)),
  tar_target(cf_summary, summarise_paths(cf_paths)),
  tar_target(gap, recovery_gap(cf_paths, arrivals_ts)),

  tar_target(naive_fit, fit_naive(arrivals_ts)),
  tar_target(naive_fc, forecast_model(naive_fit, arrivals_ts)),

  tar_target(inter_fit, fit_intervention(arrivals_ts)),
  tar_target(inter_fc, forecast_model(inter_fit, arrivals_ts)),
  tar_target(inter_paths, intervention_paths(inter_fit, arrivals_ts)),
  tar_target(inter_resid, residual_checks(inter_fit)),

  tar_target(recent_fit, fit_recent(arrivals_ts)),
  tar_target(recent_fc, forecast_model(recent_fit, arrivals_ts)),
  tar_target(recent_paths, model_paths(recent_fit, arrivals_ts)),
  tar_target(recent_resid, residual_checks(recent_fit)),
  tar_target(holdout, holdout_accuracy(arrivals_ts)),
  # A cross-check: if it fails, report it on the methods page instead of
  # stopping the whole build
  tar_target(causal, tryCatch(run_causalimpact(arrivals_ts), error = function(e) {
    warning("CausalImpact failed: ", conditionMessage(e)); NULL
  })),

  # ---- Recovery metrics ------------------------------------------------------
  tar_target(kpis, recovery_kpis(totals)),
  tar_target(crossing, crossing_date(recent_paths, totals)),
  tar_target(crossing_inter, crossing_date(inter_paths, totals)),
  tar_target(market_rec, market_recovery(markets)),
  tar_target(seasonal, seasonal_profile(totals)),

  # ---- Dashboard and methods report -----------------------------------------
  tar_quarto(site, path = ".", quiet = TRUE)
)
