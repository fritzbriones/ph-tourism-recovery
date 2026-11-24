# ==============================================================================
# Recovery metrics shown on the dashboard
# ==============================================================================

BASE_YEAR <- 2019L

# Headline numbers: year-to-date vs the same months of 2019, and the latest
# rolling 12-month total vs the full 2019 total.
recovery_kpis <- function(totals) {
  latest <- max(totals$date)
  ly <- lubridate::year(latest); lm <- lubridate::month(latest)
  ytd <- sum(totals$arrivals[totals$year == ly & totals$month <= lm])
  ytd_2019 <- sum(totals$arrivals[totals$year == BASE_YEAR & totals$month <= lm])
  total_2019 <- sum(totals$arrivals[totals$year == BASE_YEAR])
  roll12 <- sum(utils::tail(totals$arrivals, 12))
  tibble::tibble(
    latest_month = format(latest),
    ytd = ytd, ytd_2019 = ytd_2019, ytd_pct_2019 = ytd / ytd_2019,
    rolling12 = roll12, total_2019 = total_2019, rolling12_pct_2019 = roll12 / total_2019
  )
}

# When does the rolling 12-month total pass the 2019 total?
# Uses simulated future paths, so the answer comes with uncertainty.
# (Cumulative arrivals since 2020 can never catch up; a rolling annual total can.)
crossing_date <- function(paths, totals) {
  total_2019 <- sum(totals$arrivals[totals$year == BASE_YEAR])
  hist <- utils::tail(totals$arrivals, 11)
  per_rep <- paths |>
    dplyr::arrange(rep, date) |>
    dplyr::group_by(rep) |>
    dplyr::summarise(
      cross = {
        roll <- stats::filter(c(hist, sim), rep(1, 12), sides = 1)[-(1:11)]
        hit <- which(roll >= total_2019)
        if (length(hit)) as.numeric(date[hit[1]]) else NA_real_
      },
      .groups = "drop"
    )
  already <- sum(utils::tail(totals$arrivals, 12)) >= total_2019
  p_by_end <- mean(!is.na(per_rep$cross))
  q <- stats::quantile(per_rep$cross, c(0.1, 0.5, 0.9), na.rm = TRUE, type = 1)
  fmt <- function(x) if (is.na(x)) NA_character_ else format(tsibble::yearmonth(x))
  tibble::tibble(
    target_2019_total = total_2019,
    already_passed = already,
    prob_by_horizon = p_by_end,
    horizon = format(HORIZON_END),
    median_month = if (p_by_end >= 0.5) fmt(q[[2]]) else NA_character_,
    p10_month = fmt(q[[1]]),
    p90_month = if (p_by_end >= 0.9) fmt(q[[3]]) else NA_character_
  )
}

# Source markets: latest year-to-date vs the same months of 2019.
# Caveat: 2019 counts are by country of RESIDENCE, 2022+ by CITIZENSHIP.
market_recovery <- function(markets, top_n = 10) {
  m <- dplyr::filter(markets, !is_total)
  ly <- max(m$year)
  lm <- max(m$month[m$year == ly & m$arrivals > 0])
  ytd <- m |>
    dplyr::filter(month <= lm, year %in% c(BASE_YEAR, ly)) |>
    dplyr::group_by(market, year) |>
    dplyr::summarise(arrivals = sum(arrivals, na.rm = TRUE), .groups = "drop") |>
    tidyr::pivot_wider(names_from = year, values_from = arrivals, names_prefix = "y")
  names(ytd) <- c("market", "base", "latest")[match(names(ytd),
                   c("market", paste0("y", BASE_YEAR), paste0("y", ly)))]
  ytd |>
    dplyr::filter(!is.na(base), base > 0) |>
    dplyr::slice_max(base, n = top_n) |>
    dplyr::mutate(latest = dplyr::coalesce(latest, 0),
                  recovery = latest / base,
                  period = paste0("Jan-", month.abb[lm], " ", ly, " vs ", BASE_YEAR)) |>
    dplyr::arrange(dplyr::desc(recovery))
}

# Seasonal profile: each month as a share of its year's average month.
# Compares the pre-COVID pattern (2017-2019) with every complete year since 2023.
seasonal_profile <- function(totals) {
  full_years <- totals |> dplyr::count(year) |> dplyr::filter(n == 12) |> dplyr::pull(year)
  idx <- totals |>
    dplyr::filter(year %in% full_years) |>
    dplyr::group_by(year) |>
    dplyr::mutate(index = arrivals / mean(arrivals)) |>
    dplyr::ungroup()
  dplyr::bind_rows(
    idx |> dplyr::filter(year %in% 2017:2019) |>
      dplyr::group_by(month) |> dplyr::summarise(index = mean(index), .groups = "drop") |>
      dplyr::mutate(period = "2017-2019 average"),
    idx |> dplyr::filter(year >= 2023) |>
      dplyr::transmute(month, index, period = as.character(year))
  )
}
