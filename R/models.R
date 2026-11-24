# ==============================================================================
# Models
#   1. Counterfactual: trained on Jan 2010 - Feb 2020 only, projected forward.
#      "What arrivals would have looked like without COVID-19."
#   2. Naive forecast: Prophet on the full series with no knowledge of COVID.
#      Shown on purpose, to demonstrate how the 2020-21 crash distorts it.
#   3. Intervention ARIMA (ARIMAX): log arrivals with regressors for the
#      border closure and a decaying post-reopening gap. Used to MEASURE the
#      shock (interrupted time series).
#   3b. Post-reopening ARIMA: fitted on Jan 2023 onward only (the new normal
#      after the recovery ramp). Used for the headline FORECAST because it
#      wins the 12-month hold-out test by a wide margin.
#   4. CausalImpact (Bayesian structural time series) as a cross-check of the
#      counterfactual.
# All models work on log(arrivals): seasonality is multiplicative and
# forecasts stay positive.
# ==============================================================================

CLOSE_START <- tsibble::yearmonth("2020 Mar")  # lockdown and border closure
REOPEN      <- tsibble::yearmonth("2022 Feb")  # reopened to tourists 10 Feb 2022
HORIZON_END <- tsibble::yearmonth("2030 Dec")
RECENT_START <- tsibble::yearmonth("2023 Jan") # first full year after reopening
TAU_GRID    <- c(3, 6, 9, 12, 18, 24, 36)       # months; speed of gap decay
N_SIMS      <- 1000

as_arrivals_ts <- function(totals) {
  totals |>
    dplyr::select(date, arrivals) |>
    tsibble::as_tsibble(index = date)
}

# ARIMA cannot fit through a missing month here (Jan 2022, not collected by
# DOT). For the intervention model only, a missing month is filled by
# log-linear interpolation between its neighbours. Published data keeps NA.
fill_gaps_log <- function(ts) {
  y <- log(ts$arrivals)
  miss <- is.na(y)
  if (any(miss)) {
    y[miss] <- stats::approx(which(!miss), y[!miss], xout = which(miss))$y
    ts$arrivals <- exp(y)
  }
  attr(ts, "filled") <- format(ts$date[miss])
  ts
}

# Intervention regressors. Values for future months are known in advance,
# so the model can forecast without guessing future regressors.
add_interventions <- function(ts, tau) {
  months_since <- as.numeric(ts$date - REOPEN)
  ts |>
    dplyr::mutate(
      closed = as.numeric(date > CLOSE_START & date < REOPEN),
      mar2020 = as.numeric(date == CLOSE_START),   # partial month
      post = as.numeric(date >= REOPEN),
      gap_decay = ifelse(date >= REOPEN, exp(-months_since / tau), 0)
    )
}

future_months <- function(ts, until = HORIZON_END) {
  last <- max(ts$date)
  n <- as.numeric(until - last)
  tsibble::new_data(ts, n)
}

# ---- 1. Counterfactual -------------------------------------------------------

pre_covid <- function(ts) dplyr::filter(ts, date < CLOSE_START)

cv_pre_covid <- function(ts) {
  pre <- pre_covid(ts)
  # Last fold must leave 12 months of pre-COVID data to score against
  pre |>
    dplyr::filter(date <= max(date) - 12) |>
    tsibble::stretch_tsibble(.init = 60, .step = 12) |>
    fabletools::model(
      SNAIVE = fable::SNAIVE(log(arrivals)),
      ETS = fable::ETS(log(arrivals)),
      ARIMA = fable::ARIMA(log(arrivals))
    ) |>
    fabletools::forecast(h = 12) |>
    fabletools::accuracy(pre) |>
    dplyr::select(model = .model, RMSE, MAE, MAPE, MASE) |>
    dplyr::arrange(MASE)
}

