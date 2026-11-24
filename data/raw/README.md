# Raw DOT files

Put the Department of Tourism yearly files here, unchanged, as downloaded from
the **Datasets used in this dashboard** section of
<https://www.tourism.gov.ph/dot/data/>.

- One file per year, 2010 to the latest year. CSV preferred; JSON also works.
- Keep the year in the file name (for example `2019_monthly_visitor_arrivals.csv`);
  the pipeline reads the year from it when the file has no year column.
- Don't edit the numbers by hand. Any fixes belong in `R/ingest.R`, so they're
  documented and repeatable.

While this folder has no CSV or JSON files, the pipeline uses a clearly
labelled SYNTHETIC series so the dashboard can still be built and tested.

License: CC BY 4.0, Department of Tourism, Republic of the Philippines.
