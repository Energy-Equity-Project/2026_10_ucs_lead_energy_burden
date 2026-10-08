# Build the AMI band files in outputs/ for the UCS DOE LEAD 2022 energy burden request.
# Reads only cleaned, shared data; never copy shared data into this repo.
# These sit alongside the FPL files from R/01_build.R and use the same helpers and
# method (R/functions.R), applied to LEAD's Area Median Income (AMI) cohort file.
#
# Produces three national tables (50 states + DC + PR), each aggregated directly
# from the AMI cohort rows:
#   dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-ami.csv   one row per tract x AMI band
#   dd-mm-yyyy-ucs-lead-2022-county-energy-burden-ami.csv  one row per county x AMI band
#   dd-mm-yyyy-ucs-lead-2022-state-energy-burden-ami.csv   one row per state x AMI band
#
# The AMI file is a separate LEAD model run: its household counts differ from the FPL
# file's in about 7% of tracts (mostly CA and CT), so these bands do not sum to the
# overall FPL-based tract, county and state files. The checks below therefore compare
# against overall tables built from the AMI file itself, which are not written.
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

# Read inputs: only the columns the summary needs, kept lazy so arrow aggregates
# the 25M cohort rows during the scan
lead_ami_cohorts <- arrow::open_dataset(lead_ami_national_file) %>%
  select(
    state, fip, ami150, units,
    avg_income, avg_electricity_cost, avg_gas_cost, avg_other_fuel_cost,
    hincp_valid_units, elep_valid_units, gasp_valid_units, fulp_valid_units
  ) %>%
  mutate(county_fip = floor(fip / 1e6))

# LEAD's AMI band labels; the factor orders them from lowest to highest income
ami_levels <- c("0-30%", "30-60%", "60-80%", "80-100%", "100-150%", "150%+")

# Tract by AMI band, grouped by tract and band from the cohorts directly
tract_ami_energy_burden <- summarize_lead(lead_ami_cohorts, state, fip, ami150) %>%
  complete_bands(c("state", "fip"), "ami150", "ami", ami_levels) %>%
  add_tract_geoids() %>%
  arrange(tract_geoid, ami) %>%
  select(state_fips, county_geoid, tract_geoid, ami, all_of(value_columns))

# County by AMI band, grouped by county and band from the cohorts directly
county_ami_energy_burden <- summarize_lead(lead_ami_cohorts, state, county_fip, ami150) %>%
  complete_bands(c("state", "county_fip"), "ami150", "ami", ami_levels) %>%
  add_county_geoids() %>%
  arrange(county_geoid, ami) %>%
  select(state_fips, county_geoid, ami, all_of(value_columns))

# State by AMI band, with the FPL state file's columns plus the band. The full
# table keeps the weights for the check below.
state_ami_full <- summarize_lead(lead_ami_cohorts, state, ami150) %>%
  mutate(
    state_fips = sprintf("%02d", state),
    ami = factor(ami150, levels = ami_levels)
  ) %>%
  left_join(state_names, by = "state_fips") %>%
  arrange(state_fips, ami)

state_ami_energy_burden <- state_ami_full %>%
  mutate(ami = as.character(ami)) %>%
  select(state_fips, state_abbr, state_name, ami, all_of(state_value_columns))

# Overall AMI tables, built only as targets for the re-weighting and rollup checks
tract_ami_overall <- summarize_lead(lead_ami_cohorts, state, fip) %>% add_tract_geoids()
county_ami_overall <- summarize_lead(lead_ami_cohorts, state, county_fip) %>% add_county_geoids()
state_ami_overall <- summarize_lead(lead_ami_cohorts, state) %>% mutate(state_fips = sprintf("%02d", state))

# Checks -----------------------------------------------------------------------

audit <- cohort_audit(lead_ami_cohorts)
cohort_households <- audit$households

