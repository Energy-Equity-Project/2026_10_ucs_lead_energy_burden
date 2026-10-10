# Build the FPL files in outputs/ for the UCS DOE LEAD 2022 energy burden request.
# Reads only cleaned, shared data; never copy shared data into this repo.
# The AMI band files come from R/02_build_ami.R. Both scripts follow the same steps
# with the shared helpers in R/functions.R; only the config and the files written differ.
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
#      by its own valid-units column (e.g. electricity cost by elep_valid_units).
#      Cohorts with income under $1,000 are left out of every mean, and a negative
#      cost average is left out of that cost's mean (see add_cohort_weights())
#   2. total_households = sum of the generic `units` column, filtered cohorts included
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

# LEAD's FPL band labels; the factor orders them from lowest to highest income
band_col <- "fpl150"
out_col <- "fpl"
fpl_levels <- c("0-100%", "100-150%", "150-200%", "200-400%", "400%+")

# Counts for this input file; a changed file fails the checks. The docs cite them.
expected <- list(
  tracts = 84280, counties = 3222, states = 52,
  negative_weight_rows = 4, negative_weight_tracts = 4,
  low_income_rows = 196592, negative_cost_rows = 10, filtered_tracts = 62432,
  empty_tract_band_rows = 754, empty_county_band_rows = 2,
  na_burden_tract = 17, na_burden_tract_band = 858,
  # Observed max is 0.0013 percentage points in the 4 negative-weight tracts; 1e-4 allows 0.01
  loose_burden_gap = 1e-4
)

# Read inputs: only the columns the summary needs, kept lazy so arrow aggregates
# the 20M cohort rows during the scan
lead_cohorts <- arrow::open_dataset(lead_national_file) %>%
  select(
    state, fip, all_of(band_col), units,
    avg_income, avg_electricity_cost, avg_gas_cost, avg_other_fuel_cost,
    hincp_valid_units, elep_valid_units, gasp_valid_units, fulp_valid_units
  ) %>%
  mutate(county_fip = floor(fip / 1e6))

# Build all six tables from the cohorts directly
tables <- build_tables(lead_cohorts, band_col, out_col, fpl_levels)

# Checks: the same structural, validity, re-weighting and regression checks as the AMI build
audit <- cohort_audit(lead_cohorts)
check_tables(tables, audit, expected, out_col, fpl_levels)
check_rollups(tables, out_col)
check_regression(lead_rollup_file, lead_cohorts, tables, audit, expected$loose_burden_gap)

print_build_summary(tables, out_col, fpl_levels)
print_exclusion_summary(exclusion_summary(lead_cohorts, band_col, fpl_levels))

# Write outputs; every file and column is documented in outputs/README.md
dir.create(output_dir, showWarnings = FALSE)

write_output(select_output(tables$tract, "tract"), output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden.csv"))
write_output(select_output(tables$tract_band, "tract", out_col), output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden-fpl.csv"))
write_output(select_output(tables$county, "county"), output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden.csv"))
write_output(select_output(tables$county_band, "county", out_col), output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden-fpl.csv"))
write_output(select_output(tables$state, "state"), output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden.csv"))
write_output(select_output(tables$state_band, "state", out_col), output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden-fpl.csv"))
