# Compare the shipped UCS files with values read off the DOE LEAD interactive tool.
# Reads only the latest shipped CSVs in OUTPUT_DIR and R/lead_tool_values.R; it does
# not recompute anything and writes no files.
#
# Phase 1: FPL, state level and state x FPL band (Michigan and Alabama).
# Phase 2: county level, overall values only (Wayne County, MI 26163; Perry County, AL 01105).
# Phase 3: tract level, overall values only (Perry tract 6871 01105687100; Wayne tract 5452
# 26163545200). The tool's tract name drops the code's last two digits (6871 = 687100).
# Phase 4: state x AMI band burden (Michigan and Alabama).
# The LEAD tool does not update its FPL band stats when a county or tract is selected, so
# county and tract FPL band values are not checked against it.
# Later phases add rows to `tool_values` in R/lead_tool_values.R and the matching file
# patterns to `shipped_files`.
#
# Run from the repo root: Rscript R/03_check_lead_tool.R

library(tidyverse)

# The match count groups by two keys and is ungrouped explicitly, so dplyr's
# regrouping notice is noise
options(dplyr.summarise.inform = FALSE)

# Retrieve the output folder from .Renviron
output_dir <- Sys.getenv("OUTPUT_DIR")

if (output_dir == "") {
  stop("Missing in .Renviron: OUTPUT_DIR. Copy .Renviron.example to .Renviron, fill it in and restart R.")
}

# Values as the LEAD tool displays them, shared with R/04_diagnose_tool_gaps.R
source("R/lead_tool_values.R")

# Shipped files to check: the file-name suffix after the date, the geography key
# column and the band column (NA for overall files)
shipped_files <- tribble(
  ~level,  ~family, ~suffix,                                ~geoid_col,   ~band_col,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden",     "state_fips", NA,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden-fpl", "state_fips", "fpl",
  "county", "fpl",  "ucs-lead-2022-county-energy-burden",    "county_geoid", NA,
  "tract", "fpl",   "ucs-lead-2022-tract-energy-burden",     "tract_geoid", NA,
  "state", "ami",   "ucs-lead-2022-state-energy-burden-ami", "state_fips", "ami"
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

# Matches by level and band family, so each phase reads on its own
comparison %>%
  group_by(level, family) %>%
  summarize(matches = sum(rounds_to_tool), values = n()) %>%
  ungroup() %>%
  print()

message(
  sum(comparison$rounds_to_tool), " of ", nrow(comparison),
  " shipped values reproduce the LEAD tool at its display precision"
)