fit_counterfactual <- function(ts, cv) {
  best <- cv$model[cv$model != "SNAIVE"][1]
  spec <- switch(best,
                 ETS = fable::ETS(log(arrivals)),
                 ARIMA = fable::ARIMA(log(arrivals)))
  fit <- pre_covid(ts) |> fabletools::model(counterfactual = spec)
  attr(fit, "chosen") <- best
  fit
}

counterfactual_paths <- function(fit, ts) {
  future <- tsibble::new_data(pre_covid(ts), as.numeric(HORIZON_END - CLOSE_START) + 1)
  fabletools::generate(fit, new_data = future, times = N_SIMS, bootstrap = FALSE) |>
    tibble::as_tibble() |>
    dplyr::select(date, rep = .rep, sim = .sim)
}

summarise_paths <- function(paths) {
  paths |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      median = stats::median(sim),
      lo80 = stats::quantile(sim, 0.10), hi80 = stats::quantile(sim, 0.90),
      lo95 = stats::quantile(sim, 0.025), hi95 = stats::quantile(sim, 0.975),
      .groups = "drop"
    )
}

# Cumulative visitors "lost" from Mar 2020 to the latest month
recovery_gap <- function(cf_paths, ts) {
  actual <- tibble::as_tibble(ts) |> dplyr::filter(date >= CLOSE_START)
  per_rep <- cf_paths |>
    dplyr::inner_join(actual, by = "date") |>
    dplyr::group_by(rep) |>
    dplyr::summarise(deficit = sum(sim - arrivals, na.rm = TRUE), .groups = "drop")
  tibble::tibble(
    from = format(CLOSE_START), to = format(max(ts$date)),
    deficit_median = stats::median(per_rep$deficit),
    deficit_lo95 = stats::quantile(per_rep$deficit, 0.025),
    deficit_hi95 = stats::quantile(per_rep$deficit, 0.975)
  )
}

# ---- 2. Naive Prophet --------------------------------------------------------

fit_naive <- function(ts) {
  if (requireNamespace("fable.prophet", quietly = TRUE)) {
    ts |> fabletools::model(
      `Naive Prophet` = fable.prophet::prophet(log(arrivals) ~ season("year", type = "additive"))
    )
  } else {
    warning("fable.prophet not installed: using a naive ETS model instead.")
    ts |> fabletools::model(`Naive ETS` = fable::ETS(log(arrivals)))
  }
}

# ---- 3. Intervention ARIMA ---------------------------------------------------

fit_intervention <- function(ts) {
  ts <- fill_gaps_log(ts)
  fits <- purrr::map(TAU_GRID, function(tau) {
    add_interventions(ts, tau) |>
      fabletools::model(
        `Intervention ARIMA` = fable::ARIMA(log(arrivals) ~ closed + mar2020 + post + gap_decay)
      )
  })
  aicc <- purrr::map_dbl(fits, function(f) {
    g <- fabletools::glance(f)
    if ("AICc" %in% names(g)) g$AICc else Inf
  })
  if (all(!is.finite(aicc))) stop("Intervention ARIMA could not be fitted for any tau.")
  best <- which.min(aicc)
  fit <- fits[[best]]
  attr(fit, "tau") <- TAU_GRID[best]
  attr(fit, "tau_table") <- tibble::tibble(tau_months = TAU_GRID, AICc = aicc)
  attr(fit, "filled") <- attr(ts, "filled")
  fit
}

forecast_model <- function(fit, ts) {
  future <- future_months(ts)
  tau <- attr(fit, "tau")
  if (!is.null(tau)) future <- add_interventions(future, tau)
  fc <- fabletools::forecast(fit, new_data = future)
  fc |>
    dplyr::mutate(
      i80 = fabletools::hilo(arrivals, 80), i95 = fabletools::hilo(arrivals, 95)
    ) |>
    fabletools::unpack_hilo(c(i80, i95)) |>
    tibble::as_tibble() |>
    dplyr::transmute(model = .model, date, median = stats::median(arrivals),
                     mean = .mean, lo80 = i80_lower, hi80 = i80_upper,
                     lo95 = i95_lower, hi95 = i95_upper)
}

