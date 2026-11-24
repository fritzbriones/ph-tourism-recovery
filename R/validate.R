# ==============================================================================
# Validation: the pipeline stops on hard failures and writes a report of every
# check to output/validation_report.csv.
# ==============================================================================

validate_dot <- function(markets, totals, tolerance = 0.005) {
  dup <- markets |> dplyr::count(year, month, market) |> dplyr::filter(n > 1)
  neg <- markets |> dplyr::filter(arrivals < 0)

  # Every month between the first and the last must be present
  expected <- seq(min(totals$date), max(totals$date), by = 1)
  missing <- setdiff(as.character(expected), as.character(totals$date))

  # File total row vs sum of markets (only where the file has a total row)
  gap <- totals |>
    dplyr::filter(total_source == "file total row", market_sum > 0) |>
    dplyr::mutate(rel_diff = abs(total_row - market_sum) / total_row) |>
    dplyr::filter(rel_diff > tolerance)

  # The headline KPIs compare Jan..latest month of the latest year with 2019:
  # a gap inside the latest year would silently undercount them
  latest_year <- max(totals$year)
  gaps_latest <- totals |> dplyr::filter(year == latest_year, is.na(arrivals))

  # Each file's monthly totals must add up to the annual total it reports
  annual <- markets |>
    dplyr::filter(is_total, !is.na(annual_reported)) |>
    dplyr::group_by(year) |>
    dplyr::summarise(sum_months = sum(arrivals, na.rm = TRUE), reported = dplyr::first(annual_reported),
                     .groups = "drop") |>
    dplyr::filter(sum_months != reported)

  report <- tibble::tribble(
    ~check, ~result, ~pass,
    "first month", format(min(totals$date)), TRUE,
    "last month", format(max(totals$date)), TRUE,
    "months in series", as.character(nrow(totals)), TRUE,
    "missing months", if (length(missing)) paste(missing, collapse = "; ") else "none", length(missing) == 0,
    "months DOT did not collect (kept as NA)",
      if (any(totals$not_reported)) paste(format(totals$date[totals$not_reported]), collapse = "; ") else "none", TRUE,
    "missing months inside the latest year (would distort year-to-date KPIs)",
      if (nrow(gaps_latest)) paste(format(gaps_latest$date), collapse = "; ") else "none",
      nrow(gaps_latest) == 0,
    "duplicate year-month-market rows", as.character(nrow(dup)), nrow(dup) == 0,
    "negative values", as.character(nrow(neg)), nrow(neg) == 0,
    "months where total row differs from sum of markets by > 0.5%",
      if (nrow(gap)) paste(format(gap$date), collapse = "; ") else "none", TRUE,
    "years where monthly totals don't add up to the file's annual total",
      if (nrow(annual)) paste(annual$year, collapse = "; ") else "none", nrow(annual) == 0,
    "classification switch (residence -> citizenship)",
      paste0(CITIZENSHIP_FROM, "-01"), TRUE
  )

  fails <- report |> dplyr::filter(!pass)
  if (nrow(fails)) {
    stop("Data validation failed:\n",
         paste0("  - ", fails$check, ": ", fails$result, collapse = "\n"))
  }
  report
}

write_csv_file <- function(x, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(x, path)
  path
}
