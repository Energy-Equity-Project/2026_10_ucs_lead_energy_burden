# Build the FPL files in outputs/ for the UCS DOE LEAD 2022 energy burden request.
# Reads only cleaned, shared data; never copy shared data into this repo.
# The AMI band files come from R/02_build_ami.R; shared helpers live in R/functions.R.
#
# Produces six national tables (50 states + DC + PR) from the cohort-level LEAD
# file (the FPL file), each aggregated directly from the cohort rows:
#   dd-mm-yyyy-ucs-lead-2022-tract-energy-burden.csv       one row per census tract
#   dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-fpl.csv   one row per tract x FPL band
#   dd-mm-yyyy-ucs-lead-2022-county-energy-burden.csv      one row per county
#   dd-mm-yyyy-ucs-lead-2022-county-energy-burden-fpl.csv  one row per county x FPL band
#   dd-mm-yyyy-ucs-lead-2022-state-energy-burden.csv       one row per state
#   dd-mm-yyyy-ucs-lead-2022-state-energy-burden-fpl.csv   one row per state x FPL band
#
# Method, per area or area x FPL band:
#   1. weighted means of income, electricity, gas and other fuel cost, each weighted
#      by its own valid-units column (e.g. electricity cost by elep_valid_units)
#   2. total_households = sum of the generic `units` column
#   3. after ungroup(): total_utility_cost = electricity + gas + other fuel, and
#      energy_burden = 100 * total_utility_cost / weighted_income
#
# Run from the repo root: Rscript R/01_build.R
# File paths come from the repo's .Renviron (gitignored); copy .Renviron.example
# to .Renviron and fill it in before the first run.

# Load required packages; arrow is namespace-qualified because it masks dplyr verbs
library(tidyverse)
source("R/functions.R")

# Retrieve file paths from environment variables set in .Renviron
path_vars <- c("LEAD_NATIONAL_FILE", "LEAD_ROLLUP_FILE", "OUTPUT_DIR")
paths <- Sys.getenv(path_vars)

if (any(paths == "")) {
  stop(
    "Missing in .Renviron: ", paste(path_vars[paths == ""], collapse = ", "),
    ". Copy .Renviron.example to .Renviron, fill it in and restart R."
  )
}

lead_national_file <- paths[["LEAD_NATIONAL_FILE"]]
lead_rollup_file <- paths[["LEAD_ROLLUP_FILE"]]
output_dir <- paths[["OUTPUT_DIR"]]
run_date <- format(Sys.Date(), "%d-%m-%Y")

# Read inputs: only the columns the summary needs, kept lazy so arrow aggregates
# the 20M cohort rows during the scan
lead_cohorts <- arrow::open_dataset(lead_national_file) %>%
  select(
    state, fip, fpl150, units,
    avg_income, avg_electricity_cost, avg_gas_cost, avg_other_fuel_cost,
    hincp_valid_units, elep_valid_units, gasp_valid_units, fulp_valid_units
  ) %>%
  mutate(county_fip = floor(fip / 1e6))

# LEAD's FPL band labels; the factor orders them from lowest to highest income
fpl_levels <- c("0-100%", "100-150%", "150-200%", "200-400%", "400%+")

# Tract level
tract_energy_burden <- summarize_lead(lead_cohorts, state, fip) %>%
  add_tract_geoids() %>%
  arrange(tract_geoid) %>%
  select(state_fips, county_geoid, tract_geoid, all_of(value_columns))

# Tract by FPL band, grouped by tract and band from the cohorts directly
tract_fpl_energy_burden <- summarize_lead(lead_cohorts, state, fip, fpl150) %>%
  complete_bands(c("state", "fip"), "fpl150", "fpl", fpl_levels) %>%
  add_tract_geoids() %>%
  arrange(tract_geoid, fpl) %>%
  select(state_fips, county_geoid, tract_geoid, fpl, all_of(value_columns))

