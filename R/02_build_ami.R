# Build the AMI band files in outputs/ for the UCS DOE LEAD 2022 energy burden request.
# Reads only cleaned, shared data; never copy shared data into this repo.
# These sit alongside the FPL files from R/01_build.R. Both scripts follow the same
# steps with the shared helpers in R/functions.R; only the config and the files
# written differ.
#
# Produces four national tables (50 states + DC + PR), each aggregated directly
# from the AMI cohort rows:
#   dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-ami.csv   one row per tract x AMI band
#   dd-mm-yyyy-ucs-lead-2022-county-energy-burden-ami.csv  one row per county x AMI band
#   dd-mm-yyyy-ucs-lead-2022-state-energy-burden.csv       one row per state
#   dd-mm-yyyy-ucs-lead-2022-state-energy-burden-ami.csv   one row per state x AMI band
#
# The AMI file is a separate LEAD model run with its own household counts: 6,258
# tracts (7.4%) differ from the FPL file by more than 0.1%, mostly in CA, NY, MA, HI
# and CT. The overall state file comes from this file because the LEAD tool's state
# household counts are the AMI run's, so it equals the sum of the state AMI bands but
# not of the FPL bands. The overall tract and county files stay FPL-based; their AMI
# tables are built here as check targets but not written.
#
# Run from the repo root: Rscript R/02_build_ami.R
# File paths come from the repo's .Renviron (gitignored); copy .Renviron.example
# to .Renviron and fill it in before the first run.

# Load required packages; arrow is namespace-qualified because it masks dplyr verbs
library(tidyverse)
source("R/functions.R")

# Retrieve file paths from environment variables set in .Renviron
path_vars <- c("LEAD_AMI_NATIONAL_FILE", "LEAD_AMI_ROLLUP_FILE", "OUTPUT_DIR")
paths <- Sys.getenv(path_vars)

if (any(paths == "")) {
  stop(
    "Missing in .Renviron: ", paste(path_vars[paths == ""], collapse = ", "),
    ". Copy .Renviron.example to .Renviron, fill it in and restart R."
  )
}

lead_ami_national_file <- paths[["LEAD_AMI_NATIONAL_FILE"]]
lead_ami_rollup_file <- paths[["LEAD_AMI_ROLLUP_FILE"]]
output_dir <- paths[["OUTPUT_DIR"]]
run_date <- format(Sys.Date(), "%d-%m-%Y")

# LEAD's AMI band labels; the factor orders them from lowest to highest income
band_col <- "ami150"
out_col <- "ami"
ami_levels <- c("0-30%", "30-60%", "60-80%", "80-100%", "100-150%", "150%+")

# Counts for this input file; a changed file fails the checks. The docs cite them.
# All negative weights and negative cost averages are in the 150%+ band.
expected <- list(
  tracts = 84280, counties = 3222, states = 52,
  negative_weight_rows = 7992, negative_weight_tracts = 4441,
  negative_cost_rows = 15635, filtered_tracts = 6417,
  empty_tract_band_rows = 935, empty_county_band_rows = 1,
  na_burden_tract = 17, na_burden_tract_band = 1055,
  # Observed max is 0.083 percentage points in the negative-weight tracts; 1e-3 allows 0.1
  loose_burden_gap = 1e-3
)

# Read inputs: only the columns the summary needs, kept lazy so arrow aggregates
# the 25M cohort rows during the scan
lead_ami_cohorts <- arrow::open_dataset(lead_ami_national_file) %>%
  select(
    state, fip, all_of(band_col), units,
    avg_income, avg_electricity_cost, avg_gas_cost, avg_other_fuel_cost,
    hincp_valid_units, elep_valid_units, gasp_valid_units, fulp_valid_units
  ) %>%
  mutate(county_fip = floor(fip / 1e6))

# Build all six tables from the cohorts directly; the band tables and the state table are written
tables <- build_tables(lead_ami_cohorts, band_col, out_col, ami_levels)

# Checks: the same structural, validity, re-weighting and regression checks as the FPL build
audit <- cohort_audit(lead_ami_cohorts)
check_tables(tables, audit, expected, out_col, ami_levels)
check_rollups(tables, out_col)
check_regression(lead_ami_rollup_file, lead_ami_cohorts, tables, audit, expected$loose_burden_gap)

print_build_summary(tables, out_col, ami_levels)
print_exclusion_summary(exclusion_summary(lead_ami_cohorts, band_col, ami_levels))

# Write outputs; every file and column is documented in outputs/README.md
dir.create(output_dir, showWarnings = FALSE)

write_output(select_output(tables$tract_band, "tract", out_col), output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden-ami.csv"))
write_output(select_output(tables$county_band, "county", out_col), output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden-ami.csv"))
write_output(select_output(tables$state, "state"), output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden.csv"))
write_output(select_output(tables$state_band, "state", out_col), output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden-ami.csv"))
