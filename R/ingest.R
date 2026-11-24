# ==============================================================================
# Ingestion: read the yearly DOT files (CSV or JSON) from data/raw/ and bind
# them into one tidy monthly table: one row per year x month x market.
#
# Source: Department of Tourism, Philippine Tourism Data Dashboard
#   https://www.tourism.gov.ph/dot/data/  ("Datasets used in this dashboard")
#   2010-2021 files: arrivals by COUNTRY OF RESIDENCE
#   2022-2026 files: arrivals by COUNTRY OF CITIZENSHIP
#
# The parser accepts both common layouts:
#   wide  - one row per market, one column per month (Jan ... Dec)
#   long  - one row per market and month, with a month column
# Rows named "Total" / "Grand Total" are kept but flagged, so the validation
# step can check them against the sum of the markets.
# ==============================================================================

MONTH_KEYS <- c("jan", "feb", "mar", "apr", "may", "jun",
                "jul", "aug", "sep", "oct", "nov", "dec")

# First year classified by country of citizenship instead of residence
CITIZENSHIP_FROM <- 2022L

list_raw_files <- function(dir = "data/raw") {
  files <- list.files(dir, pattern = "\\.(csv|json)$", full.names = TRUE,
                      ignore.case = TRUE)
  # The same DOT archive also has "Outbound Philippine Residents" files:
  # those count Filipinos leaving, not visitors arriving, so never mix them in
  outbound <- grepl("outbound|destination", basename(files), ignore.case = TRUE)
  if (any(outbound)) {
    warning("Ignoring outbound files: ", paste(basename(files[outbound]), collapse = ", "))
    files <- files[!outbound]
  }
  # If a year has both a CSV and a JSON copy, keep the CSV only
  key <- sub("\\.(csv|json)$", "", basename(files), ignore.case = TRUE)
  files[!(duplicated(key) & grepl("json$", files, ignore.case = TRUE))]
}

to_number <- function(x) {
  x <- gsub("[^0-9.-]", "", as.character(x))
  suppressWarnings(as.numeric(ifelse(x %in% c("", "-", "."), NA, x)))
}

month_index <- function(x) {
  key <- substr(tolower(trimws(x)), 1, 3)
  out <- match(key, MONTH_KEYS)
  num <- suppressWarnings(as.integer(x))
  ifelse(is.na(out), num, out)
}

clean_names <- function(df) {
  names(df) <- tolower(gsub("[^A-Za-z0-9]+", "_", trimws(names(df))))
  names(df) <- gsub("^_|_$", "", names(df))
  df
}

read_raw <- function(path) {
  if (grepl("json$", path, ignore.case = TRUE)) {
    x <- jsonlite::fromJSON(path, flatten = TRUE)
    # Some APIs wrap the rows, e.g. {"data": [...]}
    if (is.list(x) && !is.data.frame(x)) x <- x[[which(vapply(x, is.data.frame, TRUE))[1]]]
    df <- tibble::as_tibble(lapply(x, as.character))
  } else {
    df <- readr::read_csv(path, col_types = readr::cols(.default = "c"),
                          show_col_types = FALSE, name_repair = "unique")
  }
  clean_names(df)
}

read_dot_file <- function(path) {
  df <- read_raw(path)
  file_year <- as.integer(stringr::str_extract(basename(path), "20[0-9]{2}"))

  month_cols <- names(df)[substr(names(df), 1, 3) %in% MONTH_KEYS &
                            nchar(names(df)) <= 9]
  is_wide <- length(month_cols) >= 1 && !"month" %in% names(df)

  label_col <- names(df)[grepl("country|market|residence|citizenship|nationality|region",
                               names(df))][1]
  if (is.na(label_col)) label_col <- setdiff(names(df), c(month_cols, "year"))[1]

  if (is_wide) {
    long <- df |>
      dplyr::select(market = dplyr::all_of(label_col),
                    dplyr::any_of("year"), dplyr::all_of(month_cols)) |>
      tidyr::pivot_longer(dplyr::all_of(month_cols),
                          names_to = "month", values_to = "arrivals")
  } else {
    value_col <- names(df)[grepl("arrival|visitor|count|value|total", names(df)) &
                             names(df) != label_col][1]
    if (is.na(value_col) || !"month" %in% names(df)) {
      stop("Unrecognised layout in ", basename(path),
           ". Columns: ", paste(names(df), collapse = ", "))
    }
    long <- df |>
      dplyr::select(market = dplyr::all_of(label_col), dplyr::any_of("year"),
                    month, arrivals = dplyr::all_of(value_col))
  }

  if (!"year" %in% names(long)) long$year <- file_year

  long |>
    dplyr::transmute(
      year = as.integer(to_number(year)),
      month = month_index(month),
      market = stringr::str_squish(market),
      arrivals = to_number(arrivals),
      is_total = grepl("^(grand\\s*)?total", market, ignore.case = TRUE),
      file = basename(path)
    ) |>
    dplyr::filter(!is.na(month), !is.na(market), market != "") |>
    dplyr::mutate(classification = ifelse(year >= CITIZENSHIP_FROM,
                                          "citizenship", "residence"))
}

ingest_dot <- function(files) {
  if (!length(files)) stop("No files given to ingest_dot().")
  purrr::map(files, read_dot_file) |> purrr::list_rbind()
}

# One row per month: the file's own Total row when present, else the sum of
# its markets. `total_source` records which was used.
monthly_total <- function(markets) {
  markets |>
    dplyr::group_by(year, month, classification) |>
    dplyr::summarise(
      total_row = if (any(is_total)) sum(arrivals[is_total], na.rm = TRUE) else NA_real_,
      market_sum = sum(arrivals[!is_total], na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      arrivals = dplyr::coalesce(total_row, market_sum),
      total_source = ifelse(is.na(total_row), "sum of markets", "file total row"),
      date = tsibble::yearmonth(sprintf("%d-%02d", year, month))
    ) |>
    dplyr::filter(!is.na(arrivals)) |>
    dplyr::arrange(date) |>
    # A partial year can list future months as 0: drop zeros at the very end
    dplyr::filter(dplyr::row_number() <= max(which(arrivals > 0)))
}