# County level, built from the cohorts directly rather than from the tract table
county_energy_burden <- summarize_lead(lead_cohorts, state, county_fip) %>%
  add_county_geoids() %>%
  arrange(county_geoid) %>%
  select(state_fips, county_geoid, all_of(value_columns))

# County by FPL band, grouped by county and band from the cohorts directly
county_fpl_energy_burden <- summarize_lead(lead_cohorts, state, county_fip, fpl150) %>%
  complete_bands(c("state", "county_fip"), "fpl150", "fpl", fpl_levels) %>%
  add_county_geoids() %>%
  arrange(county_geoid, fpl) %>%
  select(state_fips, county_geoid, fpl, all_of(value_columns))

# State level, also built from the cohorts directly. The partner asked for the
# averages and household count only, so the per-measure weight columns are left out.
state_energy_burden <- summarize_lead(lead_cohorts, state) %>%
  mutate(state_fips = sprintf("%02d", state)) %>%
  left_join(state_names, by = "state_fips") %>%
  arrange(state_fips) %>%
  select(state_fips, state_abbr, state_name, all_of(state_value_columns))

# State by FPL band, also built from the cohorts directly, with the state file's
# columns plus the band. The full table keeps the weights for the check below.
state_fpl_full <- summarize_lead(lead_cohorts, state, fpl150) %>%
  mutate(
    state_fips = sprintf("%02d", state),
    fpl = factor(fpl150, levels = fpl_levels)
  ) %>%
  left_join(state_names, by = "state_fips") %>%
  arrange(state_fips, fpl)

state_fpl_energy_burden <- state_fpl_full %>%
  mutate(fpl = as.character(fpl)) %>%
  select(state_fips, state_abbr, state_name, fpl, all_of(state_value_columns))

# Checks -----------------------------------------------------------------------

audit <- cohort_audit(lead_cohorts)
cohort_households <- audit$households

