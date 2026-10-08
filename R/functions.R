# Shared helpers for the FPL (01_build.R) and AMI (02_build_ami.R) builds, so both
# band families use the same weighting, totals, band filling and checks.
# Sourced from the repo root: source("R/functions.R")

# A few tiny tracts carry a degenerate modeled income (~1e-10) that would give
# burdens near 1e13. Same floor as the shared tract rollup, so the two agree.
income_floor <- 1e-9

# Weighted means written as sum(x * w) / sum(w) over rows with a non-NA average
# and a positive weight, which is weighted.mean(x, w, na.rm = TRUE) in a form
# arrow can compute. Non-positive weights are zeroed on purpose: some cohorts
# carry negative valid units (a raw LEAD modeling artifact; 4 in FPL, 7,992 in AMI),
# and a negative weight has no meaning in a mean. A group whose weights are all
# zero returns NaN, which add_totals() sets to NA.
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

# State file columns: the averages and household count, without the weight columns
state_value_columns <- c(
  "total_households", "weighted_income", "weighted_electricity_cost", "weighted_gas_cost",
  "weighted_other_fuel_cost", "total_utility_cost", "energy_burden"
)

# fip is stored as a double, so restore leading zeros as text GEOIDs
add_tract_geoids <- function(df) {
  df %>%
    mutate(
      state_fips = sprintf("%02d", state),
      county_geoid = str_sub(sprintf("%011.0f", fip), 1, 5),
      tract_geoid = sprintf("%011.0f", fip)
    )
}

add_county_geoids <- function(df) {
  df %>%
    mutate(
      state_fips = sprintf("%02d", state),
      county_geoid = sprintf("%05.0f", county_fip)
    )
}

state_names <- tidycensus::fips_codes %>%
  distinct(state_fips = state_code, state_abbr = state, state_name)

# Gives every area every band. `band_col` is LEAD's band column (fpl150 or ami150),
# `out_col` the ordered factor written to the output (fpl or ami). A band with no
# LEAD cohorts in the area gets zero households and NA averages, cost and burden.
# `keys` are the area columns as text; nesting() is far faster than a grouped
# complete() over 84k tracts.
complete_bands <- function(df, keys, band_col, out_col, levels) {
  df %>%
    mutate(!!out_col := factor(.data[[band_col]], levels = levels)) %>%
    complete(nesting(!!!syms(keys)), !!sym(out_col)) %>%
    mutate(across(ends_with("_households"), ~ coalesce(.x, 0)))
}

# Each table comes from the cohorts, so re-weighting a finer table up to a coarser
# one is an independent check of the grouping. A group's weighted mean times its
# valid units is its weighted sum, so the two must agree to floating-point noise.
# add_totals() applies the same $0-fuel and income-floor rules as the outputs.
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
check_gap <- function(check) {
  max(map_dbl(state_value_columns, ~ relative_gap(check[[paste0(.x, "_check")]], check[[.x]])))
}

# A missing household count or weight would silently blank out its whole group;
# also counts the cohort rows and tracts with a negative valid-units weight
cohort_audit <- function(cohorts) {
  totals <- cohorts %>%
    summarize(
      households = sum(units),
      missing_weights = sum(
        is.na(units) | is.na(hincp_valid_units) | is.na(elep_valid_units) |
          is.na(gasp_valid_units) | is.na(fulp_valid_units)
      )
    ) %>%
    collect()

  negative_weight_tracts <- cohorts %>%
    filter(hincp_valid_units < 0 | elep_valid_units < 0 | gasp_valid_units < 0 | fulp_valid_units < 0) %>%
    count(fip) %>%
    collect() %>%
    mutate(tract_geoid = sprintf("%011.0f", fip))

  list(
    households = totals$households,
    missing_weights = totals$missing_weights,
    negative_weight_rows = sum(negative_weight_tracts$n),
    negative_weight_tracts = negative_weight_tracts$tract_geoid
  )
}

# Regression against a shared tract rollup, an independent implementation of the
# same method. The rollup divides raw sums, so it keeps the negative-weight cohorts
# the builds drop; tracts containing them are flagged so they can be checked loosely.
rollup_regression <- function(rollup_file, tract_table, negative_weight_tracts) {
  arrow::read_parquet(rollup_file) %>%
    mutate(tract_geoid = sprintf("%011.0f", fip)) %>%
    select(tract_geoid, rollup_households = total_households, rollup_burden = avg_energy_burden) %>%
    full_join(tract_table, by = "tract_geoid") %>%
    mutate(
      burden_gap = abs(energy_burden / 100 - rollup_burden),
      households_gap = abs(total_households - rollup_households),
      negative_weight = tract_geoid %in% negative_weight_tracts
    )
}

# Burden should fall as income rises; print the spread across states for each band
print_band_spread <- function(state_band_table, band_col, levels) {
  state_band_table %>%
    group_by(band = factor(.data[[band_col]], levels = levels)) %>%
    summarize(
      min = round(min(energy_burden), 2),
      median = round(median(energy_burden), 2),
      max = round(max(energy_burden), 2)
    ) %>%
    ungroup() %>%
    rename(!!band_col := band) %>%
    print()
}

# Write one output CSV with blank missing values and the band factor as text
write_output <- function(df, output_dir, file_name) {
  write.csv(
    df %>% mutate(across(where(is.factor), as.character)),
    file.path(output_dir, file_name),
    row.names = FALSE,
    na = ""
  )
}
