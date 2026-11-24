# ==============================================================================
# Optional helper: find and download the DOT yearly arrivals files.
#
#   Rscript R/download.R          # run from the repository root
#
# It looks for .csv / .json links on the DOT data page and on the "Statistics"
# archive pages (and the post pages they link to), keeps the inbound
# "Monthly Visitor Arrivals" files, skips the outbound files, and saves new or
# changed files to data/raw/. The targets pipeline then reads data/raw/.
#
# Files are saved into the repository (not read live) on purpose: the
# analysis stays reproducible if DOT moves or redesigns its pages.
# ==============================================================================

DOT_PAGES <- c(
  "https://www.tourism.gov.ph/dot/data/",
  "https://www.tourism.gov.ph/dot/statistics/",
  "https://www.tourism.gov.ph/dot/statistics/page/2/",
  "https://www.tourism.gov.ph/dot/statistics/page/3/"
)

page_links <- function(url) {
  html <- tryCatch(rvest::read_html(url), error = function(e) {
    warning("Could not read ", url, ": ", conditionMessage(e)); NULL
  })
  if (is.null(html)) return(tibble::tibble(text = character(), href = character()))
  a <- rvest::html_elements(html, "a")
  tibble::tibble(text = rvest::html_text2(a),
                 href = xml2::url_absolute(rvest::html_attr(a, "href"), url)) |>
    dplyr::filter(!is.na(href))
}

is_arrivals <- function(x) {
  grepl("visitor.?arrivals", x, ignore.case = TRUE) &
    !grepl("outbound|destination", x, ignore.case = TRUE)
}

discover_dot_files <- function(pages = DOT_PAGES) {
  links <- purrr::map(pages, page_links) |> purrr::list_rbind()
  # Archive entries link to a post page that holds the download buttons
  posts <- links |>
    dplyr::filter(is_arrivals(paste(text, href)),
                  !grepl("\\.(csv|json)(\\?|$)", href, ignore.case = TRUE)) |>
    dplyr::distinct(href) |> dplyr::pull(href)
  all_links <- dplyr::bind_rows(links, purrr::map(posts, page_links) |> purrr::list_rbind())
  all_links |>
    dplyr::filter(grepl("\\.(csv|json)(\\?|$)", href, ignore.case = TRUE),
                  is_arrivals(paste(text, href))) |>
    dplyr::distinct(href, .keep_all = TRUE) |>
    dplyr::mutate(year = stringr::str_extract(paste(href, text), "20[0-9]{2}"),
                  ext = tolower(stringr::str_extract(href, "(csv|json)(?=(\\?|$))"))) |>
    dplyr::filter(!is.na(year)) |>
    # One file per year: prefer CSV
    dplyr::arrange(year, ext != "csv") |>
    dplyr::distinct(year, .keep_all = TRUE)
}

download_dot_files <- function(dest = "data/raw") {
  files <- discover_dot_files()
  if (!nrow(files)) stop("No arrivals files found. The DOT pages may have changed.")
  dir.create(dest, showWarnings = FALSE, recursive = TRUE)
  out <- file.path(dest, paste0(files$year, "_monthly_visitor_arrivals.", files$ext))
  purrr::walk2(files$href, out, function(u, f) {
    tmp <- tempfile()
    utils::download.file(u, tmp, mode = "wb", quiet = TRUE)
    if (!file.exists(f) || unname(tools::md5sum(tmp)) != unname(tools::md5sum(f))) {
      file.copy(tmp, f, overwrite = TRUE)
      message("Saved ", f)
    }
  })
  invisible(out)
}

if (sys.nframe() == 0) download_dot_files()
