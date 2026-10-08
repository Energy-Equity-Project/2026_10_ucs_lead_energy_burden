# Build every file in outputs/ for the UCS DOE LEAD 2022 energy burden request.
# Reads only cleaned, shared data; never copy shared data into this repo.
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

# A few tiny tracts carry a degenerate modeled income (~1e-10) that would give
# burdens near 1e13. Same floor as the shared tract rollup, so the two agree.
income_floor <- 1e-9

# Read inputs: only the columns the summary needs, kept lazy so arrow aggregates
# the 20M cohort rows during the scan
lead_cohorts <- arrow::open_dataset(lead_national_file) %>%
  select(
    state, fip, fpl150, units,
    avg_income, avg_electricity_cost, avg_gas_cost, avg_other_fuel_cost,
    hincp_valid_units, elep_valid_units, gasp_valid_units, fulp_valid_units
  ) %>%
  mutate(county_fip = floor(fip / 1e6))

# Weighted means written as sum(x * w) / sum(w) over rows with a non-NA average
# and a positive weight, which is weighted.mean(x, w, na.rm = TRUE) in a form
# arrow can compute. Non-positive weights are zeroed on purpose: 4 Alaska cohorts
# carry negative valid units (a raw LEAD modeling artifact), and a negative weight
# has no meaning in a mean. A group whose weights are all zero returns NaN, which
# add_totals() sets to NA.
summarize_lead <- function(cohorts, ...) {
  cohorts %>%
    mutate(
      income_w = case_when(is.na(avg_income) | hincp_valid_units <= 0 ~ 0, TRUE ~ hincp_valid_units),
      electric_w = case_when(is.na(avg_electricity_cost) | elep_valid_units <= 0 ~ 0, TRUE ~ elep_valid_units),
      gas_w = case_when(is.na(avg_gas_cost) | gasp_valid_units <= 0 ~ 0, TRUE ~ gasp_valid_units),
      other_fuel_w = case_when(is.na(avg_other_fuel_cost) | fulp_valid_units <= 0 ~ 0, TRUE ~ fulp_valid_units)
    ) %>%
    group_by(...) %>%
    summarize(
      total_households = sum(units),
      income_households = sum(income_w),
      electric_households = sum(electric_w),
      gas_households = sum(gas_w),
      other_fuel_households = sum(other_fuel_w),
      weighted_income = sum(avg_income * income_w, na.rm = TRUE) / sum(income_w),
      weighted_electricity_cost = sum(avg_electricity_cost * electric_w, na.rm = TRUE) / sum(electric_w),
      weighted_gas_cost = sum(avg_gas_cost * gas_w, na.rm = TRUE) / sum(gas_w),
      weighted_other_fuel_cost = sum(avg_other_fuel_cost * other_fuel_w, na.rm = TRUE) / sum(other_fuel_w)
    ) %>%
    collect() %>%
    ungroup() %>%
    add_totals()
}

# Total cost and burden from the weighted averages, shared by the outputs and the
# re-weighting checks so both apply the same rules
add_totals <- function(df) {
  df %>%
    mutate(
      across(starts_with("weighted_"), ~ if_else(is.nan(.x), NA_real_, .x)),
      # A fuel with no valid units in the group adds $0 rather than voiding the total;
      # a group with no valid units for any fuel has no total at all
      total_utility_cost = case_when(
        is.na(weighted_electricity_cost) & is.na(weighted_gas_cost) &
          is.na(weighted_other_fuel_cost) ~ NA_real_,
        TRUE ~ coalesce(weighted_electricity_cost, 0) +
          coalesce(weighted_gas_cost, 0) +
          coalesce(weighted_other_fuel_cost, 0)
      ),
      energy_burden = case_when(
        is.na(weighted_income) | weighted_income < income_floor ~ NA_real_,
        TRUE ~ 100 * total_utility_cost / weighted_income
      )
    )
}

# Shared column order for the tract and county outputs: households, dollars, then burden
value_columns <- c(
  "total_households", "income_households", "electric_households",
  "gas_households", "other_fuel_households",
  "weighted_income", "weighted_electricity_cost", "weighted_gas_cost",
  "weighted_other_fuel_cost", "total_utility_cost", "energy_burden"
)

# LEAD's FPL band labels; the factor orders them from lowest to highest income
fpl_levels <- c("0-100%", "100-150%", "150-200%", "200-400%", "400%+")