stopifnot(
  audit$missing_weights == 0,
  !anyDuplicated(tract_energy_burden$tract_geoid),
  !anyDuplicated(county_energy_burden$county_geoid),
  nrow(tract_energy_burden) == 84280,
  nrow(county_energy_burden) == 3222,
  all(nchar(tract_energy_burden$tract_geoid) == 11),
  all(nchar(county_energy_burden$county_geoid) == 5),
  # Every county's tracts share its state, so county GEOIDs nest inside states
  all(str_sub(county_energy_burden$county_geoid, 1, 2) == county_energy_burden$state_fips),
  abs(sum(tract_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  abs(sum(county_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  nrow(state_energy_burden) == 52,
  !anyDuplicated(state_energy_burden$state_fips),
  !anyNA(state_energy_burden$state_abbr),
  !anyNA(state_energy_burden$energy_burden),
  abs(sum(state_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  nrow(state_fpl_energy_burden) == 52 * length(fpl_levels),
  !anyNA(state_fpl_full$fpl),
  !anyDuplicated(state_fpl_energy_burden[c("state_fips", "fpl")]),
  !anyNA(state_fpl_energy_burden$state_abbr),
  !anyNA(state_fpl_energy_burden$energy_burden),
  abs(sum(state_fpl_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  # Tract and county by FPL band: every area has all five bands, once each
  nrow(tract_fpl_energy_burden) == 84280 * length(fpl_levels),
  nrow(county_fpl_energy_burden) == 3222 * length(fpl_levels),
  !anyNA(tract_fpl_energy_burden$fpl),
  !anyNA(county_fpl_energy_burden$fpl),
  !anyDuplicated(tract_fpl_energy_burden[c("tract_geoid", "fpl")]),
  !anyDuplicated(county_fpl_energy_burden[c("county_geoid", "fpl")]),
  all(nchar(tract_fpl_energy_burden$tract_geoid) == 11),
  all(nchar(county_fpl_energy_burden$county_geoid) == 5),
  abs(sum(tract_fpl_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  abs(sum(county_fpl_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  # Bands with no LEAD cohorts in the area, filled in by complete_bands(); the docs cite these counts
  sum(tract_fpl_energy_burden$total_households == 0) == 754,
  sum(county_fpl_energy_burden$total_households == 0) == 2
)

# Re-weight finer tables up to coarser ones: county and state x FPL up to states,
# tract x FPL up to tracts, county x FPL up to counties
county_state_check <- reweight_to(county_energy_burden, state_energy_burden, "state_fips")
fpl_state_check <- reweight_to(state_fpl_full, state_energy_burden, "state_fips")
tract_fpl_check <- reweight_to(tract_fpl_energy_burden, tract_energy_burden, "tract_geoid")
county_fpl_check <- reweight_to(county_fpl_energy_burden, county_energy_burden, "county_geoid")

stopifnot(
  nrow(county_state_check) == 52,
  nrow(fpl_state_check) == 52,
  nrow(tract_fpl_check) == nrow(tract_energy_burden),
  nrow(county_fpl_check) == nrow(county_energy_burden),
  check_gap(county_state_check) < 1e-9,
  check_gap(fpl_state_check) < 1e-9,
  check_gap(tract_fpl_check) < 1e-9,
  check_gap(county_fpl_check) < 1e-9
)

# Regression against the shared FPL tract rollup. Its 4 negative-weight tracts
# differ slightly and are checked loosely; every other tract must match to
# floating-point noise.
rollup_check <- rollup_regression(lead_rollup_file, tract_energy_burden, audit$negative_weight_tracts)
exact_check <- rollup_check %>% filter(!negative_weight)
loose_check <- rollup_check %>% filter(negative_weight)

stopifnot(
  nrow(rollup_check) == nrow(tract_energy_burden),
  length(audit$negative_weight_tracts) == 4,
  identical(is.na(rollup_check$energy_burden), is.na(rollup_check$rollup_burden)),
  max(exact_check$burden_gap, na.rm = TRUE) < 1e-9,
  max(rollup_check$households_gap) < 1e-9,
  # Observed max is 0.0013 percentage points; 1e-4 allows up to 0.01 points
  max(loose_check$burden_gap, na.rm = TRUE) < 1e-4
)

message(
  "Regression vs shared rollup: max burden gap ", signif(max(exact_check$burden_gap, na.rm = TRUE), 3),
  " (", signif(max(loose_check$burden_gap, na.rm = TRUE), 3), " in the 4 negative-weight tracts)",
  ", max household gap ", signif(max(rollup_check$households_gap), 3)
)
message("Tracts with NA burden: ", sum(is.na(tract_energy_burden$energy_burden)))
message("Counties with NA burden: ", sum(is.na(county_energy_burden$energy_burden)))
message(
  "Tract x FPL rows with NA burden: ", sum(is.na(tract_fpl_energy_burden$energy_burden)),
  " (", sum(tract_fpl_energy_burden$total_households == 0), " are bands with no households)"
)
message(
  "County x FPL rows with NA burden: ", sum(is.na(county_fpl_energy_burden$energy_burden)),
  " (", sum(county_fpl_energy_burden$total_households == 0), " are bands with no households)"
)

state_range <- state_energy_burden %>% arrange(energy_burden) %>% slice(1, n())
message(
  "State burden range: ", state_range$state_abbr[1], " ", round(state_range$energy_burden[1], 2),
  "% to ", state_range$state_abbr[2], " ", round(state_range$energy_burden[2], 2), "%"
)

print_band_spread(state_fpl_energy_burden, "fpl", fpl_levels)

# The docs cite this count; confirm it after every rebuild
high_burden_tracts <- tract_energy_burden %>% filter(energy_burden > 20)
message(
  "Tracts above 20% burden: ", nrow(high_burden_tracts),
  " (largest has ", round(max(high_burden_tracts$total_households)), " households)"
)

# Write outputs; every file and column is documented in outputs/README.md
dir.create(output_dir, showWarnings = FALSE)

write_output(tract_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden.csv"))
write_output(tract_fpl_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden-fpl.csv"))
write_output(county_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden.csv"))
write_output(county_fpl_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden-fpl.csv"))
write_output(state_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden.csv"))
write_output(state_fpl_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden-fpl.csv"))
