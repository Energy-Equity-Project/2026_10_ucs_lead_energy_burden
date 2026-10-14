# Compare the shipped UCS files with values read off the DOE LEAD interactive tool.
# Reads only the latest shipped CSVs in OUTPUT_DIR and the tool values below; it does
# not recompute anything and writes no files.
#
# Phase 1: FPL, state level and state x FPL band (Michigan and Alabama).
# Phase 2: county level, overall values only (Wayne County, MI 26163; Perry County, AL 01105).
# Phase 3: tract level, overall values only (Perry tract 6871 01105687100; Wayne tract 5452
# 26163545200). The tool's tract name drops the code's last two digits (6871 = 687100).
# The LEAD tool does not update its FPL band stats when a county or tract is selected, so
# county and tract FPL band values are not checked against it.
# Later phases add rows to `tool_values` and the matching file patterns to `shipped_files`.
#
# Run from the repo root: Rscript R/03_check_lead_tool.R

library(tidyverse)

# Retrieve the output folder from .Renviron
output_dir <- Sys.getenv("OUTPUT_DIR")

if (output_dir == "") {
  stop("Missing in .Renviron: OUTPUT_DIR. Copy .Renviron.example to .Renviron, fill it in and restart R.")
}

# Values as the LEAD tool displays them (whole numbers). band = NA is the overall row.
tool_values <- tribble(
  ~level,  ~family, ~geoid, ~band,      ~metric,              ~tool_value, ~tool_digits,
  "state", "fpl",   "26",   NA,         "energy_burden",      3,           0,
  "state", "fpl",   "26",   NA,         "total_utility_cost", 2687,        0,
  "state", "fpl",   "26",   NA,         "total_households",   4009261,     0,
  "state", "fpl",   "26",   NA,         "weighted_income",    94973,       0,
  "state", "fpl",   "26",   "0-100%",   "energy_burden",      23,          0,
  "state", "fpl",   "26",   "100-150%", "energy_burden",      9,           0,
  "state", "fpl",   "26",   "150-200%", "energy_burden",      8,           0,
  "state", "fpl",   "26",   "200-400%", "energy_burden",      4,           0,
  "state", "fpl",   "26",   "400%+",    "energy_burden",      2,           0,
  "state", "fpl",   "01",   NA,         "energy_burden",      3,           0,
  "state", "fpl",   "01",   NA,         "total_utility_cost", 2419,        0,
  "state", "fpl",   "01",   NA,         "total_households",   1933150,     0,
  "state", "fpl",   "01",   NA,         "weighted_income",    84282,       0,
  "state", "fpl",   "01",   "0-100%",   "energy_burden",      20,          0,
  "state", "fpl",   "01",   "100-150%", "energy_burden",      8,           0,
  "state", "fpl",   "01",   "150-200%", "energy_burden",      6,           0,
  "state", "fpl",   "01",   "200-400%", "energy_burden",      4,           0,
  "state", "fpl",   "01",   "400%+",    "energy_burden",      1,           0,
  "county", "fpl",  "26163", NA,        "energy_burden",      3,           0,
  "county", "fpl",  "26163", NA,        "total_utility_cost", 2835,        0,
  "county", "fpl",  "26163", NA,        "total_households",   688461,      0,
  "county", "fpl",  "26163", NA,        "weighted_income",    82303,       0,
  "county", "fpl",  "01105", NA,        "energy_burden",      6,           0,
  "county", "fpl",  "01105", NA,        "total_utility_cost", 2521,        0,
  "county", "fpl",  "01105", NA,        "total_households",   3075,        0,
  "county", "fpl",  "01105", NA,        "weighted_income",    43119,       0,
  "tract", "fpl",   "01105687100", NA,  "energy_burden",      7,           0,
  "tract", "fpl",   "01105687100", NA,  "total_utility_cost", 2671,        0,
  "tract", "fpl",   "01105687100", NA,  "total_households",   1154,        0,
  "tract", "fpl",   "01105687100", NA,  "weighted_income",    36089,       0,
  "tract", "fpl",   "26163545200", NA,  "energy_burden",      13,          0,
  "tract", "fpl",   "26163545200", NA,  "total_utility_cost", 3533,        0,
  "tract", "fpl",   "26163545200", NA,  "total_households",   869,         0,
  "tract", "fpl",   "26163545200", NA,  "weighted_income",    27926,       0
)

# Shipped files to check: the file-name suffix after the date, the geography key
# column and the band column (NA for overall files)
shipped_files <- tribble(
  ~level,  ~family, ~suffix,                                ~geoid_col,   ~band_col,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden",     "state_fips", NA,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden-fpl", "state_fips", "fpl",
  "county", "fpl",  "ucs-lead-2022-county-energy-burden",    "county_geoid", NA,
  "tract", "fpl",   "ucs-lead-2022-tract-energy-burden",     "tract_geoid", NA
)

metrics <- c("energy_burden", "total_utility_cost", "total_households", "weighted_income")

# Latest dated file for a suffix. Names start with dd-mm-yyyy, so sort on the parsed
# date rather than the text.
latest_file <- function(suffix) {
  files <- list.files(output_dir, pattern = paste0("^\\d{2}-\\d{2}-\\d{4}-", suffix, "\\.csv$"))
  if (length(files) == 0) stop("No shipped file in ", output_dir, " for ", suffix)
  dates <- as.Date(str_sub(files, 1, 10), format = "%d-%m-%Y")
  file.path(output_dir, files[which.max(dates)])
}

# One shipped file in long form: one row per area, band and metric
read_shipped <- function(level, family, suffix, geoid_col, band_col) {
  path <- latest_file(suffix)
  message("Reading ", path)
  shipped <- read.csv(path, colClasses = setNames("character", geoid_col))

  shipped %>%
    mutate(
      geoid = .data[[geoid_col]],
      band = if (is.na(band_col)) NA_character_ else .data[[band_col]]
    ) %>%
    select(geoid, band, all_of(metrics)) %>%
    pivot_longer(all_of(metrics), names_to = "metric", values_to = "ours") %>%
    mutate(level = level, family = family)
}

shipped_values <- pmap_dfr(shipped_files, read_shipped)

# Join by key, never by row position
comparison <- tool_values %>%
  left_join(shipped_values, by = c("level", "family", "geoid", "band", "metric")) %>%
  mutate(
    gap = ours - tool_value,
    pct_gap = 100 * gap / tool_value,
    rounds_to_tool = round(ours, tool_digits) == tool_value
  )

# A reference row with no shipped value means a key typo or a missing file
unmatched <- comparison %>% filter(is.na(ours))
if (nrow(unmatched) > 0) {
  print(unmatched)
  stop(nrow(unmatched), " tool value(s) have no matching shipped row")
}

comparison %>%
  select(level, family, geoid, band, metric, tool_value, ours, gap, pct_gap, rounds_to_tool) %>%
  mutate(across(c(ours, gap, pct_gap), ~ round(.x, 3))) %>%
  print(n = Inf, width = Inf)

# Matches by level, so each phase reads on its own
comparison %>%
  group_by(level) %>%
  summarize(matches = sum(rounds_to_tool), values = n()) %>%
  ungroup() %>%
  print()

message(
  sum(comparison$rounds_to_tool), " of ", nrow(comparison),
  " shipped values reproduce the LEAD tool at its display precision"
)