# Gives every area all five bands. A band with no LEAD cohorts in the area gets
# zero households and NA averages, cost and burden. `keys` are the area columns as
# text; nesting() is far faster than a grouped complete() over 84k tracts.
complete_fpl <- function(df, keys) {
  df %>%
    mutate(fpl = factor(fpl150, levels = fpl_levels)) %>%
    complete(nesting(!!!syms(keys)), fpl) %>%
    mutate(across(ends_with("_households"), ~ coalesce(.x, 0)))
}

# Tract level; fip is stored as a double, so restore leading zeros as text GEOIDs
tract_energy_burden <- summarize_lead(lead_cohorts, state, fip) %>%
  mutate(
    state_fips = sprintf("%02d", state),
    county_geoid = str_sub(sprintf("%011.0f", fip), 1, 5),
    tract_geoid = sprintf("%011.0f", fip)
  ) %>%
  arrange(tract_geoid) %>%
  select(state_fips, county_geoid, tract_geoid, all_of(value_columns))

# Tract by FPL band, grouped by tract and band from the cohorts directly
tract_fpl_energy_burden <- summarize_lead(lead_cohorts, state, fip, fpl150) %>%
  complete_fpl(c("state", "fip")) %>%
  mutate(
    state_fips = sprintf("%02d", state),
    county_geoid = str_sub(sprintf("%011.0f", fip), 1, 5),
    tract_geoid = sprintf("%011.0f", fip)
  ) %>%
  arrange(tract_geoid, fpl) %>%
  select(state_fips, county_geoid, tract_geoid, fpl, all_of(value_columns))

# County level, built from the cohorts directly rather than from the tract table
county_energy_burden <- summarize_lead(lead_cohorts, state, county_fip) %>%
  mutate(
    state_fips = sprintf("%02d", state),
    county_geoid = sprintf("%05.0f", county_fip)
  ) %>%
  arrange(county_geoid) %>%
  select(state_fips, county_geoid, all_of(value_columns))

# County by FPL band, grouped by county and band from the cohorts directly
county_fpl_energy_burden <- summarize_lead(lead_cohorts, state, county_fip, fpl150) %>%
  complete_fpl(c("state", "county_fip")) %>%
  mutate(
    state_fips = sprintf("%02d", state),
    county_geoid = sprintf("%05.0f", county_fip)
  ) %>%
  arrange(county_geoid, fpl) %>%
  select(state_fips, county_geoid, fpl, all_of(value_columns))

# State level, also built from the cohorts directly. The partner asked for the
# averages and household count only, so the per-measure weight columns are left out.
state_names <- tidycensus::fips_codes %>%
  distinct(state_fips = state_code, state_abbr = state, state_name)

state_energy_burden <- summarize_lead(lead_cohorts, state) %>%
  mutate(state_fips = sprintf("%02d", state)) %>%
  left_join(state_names, by = "state_fips") %>%
  arrange(state_fips) %>%
  select(
    state_fips, state_abbr, state_name, total_households,
    weighted_income, weighted_electricity_cost, weighted_gas_cost,
    weighted_other_fuel_cost, total_utility_cost, energy_burden
  )

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
  select(
    state_fips, state_abbr, state_name, fpl, total_households,
    weighted_income, weighted_electricity_cost, weighted_gas_cost,
    weighted_other_fuel_cost, total_utility_cost, energy_burden
  )

# Checks -----------------------------------------------------------------------

# A missing household count or weight would silently blank out its whole group
cohort_totals <- lead_cohorts %>%
  summarize(
    households = sum(units),
    missing_weights = sum(
      is.na(units) | is.na(hincp_valid_units) | is.na(elep_valid_units) |
        is.na(gasp_valid_units) | is.na(fulp_valid_units)
    )
  ) %>%
  collect()

cohort_households <- cohort_totals$households

stopifnot(
  cohort_totals$missing_weights == 0,
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
  # Bands with no LEAD cohorts in the area, filled in by complete_fpl(); the docs cite these counts
  sum(tract_fpl_energy_burden$total_households == 0) == 754,
  sum(county_fpl_energy_burden$total_households == 0) == 2
)

# Each table comes from the cohorts, so re-weighting a finer table up to a coarser
# one is an independent check of the grouping: county and state x FPL up to states,
# tract x FPL up to tracts, county x FPL up to counties. A group's weighted mean
# times its valid units is its weighted sum, so the two must agree to floating-point
# noise. add_totals() applies the same $0-fuel and income-floor rules as the outputs.
reweight_to <- function(df, target, key) {
  df %>%
    group_by(across(all_of(key))) %>%
    summarize(
      total_households = sum(total_households),
      weighted_income = sum(weighted_income * income_households, na.rm = TRUE) / sum(income_households),
      weighted_electricity_cost = sum(weighted_electricity_cost * electric_households, na.rm = TRUE) / sum(electric_households),
      weighted_gas_cost = sum(weighted_gas_cost * gas_households, na.rm = TRUE) / sum(gas_households),
      weighted_other_fuel_cost = sum(weighted_other_fuel_cost * other_fuel_households, na.rm = TRUE) / sum(other_fuel_households)
    ) %>%
    ungroup() %>%
    add_totals() %>%
    inner_join(target, by = key, suffix = c("_check", ""))
}

