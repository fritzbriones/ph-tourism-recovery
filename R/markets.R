# ==============================================================================
# Market names differ between the residence files (to 2021) and the
# citizenship files (2022 onward). This crosswalk maps every spelling seen so
# far to one name. Add rows here when a new spelling appears; the pipeline
# lists unmatched large markets in output/unmatched_markets.csv.
# ==============================================================================

MARKET_CROSSWALK <- c(
  "AMERICA, UNITED STATES OF" = "UNITED STATES",
  "UNITED STATES OF AMERICA" = "UNITED STATES",
  "CHINA, PEOPLE'S REPUBLIC OF" = "CHINA",
  "UNITED KINGDOM OF GREAT BRITAIN AND OTHER TERRITORIES" = "UNITED KINGDOM",
  "HONGKONG" = "HONG KONG",
  "RUSSIAN FEDERATION" = "RUSSIA",
  "MYANMAR (BURMA)" = "MYANMAR",
  "MACAU - SAR" = "MACAU",
  "IRAN (ISLAM REPUBLIC OF)" = "IRAN",
  "SLOVAKIA (SLOVAK REPUBLIC)" = "SLOVAKIA",
  "CROATIA (LOCAL NAME: HRVATSKA)" = "CROATIA",
  "LAO PEOPLE'S DEMOCRATIC REPUBLIC" = "LAOS",
  "MICRONESIA, FEDERATED STATES OF" = "MICRONESIA",
  "MICRONESIA, FEDERATED STATES" = "MICRONESIA",
  "COLUMBIA" = "COLOMBIA",
  "SYRIAN ARAB REP." = "SYRIA",
  "SYRIAN ARAB REPUBLIC" = "SYRIA",
  "TANZANIA, UNITED REPUBLIC OF" = "TANZANIA",
  "SERBIA, REPUBLIC OF" = "SERBIA",
  "MARSHALL IS." = "MARSHALL ISLANDS",
  "KYRGYSZSTAN" = "KYRGYZSTAN",
  "ST. KITTS AND NEVIS" = "SAINT KITTS AND NEVIS",
  "ST. LUCIA" = "SAINT LUCIA",
  "ST. VINCENT AND THE GRENADINES" = "SAINT VINCENT AND THE GRENADINES",
  "MOLDOVA, REPUBLIC OF" = "MOLDOVA",
  "MACEDONIA, THE FORMER YUGOSLAV REPUBLIC OF" = "MACEDONIA",
  "BOSNIA AND HERZEGOWINIAN" = "BOSNIA AND HERZEGOVINA",
  "BOSNIA/HERZEGOVINA" = "BOSNIA AND HERZEGOVINA",
  "LIBYA ARAB JAMAHIRIYA" = "LIBYA",
  "LIBYAN ARAB JAMAHIRI" = "LIBYA",
  "SEYCHELLES ISLANDS" = "SEYCHELLES",
  "CAPE VERDE ISLANDS" = "CAPE VERDE",
  "NAMBIA" = "NAMIBIA",
  "PALESTINIAN TERRITORY, OCCUPIED" = "PALESTINE",
  "KOREA(NORTH), DEMOCRATIC PEOPLES REPUBLIC OF" = "NORTH KOREA",
  "BENIN, REPUBLIC OF" = "BENIN",
  "SURINAME, REPUBLIC OF" = "SURINAME",
  "TURKEMENISTAN" = "TURKMENISTAN",
  "CENTRAL AFRICAN REP" = "CENTRAL AFRICAN REPUBLIC"
)

harmonise_markets <- function(markets) {
  up <- toupper(stringr::str_squish(markets$market))
  markets$market_raw <- markets$market
  markets$market <- ifelse(up %in% names(MARKET_CROSSWALK), MARKET_CROSSWALK[up], up)
  markets
}

# Markets with at least `min_volume` arrivals in one year that never appear
# in a year on the other side of the residence/citizenship break: usually a
# spelling the crosswalk is missing.
unmatched_markets <- function(markets, min_volume = 1000) {
  m <- markets |>
    dplyr::filter(!is_total, !is_nrf) |>
    dplyr::group_by(market, classification) |>
    dplyr::summarise(max_year_volume = max(tapply(arrivals, year, sum)), .groups = "drop")
  sides <- m |> dplyr::count(market)
  m |>
    dplyr::semi_join(dplyr::filter(sides, n == 1), by = "market") |>
    dplyr::filter(max_year_volume >= min_volume) |>
    dplyr::arrange(dplyr::desc(max_year_volume))
}
