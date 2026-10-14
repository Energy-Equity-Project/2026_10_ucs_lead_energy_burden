# Shared helpers for the FPL (01_build.R) and AMI (02_build_ami.R) builds, so both
# band families use the same weighting, filters, tables, checks and summaries.
# Sourced from the repo root: source("R/functions.R")

# reweight_to() groups by two keys for the band checks; the outputs are ungrouped
# explicitly, so dplyr's regrouping notice is noise
options(dplyr.summarise.inform = FALSE)

# Group incomes below this get no burden. LEAD keeps near-zero and negative cohort
# incomes, as the LEAD tool does, so a few tract x band groups average to an income
# at or below zero; dividing by it would give a meaningless or negative burden.
income_floor <- 1e-9

# Per-measure weights and the reason flags behind them. A measure's weight is zero
# when its average is NA, its valid units are <= 0 (negative valid units are a raw
# LEAD artifact; a negative weight has no meaning in a mean), or its average is a
# negative cost (a cost cannot be negative; these are LEAD artifacts, almost all in
# AMI 150%+). A row dropped from one measure still counts toward the others.
# exclude_invalid = FALSE drops the negative-cost rule, which is the shared rollup's
# method and is used for the regression check.
add_cohort_weights <- function(cohorts, exclude_invalid = TRUE) {
  if (exclude_invalid) {
    cohorts <- cohorts %>%
      mutate(
        negative_electricity = case_when(is.na(avg_electricity_cost) ~ FALSE, avg_electricity_cost < 0 ~ TRUE, TRUE ~ FALSE),
        negative_gas = case_when(is.na(avg_gas_cost) ~ FALSE, avg_gas_cost < 0 ~ TRUE, TRUE ~ FALSE),
        negative_other_fuel = case_when(is.na(avg_other_fuel_cost) ~ FALSE, avg_other_fuel_cost < 0 ~ TRUE, TRUE ~ FALSE)
      )
  } else {
    cohorts <- cohorts %>%
      mutate(negative_electricity = FALSE, negative_gas = FALSE, negative_other_fuel = FALSE)
  }

  cohorts %>%
    mutate(
      income_w = case_when(
        is.na(avg_income) | hincp_valid_units <= 0 ~ 0,
        TRUE ~ hincp_valid_units
      ),
      electric_w = case_when(
        is.na(avg_electricity_cost) | elep_valid_units <= 0 | negative_electricity ~ 0,
        TRUE ~ elep_valid_units
      ),
      gas_w = case_when(
        is.na(avg_gas_cost) | gasp_valid_units <= 0 | negative_gas ~ 0,
        TRUE ~ gasp_valid_units
      ),
      other_fuel_w = case_when(
        is.na(avg_other_fuel_cost) | fulp_valid_units <= 0 | negative_other_fuel ~ 0,
        TRUE ~ fulp_valid_units
      )
    )
}