# ---- 3b. Post-reopening ARIMA ------------------------------------------------

recent_spec <- function() fable::ARIMA(log(arrivals))

fit_recent <- function(ts) {
  ts |> dplyr::filter(date >= RECENT_START) |>
    fabletools::model(`Post-reopening ARIMA` = recent_spec())
}

model_paths <- function(fit, ts) {
  fabletools::generate(fit, new_data = future_months(ts), times = N_SIMS, bootstrap = FALSE) |>
    tibble::as_tibble() |>
    dplyr::select(date, rep = .rep, sim = .sim)
}

intervention_paths <- function(fit, ts) {
  future <- add_interventions(future_months(ts), attr(fit, "tau"))
  fabletools::generate(fit, new_data = future, times = N_SIMS, bootstrap = FALSE) |>
    tibble::as_tibble() |>
    dplyr::select(date, rep = .rep, sim = .sim)
}

# ---- Hold-out test: last 12 months -------------------------------------------

holdout_accuracy <- function(ts, h = 12) {
  cutoff <- max(ts$date) - h
  train <- dplyr::filter(ts, date <= cutoff)
  test_dates <- dplyr::filter(ts, date > cutoff)

  naive <- fit_naive(train)
  fc_naive <- fabletools::forecast(naive, new_data = test_dates |> dplyr::select(date))

  inter <- fit_intervention(train)
  new <- add_interventions(test_dates, attr(inter, "tau")) |> dplyr::select(-arrivals)
  fc_inter <- fabletools::forecast(inter, new_data = new)

  recent <- train |> dplyr::filter(date >= RECENT_START) |>
    fabletools::model(`Post-reopening ARIMA` = recent_spec(),
                      `Seasonal naive (benchmark)` = fable::SNAIVE(arrivals))
  fc_recent <- fabletools::forecast(recent, h = h)

  dplyr::bind_rows(
    fabletools::accuracy(fc_naive, ts),
    fabletools::accuracy(fc_inter, add_interventions(fill_gaps_log(ts), attr(inter, "tau"))),
    fabletools::accuracy(fc_recent, ts)
  ) |>
    dplyr::select(model = .model, RMSE, MAE, MAPE, MASE) |>
    dplyr::mutate(test_window = paste(format(cutoff + 1), "to", format(max(ts$date))))
}

residual_checks <- function(fit) {
  aug <- fabletools::augment(fit)
  n_coef <- nrow(fabletools::tidy(fit))
  lag <- min(24, floor(nrow(aug) / 3))
  lb <- aug |> fabletools::features(.innov, feasts::ljung_box, lag = lag, dof = n_coef) |>
    dplyr::mutate(lag = lag)
  list(augment = tibble::as_tibble(aug), ljung_box = lb,
       report = utils::capture.output(fabletools::report(fit)))
}

# ---- 4. CausalImpact cross-check ---------------------------------------------

run_causalimpact <- function(ts) {
  if (!requireNamespace("CausalImpact", quietly = TRUE)) return(NULL)
  y <- zoo::zoo(log(ts$arrivals), as.Date(ts$date))
  pre <- as.Date(c(min(ts$date), CLOSE_START - 1))
  post <- as.Date(c(CLOSE_START, max(ts$date)))
  set.seed(2026)
  ci <- CausalImpact::CausalImpact(y, pre, post,
                                   model.args = list(nseasons = 12, niter = 2000))
  s <- as.data.frame(ci$series)
  tibble::tibble(
    date = tsibble::yearmonth(as.Date(rownames(s))),
    actual = exp(s$response),
    counterfactual = exp(s$point.pred),
    lo95 = exp(s$point.pred.lower), hi95 = exp(s$point.pred.upper)
  )
}