stopifnot(
  audit$missing_weights == 0,
  # All negative weights are in the 150%+ band; a changed input file fails here
  audit$negative_weight_rows == 7992,
  length(audit$negative_weight_tracts) == 4441,
  nrow(tract_ami_overall) == 84280,
  nrow(county_ami_overall) == 3222,
  nrow(state_ami_overall) == 52,
  # Every area has all six bands, once each
  nrow(tract_ami_energy_burden) == 84280 * length(ami_levels),
  nrow(county_ami_energy_burden) == 3222 * length(ami_levels),
  nrow(state_ami_energy_burden) == 52 * length(ami_levels),
  !anyNA(tract_ami_energy_burden$ami),
  !anyNA(county_ami_energy_burden$ami),
  !anyNA(state_ami_full$ami),
  !anyDuplicated(tract_ami_energy_burden[c("tract_geoid", "ami")]),
  !anyDuplicated(county_ami_energy_burden[c("county_geoid", "ami")]),
  !anyDuplicated(state_ami_energy_burden[c("state_fips", "ami")]),
  all(nchar(tract_ami_energy_burden$tract_geoid) == 11),
  all(nchar(county_ami_energy_burden$county_geoid) == 5),
  all(str_sub(county_ami_energy_burden$county_geoid, 1, 2) == county_ami_energy_burden$state_fips),
  !anyNA(state_ami_energy_burden$state_abbr),
  !anyNA(state_ami_energy_burden$energy_burden),
  abs(sum(tract_ami_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  abs(sum(county_ami_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  abs(sum(state_ami_energy_burden$total_households) - cohort_households) < 1e-6 * cohort_households,
  # Bands with no LEAD cohorts in the area, filled in by complete_bands(); the docs cite these counts
  sum(tract_ami_energy_burden$total_households == 0) == 935,
  sum(county_ami_energy_burden$total_households == 0) == 1
)

# Re-weight each band table up to the overall AMI table at the same level
tract_ami_check <- reweight_to(tract_ami_energy_burden, tract_ami_overall, "tract_geoid")
county_ami_check <- reweight_to(county_ami_energy_burden, county_ami_overall, "county_geoid")
state_ami_check <- reweight_to(state_ami_full, state_ami_overall, "state_fips")

stopifnot(
  nrow(tract_ami_check) == 84280,
  nrow(county_ami_check) == 3222,
  nrow(state_ami_check) == 52,
  check_gap(tract_ami_check) < 1e-9,
  check_gap(county_ami_check) < 1e-9,
  check_gap(state_ami_check) < 1e-9
)

# Regression against the shared AMI tract rollup. Tracts holding negative-weight
# cohorts differ because the rollup keeps those rows; every other tract must match
# to floating-point noise, and household counts must match everywhere.
rollup_check <- rollup_regression(lead_ami_rollup_file, tract_ami_overall, audit$negative_weight_tracts)
exact_check <- rollup_check %>% filter(!negative_weight)
loose_check <- rollup_check %>% filter(negative_weight)

stopifnot(
  nrow(rollup_check) == 84280,
  identical(is.na(rollup_check$energy_burden), is.na(rollup_check$rollup_burden)),
  max(exact_check$burden_gap, na.rm = TRUE) < 1e-9,
  max(rollup_check$households_gap) < 1e-9,
  # Observed max is 0.083 percentage points; 1e-3 allows up to 0.1 points
  max(loose_check$burden_gap, na.rm = TRUE) < 1e-3
)

message(
  "Regression vs shared AMI rollup: max burden gap ", signif(max(exact_check$burden_gap, na.rm = TRUE), 3),
  " (", signif(max(loose_check$burden_gap, na.rm = TRUE), 3), " in the ",
  nrow(loose_check), " negative-weight tracts)",
  ", max household gap ", signif(max(rollup_check$households_gap), 3)
)
message("AMI cohort households: ", round(cohort_households))
message(
  "Tract x AMI rows with NA burden: ", sum(is.na(tract_ami_energy_burden$energy_burden)),
  " (", sum(tract_ami_energy_burden$total_households == 0), " are bands with no households)"
)
message(
  "County x AMI rows with NA burden: ", sum(is.na(county_ami_energy_burden$energy_burden)),
  " (", sum(county_ami_energy_burden$total_households == 0), " are bands with no households)"
)
message(
  "Tract x AMI rows under 10 households: ",
  sum(tract_ami_energy_burden$total_households > 0 & tract_ami_energy_burden$total_households < 10)
)
message(
  "Tract x AMI rows in 0-30% above 20% burden: ",
  sum(tract_ami_energy_burden$ami == "0-30%" & tract_ami_energy_burden$energy_burden > 20, na.rm = TRUE)
)

print_band_spread(state_ami_energy_burden, "ami", ami_levels)

# Write outputs; every file and column is documented in outputs/README.md
dir.create(output_dir, showWarnings = FALSE)

write_output(tract_ami_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden-ami.csv"))
write_output(county_ami_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden-ami.csv"))
write_output(state_ami_energy_burden, output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden-ami.csv"))