# Weighted means written as sum(x * w) / sum(w) over rows with a positive weight,
# which is weighted.mean(x, w, na.rm = TRUE) in a form arrow can compute. A group
# whose weights are all zero returns NaN, which add_totals() sets to NA.
summarize_lead <- function(cohorts, ..., exclude_invalid = TRUE) {
  cohorts %>%
    add_cohort_weights(exclude_invalid) %>%
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

# Geography columns written ahead of the band and values at each level
geography_columns <- list(
  tract = c("state_fips", "county_geoid", "tract_geoid"),
  county = c("state_fips", "county_geoid"),
  state = c("state_fips", "state_abbr", "state_name")
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

add_state_names <- function(df) {
  df %>%
    mutate(state_fips = sprintf("%02d", state)) %>%
    left_join(state_names, by = "state_fips")
}

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

# All six tables for one band family, each aggregated directly from the cohort rows,
# with every column kept so the checks can use the weights. Scripts choose which
# tables to write and select their columns with select_output().
build_tables <- function(cohorts, band_col, out_col, levels, exclude_invalid = TRUE) {
  band <- sym(band_col)
  list(
    tract = summarize_lead(cohorts, state, fip, exclude_invalid = exclude_invalid) %>%
      add_tract_geoids() %>%
      arrange(tract_geoid),
    tract_band = summarize_lead(cohorts, state, fip, !!band, exclude_invalid = exclude_invalid) %>%
      complete_bands(c("state", "fip"), band_col, out_col, levels) %>%
      add_tract_geoids() %>%
      arrange(tract_geoid, .data[[out_col]]),
    county = summarize_lead(cohorts, state, county_fip, exclude_invalid = exclude_invalid) %>%
      add_county_geoids() %>%
      arrange(county_geoid),
    county_band = summarize_lead(cohorts, state, county_fip, !!band, exclude_invalid = exclude_invalid) %>%
      complete_bands(c("state", "county_fip"), band_col, out_col, levels) %>%
      add_county_geoids() %>%
      arrange(county_geoid, .data[[out_col]]),
    state = summarize_lead(cohorts, state, exclude_invalid = exclude_invalid) %>%
      add_state_names() %>%
      arrange(state_fips),
    state_band = summarize_lead(cohorts, state, !!band, exclude_invalid = exclude_invalid) %>%
      complete_bands("state", band_col, out_col, levels) %>%
      add_state_names() %>%
      arrange(state_fips, .data[[out_col]])
  )
}

# Output columns for a table: geography, then the band (band tables only), then values.
# The state files carry the averages and household count only, as the partner asked.
select_output <- function(df, level, out_col = NULL) {
  values <- if (level == "state") state_value_columns else value_columns
  df %>% select(all_of(c(geography_columns[[level]], out_col, values)))
}

# Each table comes from the cohorts, so re-weighting a finer table up to a coarser
# one is an independent check of the grouping. A group's weighted mean times its
# weight is its weighted sum, so the two must agree to floating-point noise.
# The means come before the weight sums: summarize() would otherwise reuse the
# summed weight columns in the means. add_totals() applies the output rules.
reweight_to <- function(df, target, key) {
  df %>%
    group_by(across(all_of(key))) %>%
    summarize(
      weighted_income = sum(weighted_income * income_households, na.rm = TRUE) / sum(income_households),
      weighted_electricity_cost = sum(weighted_electricity_cost * electric_households, na.rm = TRUE) / sum(electric_households),
      weighted_gas_cost = sum(weighted_gas_cost * gas_households, na.rm = TRUE) / sum(gas_households),
      weighted_other_fuel_cost = sum(weighted_other_fuel_cost * other_fuel_households, na.rm = TRUE) / sum(other_fuel_households),
      total_households = sum(total_households),
      income_households = sum(income_households),
      electric_households = sum(electric_households),
      gas_households = sum(gas_households),
      other_fuel_households = sum(other_fuel_households)
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

# Largest relative gap across households, the weights, the four averages, total cost and burden
check_gap <- function(check) {
  max(map_dbl(value_columns, ~ relative_gap(check[[paste0(.x, "_check")]], check[[.x]])))
}

# Re-weights every finer table up to every coarser one: across levels, from each band
# table to its overall table, and across levels within the band tables. Stops on any
# gap of 1e-9 relative or more, or on a target group with no finer rows.
check_rollups <- function(tables, out_col) {
  checks <- list(
    "tract to county" = list(tables$tract, tables$county, "county_geoid"),
    "county to state" = list(tables$county, tables$state, "state_fips"),
    "tract to state" = list(tables$tract, tables$state, "state_fips"),
    "tract x band to tract" = list(tables$tract_band, tables$tract, "tract_geoid"),
    "county x band to county" = list(tables$county_band, tables$county, "county_geoid"),
    "state x band to state" = list(tables$state_band, tables$state, "state_fips"),
    "tract x band to county x band" = list(tables$tract_band, tables$county_band, c("county_geoid", out_col)),
    "county x band to state x band" = list(tables$county_band, tables$state_band, c("state_fips", out_col)),
    "tract x band to state x band" = list(tables$tract_band, tables$state_band, c("state_fips", out_col))
  )

  results <- imap_dfr(checks, function(args, name) {
    joined <- reweight_to(args[[1]], args[[2]], args[[3]])
    tibble(check = name, rows = nrow(joined), target_rows = nrow(args[[2]]), max_gap = check_gap(joined))
  })

  failed <- results %>% filter(rows != target_rows | max_gap >= 1e-9)
  if (nrow(failed) > 0) {
    print(failed)
    stop("Re-weighting checks failed: ", paste(failed$check, collapse = ", "))
  }
  message("Re-weighting checks passed (", nrow(results), "), max gap ", signif(max(results$max_gap), 3))
  invisible(results)
}

# Missing household counts or weights would silently blank out whole groups. Also
# counts the rows and tracts behind each exclusion rule: negative valid units (zeroed
# under either rule) and the negative-cost filter.
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

  flagged_tracts <- cohorts %>%
    add_cohort_weights() %>%
    mutate(
      negative_weight = hincp_valid_units < 0 | elep_valid_units < 0 | gasp_valid_units < 0 | fulp_valid_units < 0,
      negative_cost = negative_electricity | negative_gas | negative_other_fuel
    ) %>%
    filter(negative_weight | negative_cost) %>%
    group_by(fip) %>%
    summarize(
      negative_weight = sum(negative_weight),
      negative_cost = sum(negative_cost)
    ) %>%
    collect() %>%
    ungroup() %>%
    mutate(tract_geoid = sprintf("%011.0f", fip))

  list(
    households = totals$households,
    missing_weights = totals$missing_weights,
    negative_weight_rows = sum(flagged_tracts$negative_weight),
    negative_weight_tracts = flagged_tracts$tract_geoid[flagged_tracts$negative_weight > 0],
    negative_cost_rows = sum(flagged_tracts$negative_cost),
    # Tracts where the negative-cost filter can change a value; every other tract must match the unfiltered build
    filtered_tracts = flagged_tracts$tract_geoid[flagged_tracts$negative_cost > 0]
  )
}

# Structural and validity checks, identical for both band families. `expected` holds
# the family's counts, so a changed input file fails the build.
check_tables <- function(tables, audit, expected, out_col, levels) {
  n_bands <- length(levels)
  band_tables <- c("tract_band", "county_band", "state_band")
  key_columns <- list(
    tract = "tract_geoid", tract_band = c("tract_geoid", out_col),
    county = "county_geoid", county_band = c("county_geoid", out_col),
    state = "state_fips", state_band = c("state_fips", out_col)
  )
  expected_rows <- c(
    tract = expected$tracts, tract_band = expected$tracts * n_bands,
    county = expected$counties, county_band = expected$counties * n_bands,
    state = expected$states, state_band = expected$states * n_bands
  )
  households_ok <- function(df) abs(sum(df$total_households) - audit$households) < 1e-6 * audit$households
  # Costs, total cost and burden are never negative
  values_valid <- function(df) {
    all(c(df$weighted_electricity_cost, df$weighted_gas_cost, df$weighted_other_fuel_cost,
          df$total_utility_cost, df$energy_burden) >= 0, na.rm = TRUE)
  }
  nests <- function(df) {
    all(str_sub(df$county_geoid, 1, 2) == df$state_fips) &&
      (!"tract_geoid" %in% names(df) || all(str_sub(df$tract_geoid, 1, 5) == df$county_geoid))
  }

  stopifnot(
    audit$missing_weights == 0,
    audit$negative_weight_rows == expected$negative_weight_rows,
    length(audit$negative_weight_tracts) == expected$negative_weight_tracts,
    audit$negative_cost_rows == expected$negative_cost_rows,
    length(audit$filtered_tracts) == expected$filtered_tracts,
    all(map_int(tables, nrow) == expected_rows[names(tables)]),
    all(imap_lgl(tables, ~ !anyDuplicated(.x[key_columns[[.y]]]))),
    all(map_lgl(tables[band_tables], ~ !anyNA(.x[[out_col]]))),
    all(map_lgl(tables, households_ok)),
    all(map_lgl(tables, values_valid)),
    all(nchar(tables$tract$tract_geoid) == 11),
    all(nchar(tables$tract_band$tract_geoid) == 11),
    all(nchar(tables$county$county_geoid) == 5),
    all(nchar(tables$county_band$county_geoid) == 5),
    all(map_lgl(tables[c("tract", "tract_band", "county", "county_band")], nests)),
    !anyNA(tables$state$state_abbr),
    !anyNA(tables$state_band$state_abbr),
    !anyNA(tables$state$energy_burden),
    !anyNA(tables$state_band$energy_burden),
    # Bands with no LEAD cohorts in the area, filled in by complete_bands(); the docs cite these counts
    sum(tables$tract_band$total_households == 0) == expected$empty_tract_band_rows,
    sum(tables$county_band$total_households == 0) == expected$empty_county_band_rows,
    sum(tables$state_band$total_households == 0) == 0,
    # Blank burdens; the docs cite these counts
    sum(is.na(tables$tract$energy_burden)) == expected$na_burden_tract,
    sum(is.na(tables$tract_band$energy_burden)) == expected$na_burden_tract_band,
    sum(is.na(tables$county$energy_burden)) == 0,
    sum(is.na(tables$county_band$energy_burden)) == expected$empty_county_band_rows
  )
  message("Structural and validity checks passed")
}

# Regression against a shared tract rollup, an independent implementation of the
# unfiltered method. Two checks:
#   1. The unfiltered tract table must match the rollup to floating-point noise, except
#      in tracts with negative-weight cohorts, which the rollup keeps (loose tolerance).
#   2. The filtered tract table must match the unfiltered one in every tract without a
#      negative cost average, so the negative-cost filter changes only those tracts.
check_regression <- function(rollup_file, cohorts, tables, audit, loose_tolerance) {
  unfiltered_tract <- summarize_lead(cohorts, state, fip, exclude_invalid = FALSE) %>%
    add_tract_geoids()

  rollup_check <- arrow::read_parquet(rollup_file) %>%
    mutate(tract_geoid = sprintf("%011.0f", fip)) %>%
    select(tract_geoid, rollup_households = total_households, rollup_burden = avg_energy_burden) %>%
    full_join(unfiltered_tract, by = "tract_geoid") %>%
    mutate(
      burden_gap = abs(energy_burden / 100 - rollup_burden),
      households_gap = abs(total_households - rollup_households),
      negative_weight = tract_geoid %in% audit$negative_weight_tracts
    )
  exact_check <- rollup_check %>% filter(!negative_weight)
  loose_check <- rollup_check %>% filter(negative_weight)

  untouched <- unfiltered_tract %>%
    filter(!tract_geoid %in% audit$filtered_tracts) %>%
    select(tract_geoid, all_of(value_columns)) %>%
    inner_join(tables$tract, by = "tract_geoid", suffix = c("_check", ""))

  stopifnot(
    nrow(rollup_check) == nrow(tables$tract),
    identical(is.na(rollup_check$energy_burden), is.na(rollup_check$rollup_burden)),
    max(exact_check$burden_gap, na.rm = TRUE) < 1e-9,
    max(rollup_check$households_gap) < 1e-9,
    max(loose_check$burden_gap, na.rm = TRUE) < loose_tolerance,
    nrow(untouched) == nrow(tables$tract) - length(audit$filtered_tracts),
    check_gap(untouched) < 1e-9
  )

  message(
    "Regression vs shared rollup (unfiltered): max burden gap ", signif(max(exact_check$burden_gap, na.rm = TRUE), 3),
    " (", signif(max(loose_check$burden_gap, na.rm = TRUE), 3), " in the ", nrow(loose_check),
    " negative-weight tracts), max household gap ", signif(max(rollup_check$households_gap), 3)
  )
  message(
    "Filtered vs unfiltered: ", nrow(untouched), " untouched tracts match (max gap ",
    signif(check_gap(untouched), 3), "); ", length(audit$filtered_tracts), " tracts hold filtered cohorts"
  )
}

# What the negative-cost filter leaves out, by band: rows flagged, the share of each
# fuel's weight it removes, the share of households with no valid data before any
# filter, national burden before and after, and the spread of the change across
# states. Printed by both builds; the partner README cites these numbers.
exclusion_summary <- function(cohorts, band_col, levels) {
  state_change <- summarize_lead(cohorts, state, band = .data[[band_col]], exclude_invalid = FALSE) %>%
    select(state, band, energy_burden_unfiltered = energy_burden) %>%
    inner_join(summarize_lead(cohorts, state, band = .data[[band_col]]), by = c("state", "band")) %>%
    mutate(change = energy_burden - energy_burden_unfiltered) %>%
    group_by(band = factor(band, levels = levels)) %>%
    summarize(
      states_changed = sum(abs(change) > 1e-9 * abs(energy_burden_unfiltered)),
      min_change = min(change),
      median_change = median(change),
      max_change = max(change)
    ) %>%
    ungroup()

  list(national = national_exclusions(cohorts, band_col, levels), state = state_change)
}

national_exclusions <- function(cohorts, band_col, levels) {
  weight_sums <- function(df) {
    df %>%
      summarize(
        households = sum(units),
        income = sum(income_w), electricity = sum(electric_w),
        gas = sum(gas_w), other_fuel = sum(other_fuel_w),
        negative_cost_rows = sum(negative_electricity | negative_gas | negative_other_fuel)
      ) %>%
      collect() %>%
      ungroup()
  }
  by_band <- function(exclude_invalid) {
    weighted <- cohorts %>% add_cohort_weights(exclude_invalid)
    bind_rows(
      weighted %>% group_by(band = .data[[band_col]]) %>% weight_sums(),
      weighted %>% weight_sums() %>% mutate(band = "all")
    )
  }
  burden <- function(exclude_invalid) {
    bind_rows(
      summarize_lead(cohorts, band = .data[[band_col]], exclude_invalid = exclude_invalid),
      summarize_lead(cohorts, exclude_invalid = exclude_invalid) %>% mutate(band = "all")
    ) %>%
      select(band, energy_burden)
  }

  before <- by_band(FALSE)
  after <- by_band(TRUE)
  before %>%
    select(band, households, income, electricity, gas, other_fuel) %>%
    inner_join(
      after %>% select(band, negative_cost_rows, electricity, gas, other_fuel),
      by = "band", suffix = c("", "_kept")
    ) %>%
    inner_join(burden(FALSE), by = "band") %>%
    inner_join(burden(TRUE), by = "band", suffix = c("_unfiltered", "")) %>%
    transmute(
      band = factor(band, levels = c(levels, "all")),
      households = round(households),
      negative_cost_rows,
      # Share of each fuel's valid weight the negative-cost filter removes
      pct_electricity_removed = 100 * (1 - electricity_kept / electricity),
      pct_gas_removed = 100 * (1 - gas_kept / gas),
      pct_other_fuel_removed = 100 * (1 - other_fuel_kept / other_fuel),
      # Share of households with no valid data for the measure, before any filter
      pct_no_valid_income = 100 * (1 - income / households),
      pct_no_valid_electricity = 100 * (1 - electricity / households),
      pct_no_valid_gas = 100 * (1 - gas / households),
      pct_no_valid_other_fuel = 100 * (1 - other_fuel / households),
      energy_burden_unfiltered, energy_burden,
      burden_change = energy_burden - energy_burden_unfiltered
    ) %>%
    arrange(band)
}

print_exclusion_summary <- function(exclusions) {
  rounded <- exclusions$national %>% mutate(across(where(is.double), ~ round(.x, 3)))
  message("Negative cost averages left out of the averages, by band (percent of each fuel's valid weight):")
  print(rounded %>% select(band, households, negative_cost_rows, ends_with("_removed")), width = Inf)
  message("Households with no valid data before any filter (percent), and national burden before and after:")
  print(rounded %>% select(band, starts_with("pct_no_valid"), energy_burden_unfiltered, energy_burden, burden_change), width = Inf)
  message("Change in state x band burden from the negative-cost filter (percentage points):")
  print(exclusions$state %>% mutate(across(where(is.double), ~ round(.x, 3))), width = Inf)
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

# Counts the docs cite, printed the same way for both families
print_build_summary <- function(tables, out_col, levels) {
  lowest_band <- levels[1]
  tract_band <- tables$tract_band
  message("Cohort households: ", round(sum(tables$state$total_households)))
  message("Tracts with NA burden: ", sum(is.na(tables$tract$energy_burden)))
  message(
    "Tract x band rows with NA burden: ", sum(is.na(tract_band$energy_burden)),
    " (", sum(tract_band$total_households == 0), " are bands with no households)"
  )
  message(
    "County x band rows with NA burden: ", sum(is.na(tables$county_band$energy_burden)),
    " (", sum(tables$county_band$total_households == 0), " are bands with no households)"
  )
  message(
    "Tract x band rows under 10 households: ",
    sum(tract_band$total_households > 0 & tract_band$total_households < 10)
  )
  message(
    "Tract x band rows in ", lowest_band, " above 20% / 100% burden: ",
    sum(tract_band[[out_col]] == lowest_band & tract_band$energy_burden > 20, na.rm = TRUE), " / ",
    sum(tract_band[[out_col]] == lowest_band & tract_band$energy_burden > 100, na.rm = TRUE),
    " (max ", round(max(tract_band$energy_burden, na.rm = TRUE), 1), "%)"
  )
  high_burden_tracts <- tables$tract %>% filter(energy_burden > 20)
  message(
    "Tracts above 20% burden: ", nrow(high_burden_tracts),
    " (largest has ", round(max(c(0, high_burden_tracts$total_households))), " households)"
  )
  state_range <- tables$state %>% arrange(energy_burden) %>% slice(1, n())
  message(
    "State burden range: ", state_range$state_abbr[1], " ", round(state_range$energy_burden[1], 2),
    "% to ", state_range$state_abbr[2], " ", round(state_range$energy_burden[2], 2), "%"
  )
  print_band_spread(tables$state_band, out_col, levels)
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
