# ==============================================================================
# Ingestion: read the yearly DOT files from data/raw/ and bind them into one
# tidy table, one row per year x month x market.
#
# Source: Department of Tourism, Philippine Tourism Data Dashboard
#   https://www.tourism.gov.ph/dot/statistics/
#   "<YEAR> Monthly Visitor Arrivals by Country of Residence"    (2010-2021)
#   "<YEAR> Monthly Visitor Arrivals by Country of Citizenship"  (2022 onward)
#
# Layout of every file (checked on the 2019, 2024 and 2026 files):
#   rows 1-3  title block, e.g. "JANUARY TO DECEMBER 2024"
#   row 4     header: RANK, SOURCE MARKET, JANUARY ... DECEMBER,
#             "JANUARY-DECEMBER <year>" (annual volume), % share, growth,
#             previous year's volume
#   row 5     sub-header (Volume / % Share / Growth Rate)
#   then      a total row, one row per market, and notes at the bottom
#
# Differences between years that this reader handles:
#   - The total row is "TOTAL" in the RANK column (2019, 2024) or
#     "GRAND TOTAL" in the SOURCE MARKET column (2026).
#   - 2026 adds a "TOTAL FOREIGN" subtotal (grand total minus non-resident
#     Filipinos). It is dropped so nothing is counted twice.
#   - From 2022, non-resident Filipinos are a separate row (RANK "#").
#     Up to 2021 they are inside each country of residence.
#   - Numbers have thousands separators; " - " means zero, except in months
#     not yet reported in a partial year, where every row is " - ".
#   - January 2022 is 0 in every row: DOT note (2) says reporting restarted
#     in February 2022. A month whose TOTAL is 0 is kept as NOT REPORTED
#     (NA), not as zero visitors.
#   - Market names change between files (e.g. "CHINA" vs "CHINA, PEOPLE'S
#     REPUBLIC OF"); see R/markets.R.
# ==============================================================================

MONTH_NAMES <- toupper(month.name)

# First year classified by country of citizenship instead of residence
CITIZENSHIP_FROM <- 2022L

list_raw_files <- function(dir = "data/raw") {
  files <- list.files(dir, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
  # The DOT archive also has "Outbound Philippine Residents" files:
  # those count Filipinos leaving, not visitors arriving
  outbound <- grepl("outbound|destination", basename(files), ignore.case = TRUE)
  if (any(outbound)) {
    warning("Ignoring outbound files: ", paste(basename(files[outbound]), collapse = ", "))
  }
  files[!outbound]
}

to_number <- function(x) {
  x <- trimws(as.character(x))
  dash <- x %in% c("-", "")
  out <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", x)))
  out[dash] <- 0
  out
}

read_dot_file <- function(path) {
  lines <- readr::read_lines(path, n_max = 10)
  header_row <- grep("SOURCE MARKET", lines, ignore.case = TRUE)[1]
  if (is.na(header_row)) stop("No 'SOURCE MARKET' header found in ", basename(path))

  # Year: from the title ("JANUARY TO DECEMBER 2024"), else from the file name
  title_year <- stringr::str_extract(paste(lines[seq_len(header_row - 1)], collapse = " "),
                                     "(19|20)[0-9]{2}")
  year <- as.integer(dplyr::coalesce(title_year,
                                     stringr::str_extract(basename(path), "20[0-9]{2}")))

  raw <- readr::read_csv(path, skip = header_row - 1, col_types = readr::cols(.default = "c"),
                         col_names = TRUE, name_repair = "minimal", show_col_types = FALSE)
  hdr <- toupper(trimws(names(raw)))
  month_cols <- match(MONTH_NAMES, hdr)
  if (anyNA(month_cols)) stop("Month columns missing in ", basename(path))
  annual_col <- grep("^JANUARY\\s*-\\s*[A-Z]+\\s+[0-9]{4}$", hdr)[1]

  rank <- trimws(raw[[1]])
  market <- stringr::str_squish(raw[[2]])
  market <- ifelse(is.na(market) | market == "",
                   ifelse(toupper(rank) == "TOTAL", "TOTAL", NA), market)
  keep <- !is.na(market) & toupper(market) != "TOTAL FOREIGN"

  # Months with " - " in the total row are not reported yet (partial year)
  total_idx <- which(toupper(market) %in% c("TOTAL", "GRAND TOTAL"))[1]
  if (is.na(total_idx)) stop("No total row found in ", basename(path))
  total_raw <- trimws(unlist(raw[total_idx, month_cols]))
  reported <- !total_raw %in% c("-", "", NA)
  not_collected <- reported & to_number(total_raw) == 0

  wide <- raw[keep, month_cols[reported], drop = FALSE]
  names(wide) <- as.character(which(reported))
  wide[, as.character(which(not_collected))] <- NA
  wide$market <- market[keep]
  wide$annual_reported <- if (is.na(annual_col)) NA_real_ else to_number(raw[[annual_col]][keep])

  wide |>
    tidyr::pivot_longer(-c(market, annual_reported), names_to = "month", values_to = "arrivals") |>
    dplyr::transmute(
      year = year,
      month = as.integer(month),
      market,
      arrivals = ifelse(is.na(arrivals), NA_real_, to_number(arrivals)),
      is_total = toupper(market) %in% c("TOTAL", "GRAND TOTAL"),
      is_nrf = grepl("NON-RESIDENT FILIPINO", market, ignore.case = TRUE),
      annual_reported,
      classification = ifelse(year >= CITIZENSHIP_FROM, "citizenship", "residence"),
      file = basename(path)
    )
}

ingest_dot <- function(files) {
  if (!length(files)) stop("No files given to ingest_dot().")
  purrr::map(files, read_dot_file) |> purrr::list_rbind() |> harmonise_markets()
}

# One row per month: the file's own total row, with the sum of the market
# rows (including non-resident Filipinos) kept alongside for validation.
monthly_total <- function(markets) {
  markets |>
    dplyr::group_by(year, month, classification) |>
    dplyr::summarise(
      not_reported = all(is.na(arrivals)),
      total_row = if (any(is_total)) sum(arrivals[is_total]) else NA_real_,
      market_sum = if (not_reported) NA_real_ else sum(arrivals[!is_total], na.rm = TRUE),
      nrf = sum(arrivals[is_nrf], na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      arrivals = dplyr::coalesce(total_row, market_sum),
      total_source = ifelse(is.na(total_row), "sum of markets", "file total row"),
      date = tsibble::yearmonth(sprintf("%d-%02d", year, month))
    ) |>
    dplyr::arrange(date)
}
