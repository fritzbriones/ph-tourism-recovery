# ==============================================================================
# SYNTHETIC placeholder data, used only while data/raw/ is empty so the whole
# pipeline and dashboard can be built and tested. These are NOT DOT figures.
# Markets are deliberately named "Market A" ... "Market H", and every chart
# and KPI shows a "placeholder data" banner while this is in use.
# ==============================================================================

make_placeholder <- function(end = "2026-08", seed = 2026) {
  set.seed(seed)
  dates <- seq(as.Date("2010-01-01"), as.Date(paste0(end, "-01")), by = "month")
  n <- length(dates)
  t <- seq_len(n) - 1
  m <- as.integer(format(dates, "%m"))

  season <- c(1.18, 1.10, 1.08, 0.98, 0.92, 0.90, 0.97, 0.96, 0.86, 0.90, 0.98, 1.17)
  counterfactual <- 300000 * exp(0.0068 * t) * season[m]

  i_close <- which(dates == as.Date("2020-03-01"))
  i_open <- which(dates == as.Date("2022-02-01"))
  share <- rep(1, n)
  share[i_close] <- 0.35
  share[(i_close + 1):(i_open - 1)] <- runif(i_open - i_close - 1, 0.001, 0.03)
  k <- seq_len(n - i_open + 1) - 1
  share[i_open:n] <- 0.45 - 0.35 * exp(-k / 8)   # levels off near 80% of 2019

  total <- round(counterfactual * share * exp(rnorm(n, 0, 0.03)))

  weights <- c(0.26, 0.18, 0.15, 0.11, 0.08, 0.07, 0.05, 0.10)
  markets <- paste("Market", LETTERS[1:8])
  grid <- expand.grid(i = seq_len(n), j = seq_along(markets))
  w <- weights[grid$j] * exp(rnorm(nrow(grid), 0, 0.05))
  # Market A recovers more slowly after reopening, to give the panel a story
  w[grid$j == 1 & grid$i >= i_open] <- w[grid$j == 1 & grid$i >= i_open] * 0.55

  by_market <- tibble::tibble(
    year = as.integer(format(dates[grid$i], "%Y")),
    month = m[grid$i],
    market = markets[grid$j],
    w = w,
    i = grid$i
  ) |>
    dplyr::group_by(i) |>
    dplyr::mutate(arrivals = round(total[i] * w / sum(w))) |>
    dplyr::ungroup()

  totals <- tibble::tibble(year = as.integer(format(dates, "%Y")), month = m,
                           market = "Grand Total", arrivals = total)

  dplyr::bind_rows(by_market |> dplyr::select(year, month, market, arrivals), totals) |>
    dplyr::mutate(
      is_total = market == "Grand Total",
      file = "SYNTHETIC placeholder",
      classification = ifelse(year >= 2022, "citizenship", "residence")
    )
}