# Largest relative difference; Inf if one side is missing where the other is not
relative_gap <- function(x, y) {
  if (!identical(is.na(x), is.na(y))) return(Inf)
  max(abs(x - y) / abs(y), 0, na.rm = TRUE)
}

# Largest relative gap across households, the four averages, total cost and burden
check_columns <- c(
  "total_households", "weighted_income", "weighted_electricity_cost", "weighted_gas_cost",
  "weighted_other_fuel_cost", "total_utility_cost", "energy_burden"
)

check_gap <- function(check) {
  max(map_dbl(check_columns, ~ relative_gap(check[[paste0(.x, "_check")]], check[[.x]])))
}

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

# Regression against the shared tract rollup, an independent implementation of the
# same method. The rollup divides raw sums, so it keeps the 4 negative-weight
# cohorts this build drops; their 4 tracts differ slightly and are checked
# loosely. Every other tract must match to floating-point noise.
negative_weight_tracts <- lead_cohorts %>%
  filter(hincp_valid_units < 0 | elep_valid_units < 0 | gasp_valid_units < 0 | fulp_valid_units < 0) %>%
  distinct(fip) %>%
  collect() %>%
  mutate(tract_geoid = sprintf("%011.0f", fip)) %>%
  pull(tract_geoid)

rollup_check <- arrow::read_parquet(lead_rollup_file) %>%
  mutate(tract_geoid = sprintf("%011.0f", fip)) %>%
  select(tract_geoid, rollup_households = total_households, rollup_burden = avg_energy_burden) %>%
  full_join(tract_energy_burden, by = "tract_geoid") %>%
  mutate(
    burden_gap = abs(energy_burden / 100 - rollup_burden),
    households_gap = abs(total_households - rollup_households),
    negative_weight = tract_geoid %in% negative_weight_tracts
  )

exact_check <- rollup_check %>% filter(!negative_weight)
loose_check <- rollup_check %>% filter(negative_weight)

stopifnot(
  nrow(rollup_check) == nrow(tract_energy_burden),
  length(negative_weight_tracts) == 4,
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

# Burden should fall as income rises; print the spread across states for each band
state_fpl_energy_burden %>%
  group_by(fpl = factor(fpl, levels = fpl_levels)) %>%
  summarize(
    min = round(min(energy_burden), 2),
    median = round(median(energy_burden), 2),
    max = round(max(energy_burden), 2)
  ) %>%
  ungroup() %>%
  print()

# The docs cite this count; confirm it after every rebuild
high_burden_tracts <- tract_energy_burden %>% filter(energy_burden > 20)
message(
  "Tracts above 20% burden: ", nrow(high_burden_tracts),
  " (largest has ", round(max(high_burden_tracts$total_households)), " households)"
)

# Write outputs; every file and column is documented in outputs/README.md
dir.create(output_dir, showWarnings = FALSE)

write.csv(
  tract_energy_burden,
  file.path(output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden.csv")),
  row.names = FALSE,
  na = ""
)

write.csv(
  tract_fpl_energy_burden %>% mutate(fpl = as.character(fpl)),
  file.path(output_dir, paste0(run_date, "-ucs-lead-2022-tract-energy-burden-fpl.csv")),
  row.names = FALSE,
  na = ""
)

write.csv(
  county_energy_burden,
  file.path(output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden.csv")),
  row.names = FALSE,
  na = ""
)

write.csv(
  county_fpl_energy_burden %>% mutate(fpl = as.character(fpl)),
  file.path(output_dir, paste0(run_date, "-ucs-lead-2022-county-energy-burden-fpl.csv")),
  row.names = FALSE,
  na = ""
)

write.csv(
  state_energy_burden,
  file.path(output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden.csv")),
  row.names = FALSE,
  na = ""
)

write.csv(
  state_fpl_energy_burden,
  file.path(output_dir, paste0(run_date, "-ucs-lead-2022-state-energy-burden-fpl.csv")),
  row.names = FALSE,
  na = ""
)
