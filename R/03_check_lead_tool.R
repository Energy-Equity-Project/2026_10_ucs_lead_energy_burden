# Compare the shipped UCS files with values read off the DOE LEAD interactive tool.
# Reads only the latest shipped CSVs in OUTPUT_DIR and R/lead_tool_values.R; it does
# not recompute anything from cohorts and writes no files. The only derived values are
# the fuel burdens, each shipped fuel cost as a percent of shipped income.
#
# Phase 1: state level and state x FPL band (Michigan and Alabama). The overall state file
# comes from the AMI cohort file (R/02_build_ami.R); it keeps the `fpl` key because the
# tool's overall rows in `tool_values` are labeled `fpl`.
# Phase 2: county level, overall values only (Wayne County, MI 26163; Perry County, AL 01105).
# Phase 3: tract level, overall values only (Perry tract 6871 01105687100; Wayne tract 5452
# 26163545200). The tool's tract name drops the code's last two digits (6871 = 687100).
# Phase 4: state x AMI band burden (Michigan and Alabama).
# Phase 5: electricity, gas and other fuel burden for the FPL bands that missed the tool
# (MI 0-100%, 100-150%, 150-200%; AL 0-100%, 100-150%, 150-200%), counted apart from the rest.
# Band burdens and total costs are also scored the way the tool builds them: the three
# fuels rounded to whole numbers, then added (`tool_rule`). Overall burdens are not; the
# tool rounds them as a whole.
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
# column and the band column (NA for overall files). The overall state file is built from
# the AMI cohort file but keyed `fpl`, like the tool's overall rows.
shipped_files <- tribble(
  ~level,  ~family, ~suffix,                                ~geoid_col,   ~band_col,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden",     "state_fips", NA,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden-fpl", "state_fips", "fpl",
  "county", "fpl",  "ucs-lead-2022-county-energy-burden",    "county_geoid", NA,
  "tract", "fpl",   "ucs-lead-2022-tract-energy-burden",     "tract_geoid", NA,
  "state", "ami",   "ucs-lead-2022-state-energy-burden-ami", "state_fips", "ami"
)

fuel_burdens <- c("electricity_burden", "gas_burden", "other_fuel_burden")
fuel_costs <- c("weighted_electricity_cost", "weighted_gas_cost", "weighted_other_fuel_cost")
metrics <- c("energy_burden", "total_utility_cost", "total_households", "weighted_income", fuel_burdens, fuel_costs)

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
      band = if (is.na(band_col)) NA_character_ else .data[[band_col]],
      # Each fuel's cost as a percent of income, blank where the build blanks the burden
      across(
        c(electricity_burden = weighted_electricity_cost, gas_burden = weighted_gas_cost,
          other_fuel_burden = weighted_other_fuel_cost),
        ~ case_when(is.na(weighted_income) | weighted_income < 1e-9 ~ NA_real_, TRUE ~ 100 * .x / weighted_income)
      )
    ) %>%
    select(geoid, band, all_of(metrics)) %>%
    pivot_longer(all_of(metrics), names_to = "metric", values_to = "ours") %>%
    mutate(level = level, family = family)
}

shipped_values <- pmap_dfr(shipped_files, read_shipped)

# The tool totals rounded fuels: total cost is the sum of the rounded fuel costs, and a
# band panel burden the sum of the rounded fuel burdens. Overall burdens are rounded as a
# whole (rounding their fuels first breaks 3 of the 6 overall matches). A missing fuel
# adds 0, as in the build.
fuel_rounded_sums <- shipped_values %>%
  filter(metric %in% fuel_costs | (metric %in% fuel_burdens & !is.na(band))) %>%
  mutate(metric = case_when(metric %in% fuel_burdens ~ "energy_burden", TRUE ~ "total_utility_cost")) %>%
  group_by(level, family, geoid, band, metric) %>%
  summarize(fuel_rounded_sum = sum(round(ours), na.rm = TRUE)) %>%
  ungroup()

# Join by key, never by row position
comparison <- tool_values %>%
  left_join(shipped_values, by = c("level", "family", "geoid", "band", "metric")) %>%
  left_join(fuel_rounded_sums, by = c("level", "family", "geoid", "band", "metric")) %>%
  mutate(
    gap = ours - tool_value,
    pct_gap = case_when(tool_value == 0 ~ NA_real_, TRUE ~ 100 * gap / tool_value),
    rounds_to_tool = round(ours, tool_digits) == tool_value,
    # Burdens and total costs as the tool builds them; other values as displayed
    tool_rule = case_when(!is.na(fuel_rounded_sum) ~ fuel_rounded_sum == tool_value, TRUE ~ rounds_to_tool)
  )

# A reference row with no shipped value means a key typo or a missing file
unmatched <- comparison %>% filter(is.na(ours))
if (nrow(unmatched) > 0) {
  print(unmatched)
  stop(nrow(unmatched), " tool value(s) have no matching shipped row")
}

comparison %>%
  select(level, family, geoid, band, metric, tool_value, ours, gap, pct_gap, rounds_to_tool, fuel_rounded_sum, tool_rule) %>%
  mutate(across(c(ours, gap, pct_gap), ~ round(.x, 3))) %>%
  print(n = Inf, width = Inf)

# Matches by level, band family and kind of value, so each phase reads on its own
comparison <- comparison %>%
  mutate(kind = case_when(metric %in% fuel_burdens ~ "fuel burdens", TRUE ~ "headline"))

comparison %>%
  group_by(kind, level, family) %>%
  summarize(matches = sum(rounds_to_tool), tool_rule_matches = sum(tool_rule), values = n()) %>%
  ungroup() %>%
  print()

headline <- comparison %>% filter(kind == "headline")
fuel <- comparison %>% filter(kind == "fuel burdens")
message(
  sum(comparison$rounds_to_tool), " of ", nrow(comparison),
  " shipped values reproduce the LEAD tool at its display precision (",
  sum(headline$rounds_to_tool), " of ", nrow(headline), " headline values, ",
  sum(fuel$rounds_to_tool), " of ", nrow(fuel), " fuel burdens)"
)
message(
  sum(comparison$tool_rule), " of ", nrow(comparison),
  " match when burdens and total costs are built as the tool builds them (",
  sum(headline$tool_rule), " of ", nrow(headline), " headline values)"
)
misses <- comparison %>% filter(!tool_rule)
if (nrow(misses) > 0) {
  message("Values that still miss under the tool's rule:")
  misses %>% select(level, family, geoid, band, metric, tool_value, ours, fuel_rounded_sum) %>% print(width = Inf)
}
