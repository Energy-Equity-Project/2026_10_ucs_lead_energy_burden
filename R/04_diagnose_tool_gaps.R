# Diagnose the gaps between the shipped UCS files and the DOE LEAD interactive tool.
# Recomputes the values in R/lead_tool_values.R for MI and AL under variants that each
# turn off one filter or test one hypothesis about the tool, and counts matches at the
# tool's display precision. Results are written up in LEAD_TOOL_DISCREPANCIES.md.
# Reads the two cohort parquets, the shared FPL rollup, the shipped CSVs and the raw
# LEAD county and tract CSVs for MI and AL; writes no files. Takes about 35 seconds.
#
# Run from the repo root: Rscript R/04_diagnose_tool_gaps.R

library(tidyverse)
source("R/functions.R")
source("R/lead_tool_values.R")
options(width = 250, pillar.sigfig = 7)

# Retrieve file paths from environment variables set in .Renviron
path_vars <- c("LEAD_NATIONAL_FILE", "LEAD_AMI_NATIONAL_FILE", "LEAD_ROLLUP_FILE", "LEAD_RAW_DIR", "OUTPUT_DIR")
paths <- Sys.getenv(path_vars)

if (any(paths == "")) {
  stop(
    "Missing in .Renviron: ", paste(path_vars[paths == ""], collapse = ", "),
    ". Copy .Renviron.example to .Renviron, fill it in and restart R."
  )
}

raw_dir <- paths[["LEAD_RAW_DIR"]]

metrics <- c("energy_burden", "total_utility_cost", "total_households", "weighted_income")
key_cols <- c("level", "family", "geoid", "band", "metric")

# ---- Inputs: MI and AL cohorts from both parquets, and the raw county files ----

cohort_cols <- c(
  "state", "fip", "units", "avg_income", "avg_electricity_cost", "avg_gas_cost", "avg_other_fuel_cost",
  "hincp_valid_units", "elep_valid_units", "gasp_valid_units", "fulp_valid_units",
  "hincp_x_units", "elep_x_units", "gasp_x_units", "fulp_x_units"
)

read_cohorts <- function(file, band_col) {
  arrow::open_dataset(file) %>%
    filter(state %in% c(1, 26)) %>%
    select(all_of(c(cohort_cols, band_col))) %>%
    collect() %>%
    rename(band = all_of(band_col)) %>%
    mutate(county_fip = floor(fip / 1e6))
}

fpl <- read_cohorts(paths[["LEAD_NATIONAL_FILE"]], "fpl150")
ami <- read_cohorts(paths[["LEAD_AMI_NATIONAL_FILE"]], "ami150")

# Raw "<ST> <FAMILY> Counties 2022.csv" files, cleaned the way the processor cleans the
# tract files. FIP is the 5-digit county code here.
read_county_file <- function(abbr, family) {
  file.path(raw_dir, paste0(abbr, "-2022-LEAD-data"), paste0(abbr, " ", family, " Counties 2022.csv")) %>%
    read.csv(check.names = FALSE) %>%
    janitor::clean_names() %>%
    rename(
      hincp_x_units = hincp_units, elep_x_units = elep_units, gasp_x_units = gasp_units, fulp_x_units = fulp_units,
      hincp_valid_units = hincp_units_2, elep_valid_units = elep_units_2,
      gasp_valid_units = gasp_units_2, fulp_valid_units = fulp_units_2
    ) %>%
    rename(band = all_of(if (family == "FPL") "fpl150" else "ami150")) %>%
    mutate(
      county_fip = fip,
      avg_income = case_when(hincp_valid_units > 0 ~ hincp_x_units / hincp_valid_units, TRUE ~ NA_real_),
      avg_electricity_cost = case_when(elep_valid_units > 0 ~ elep_x_units / elep_valid_units, TRUE ~ NA_real_),
      avg_gas_cost = case_when(gasp_valid_units > 0 ~ gasp_x_units / gasp_valid_units, TRUE ~ NA_real_),
      avg_other_fuel_cost = case_when(fulp_valid_units > 0 ~ fulp_x_units / fulp_valid_units, TRUE ~ NA_real_)
    )
}

county_fpl <- map_dfr(c("MI", "AL"), read_county_file, family = "FPL")
county_ami <- map_dfr(c("MI", "AL"), read_county_file, family = "AMI")

# ---- Summarizers: cohort rows + grouping columns -> the four checked metrics ----

# The shipped weight rule with switches, so each rule can be changed on its own.
# income_min drops cohorts with a lower average income from every measure (the shipped
# rule keeps every income; 1000 recomputes the rule removed on 2026-10-14).
# weight = "units" swaps every positive weight for the cohort's units.
rule_weights <- function(d, income_min, drop_negative_cost, weight) {
  d %>%
    mutate(
      low_income = coalesce(avg_income < income_min, FALSE),
      negative_electricity = drop_negative_cost & coalesce(avg_electricity_cost < 0, FALSE),
      negative_gas = drop_negative_cost & coalesce(avg_gas_cost < 0, FALSE),
      negative_other_fuel = drop_negative_cost & coalesce(avg_other_fuel_cost < 0, FALSE),
      income_w = case_when(is.na(avg_income) | hincp_valid_units <= 0 | low_income ~ 0, TRUE ~ hincp_valid_units),
      electric_w = case_when(is.na(avg_electricity_cost) | elep_valid_units <= 0 | low_income | negative_electricity ~ 0, TRUE ~ elep_valid_units),
      gas_w = case_when(is.na(avg_gas_cost) | gasp_valid_units <= 0 | low_income | negative_gas ~ 0, TRUE ~ gasp_valid_units),
      other_fuel_w = case_when(is.na(avg_other_fuel_cost) | fulp_valid_units <= 0 | low_income | negative_other_fuel ~ 0, TRUE ~ fulp_valid_units),
      across(c(income_w, electric_w, gas_w, other_fuel_w), ~ case_when(weight == "units" & .x > 0 ~ units, TRUE ~ .x))
    )
}

weighted_summary <- function(income_min = -Inf, drop_negative_cost = TRUE, weight = "valid") {
  function(d, ...) {
    d %>%
      rule_weights(income_min, drop_negative_cost, weight) %>%
      group_by(...) %>%
      summarize(
        total_households = sum(units),
        weighted_income = sum(avg_income * income_w, na.rm = TRUE) / sum(income_w),
        weighted_electricity_cost = sum(avg_electricity_cost * electric_w, na.rm = TRUE) / sum(electric_w),
        weighted_gas_cost = sum(avg_gas_cost * gas_w, na.rm = TRUE) / sum(gas_w),
        weighted_other_fuel_cost = sum(avg_other_fuel_cost * other_fuel_w, na.rm = TRUE) / sum(other_fuel_w)
      ) %>%
      ungroup() %>%
      add_totals()
  }
}

# Ratio of raw sums, every row kept (the shared rollup's method). The denominators
# can be swapped for units to test "averaged over all households".
ratio_summary <- function(income_denom = "hincp_valid_units",
                          cost_denoms = c("elep_valid_units", "gasp_valid_units", "fulp_valid_units")) {
  function(d, ...) {
    d %>%
      group_by(...) %>%
      summarize(
        total_households = sum(units),
        weighted_income = sum(hincp_x_units, na.rm = TRUE) / sum(.data[[income_denom]]),
        weighted_electricity_cost = sum(elep_x_units, na.rm = TRUE) / sum(.data[[cost_denoms[1]]]),
        weighted_gas_cost = sum(gasp_x_units, na.rm = TRUE) / sum(.data[[cost_denoms[2]]]),
        weighted_other_fuel_cost = sum(fulp_x_units, na.rm = TRUE) / sum(.data[[cost_denoms[3]]])
      ) %>%
      ungroup() %>%
      add_totals()
  }
}

# Units-weighted mean of cohort burdens (an average of ratios), shipped exclusions plus
# cohorts under $1,000 of income, whose burdens would otherwise be near infinite.
# The other three metrics stay as in the shipped rule.
cohort_burden_summary <- function(d, ...) {
  burden <- d %>%
    add_cohort_weights() %>%
    filter(income_w > 0, avg_income >= 1000) %>%
    mutate(cohort_burden = 100 * (coalesce(avg_electricity_cost * (electric_w > 0), 0) +
      coalesce(avg_gas_cost * (gas_w > 0), 0) + coalesce(avg_other_fuel_cost * (other_fuel_w > 0), 0)) / avg_income) %>%
    group_by(...) %>%
    summarize(burden_of_means = sum(cohort_burden * units) / sum(units)) %>%
    ungroup()
  summarize_lead(d, ...) %>%
    inner_join(burden, by = map_chr(enquos(...), rlang::as_label)) %>%
    mutate(energy_burden = burden_of_means)
}

shipped_rule <- function(d, ...) summarize_lead(d, ...)
unfiltered_rule <- function(d, ...) summarize_lead(d, ..., exclude_invalid = FALSE)

# ---- Values for the 46 keys under one variant ----

long_values <- function(df, level, family, geo_col, geo_fmt) {
  df %>%
    mutate(
      geoid = sprintf(geo_fmt, .data[[geo_col]]),
      band = if ("band" %in% names(df)) as.character(band) else NA_character_,
      level = level, family = family
    ) %>%
    select(level, family, geoid, band, all_of(metrics)) %>%
    pivot_longer(all_of(metrics), names_to = "metric", values_to = "value")
}

# Overall values from `overall` (the FPL file unless stated); band values from each family's own file.
# Tract-level sources set has_tracts = FALSE.
variant_values <- function(summarizer, overall = fpl, fpl_bands = fpl, ami_bands = ami, has_tracts = TRUE) {
  bind_rows(
    summarizer(overall, state) %>% long_values("state", "fpl", "state", "%02.0f"),
    summarizer(fpl_bands, state, band) %>% long_values("state", "fpl", "state", "%02.0f"),
    summarizer(overall, county_fip) %>% long_values("county", "fpl", "county_fip", "%05.0f"),
    if (has_tracts) summarizer(overall, fip) %>% long_values("tract", "fpl", "fip", "%011.0f"),
    summarizer(ami_bands, state, band) %>% long_values("state", "ami", "state", "%02.0f")
  )
}

variants <- list(
  "V0 shipped rule" = variant_values(shipped_rule),
  "V1 former $1,000 income rule" = variant_values(weighted_summary(income_min = 1000)),
  "V2 no negative-cost rule" = variant_values(weighted_summary(drop_negative_cost = FALSE)),
  "V3 unfiltered (weighted.mean)" = variant_values(unfiltered_rule),
  "V4 ratio of raw sums" = variant_values(ratio_summary()),
  "V5 income rule at <= $0" = variant_values(weighted_summary(income_min = 1e-9)),
  "V6 costs over all households" = variant_values(ratio_summary(cost_denoms = rep("units", 3))),
  "V7 all over all households" = variant_values(ratio_summary("units", rep("units", 3))),
  "V8 mean of cohort burdens" = variant_values(cohort_burden_summary),
  "V9a overall from AMI file, shipped" = variant_values(shipped_rule, overall = ami),
  "V9b overall from AMI file, unfiltered" = variant_values(ratio_summary(), overall = ami),
  "V10a county files, ratio of sums" = variant_values(ratio_summary(), overall = county_fpl, fpl_bands = county_fpl, ami_bands = county_ami, has_tracts = FALSE),
  "V10b county files, shipped rule" = variant_values(shipped_rule, overall = county_fpl, fpl_bands = county_fpl, ami_bands = county_ami, has_tracts = FALSE),
  "V10c AMI county file overall, ratio" = variant_values(ratio_summary(), overall = county_ami, fpl_bands = county_fpl, ami_bands = county_ami, has_tracts = FALSE)
)

# The variants score the four headline metrics; the fuel burden rows are scored in the C4 section
comparison <- imap_dfr(variants, ~ tool_values %>% filter(metric %in% metrics) %>% left_join(.x, by = key_cols) %>% mutate(variant = .y)) %>%
  mutate(
    variant = factor(variant, levels = names(variants)),
    scale = 10^tool_digits,
    match_round = round(value, tool_digits) == tool_value,
    match_half_up = floor(value * scale + 0.5) / scale == tool_value,
    match_floor = floor(value * scale) / scale == tool_value
  )

# ---- Sanity checks: the diagnostic must reproduce both existing methods ----

# V0 must equal the shipped CSVs (also confirms the 08-10-2026 outputs are current)
latest_file <- function(suffix) {
  files <- list.files(paths[["OUTPUT_DIR"]], pattern = paste0("^\\d{2}-\\d{2}-\\d{4}-", suffix, "\\.csv$"))
  file.path(paths[["OUTPUT_DIR"]], files[which.max(as.Date(str_sub(files, 1, 10), format = "%d-%m-%Y"))])
}
shipped <- tribble(
  ~level,  ~family, ~suffix,                                ~geo_col,       ~band_col,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden",     "state_fips",   NA,
  "state", "fpl",   "ucs-lead-2022-state-energy-burden-fpl", "state_fips",   "fpl",
  "county", "fpl",  "ucs-lead-2022-county-energy-burden",    "county_geoid", NA,
  "tract", "fpl",   "ucs-lead-2022-tract-energy-burden",     "tract_geoid",  NA,
  "state", "ami",   "ucs-lead-2022-state-energy-burden-ami", "state_fips",   "ami"
) %>%
  pmap_dfr(function(level, family, suffix, geo_col, band_col) {
    read.csv(latest_file(suffix), colClasses = setNames("character", geo_col)) %>%
      mutate(geoid = .data[[geo_col]], band = if (is.na(band_col)) NA_character_ else .data[[band_col]]) %>%
      select(geoid, band, all_of(metrics)) %>%
      pivot_longer(all_of(metrics), names_to = "metric", values_to = "shipped") %>%
      mutate(level = level, family = family)
  })

v0_check <- comparison %>%
  filter(variant == "V0 shipped rule") %>%
  left_join(shipped, by = key_cols) %>%
  mutate(rel_gap = abs(value - shipped) / abs(shipped))
message("V0 vs shipped CSVs: max relative gap ", signif(max(v0_check$rel_gap), 3), " over ", nrow(v0_check), " values")
stopifnot(max(v0_check$rel_gap) < 1e-9)

# The switchable rule with its defaults must equal the shipped rule
v0_switch <- variant_values(weighted_summary()) %>% inner_join(variants[["V0 shipped rule"]], by = key_cols)
stopifnot(max(abs(v0_switch$value.x - v0_switch$value.y) / abs(v0_switch$value.y), na.rm = TRUE) < 1e-9)

# V3 and V4 must equal the shared rollup for the two checked tracts
rollup <- arrow::read_parquet(paths[["LEAD_ROLLUP_FILE"]]) %>%
  mutate(geoid = sprintf("%011.0f", fip)) %>%
  filter(geoid %in% c("01105687100", "26163545200")) %>%
  transmute(geoid, energy_burden = 100 * avg_energy_burden, total_households, weighted_income) %>%
  pivot_longer(-geoid, names_to = "metric", values_to = "rollup")
rollup_check <- comparison %>%
  filter(level == "tract", variant %in% c("V3 unfiltered (weighted.mean)", "V4 ratio of raw sums")) %>%
  inner_join(rollup, by = c("geoid", "metric")) %>%
  mutate(rel_gap = abs(value - rollup) / abs(rollup))
message("V3/V4 vs shared rollup (2 tracts): max relative gap ", signif(max(rollup_check$rel_gap), 3))
stopifnot(max(rollup_check$rel_gap) < 1e-9)

# ---- Results ----

message("\nMatches out of the values each variant can produce, by display rule:")
comparison %>%
  group_by(variant) %>%
  summarize(
    values = sum(!is.na(value)),
    round = sum(match_round, na.rm = TRUE),
    half_up = sum(match_half_up, na.rm = TRUE),
    floor = sum(match_floor, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  print(n = Inf)

message("\nMatches under round(), by level and family (matches/values):")
comparison %>%
  group_by(variant, group = paste(level, family, sep = "_")) %>%
  summarize(cell = paste0(sum(match_round, na.rm = TRUE), "/", sum(!is.na(value)))) %>%
  ungroup() %>%
  pivot_wider(names_from = group, values_from = cell) %>%
  print(n = Inf)

# Per-value table: each variant's value next to the tool's; a trailing * marks a match under round()
per_value <- comparison %>%
  mutate(
    short = str_extract(as.character(variant), "^V\\d+[a-c]?"),
    shown = case_when(
      is.na(value) ~ "",
      metric == "energy_burden" ~ sprintf("%.2f%s", value, if_else(match_round, "*", "")),
      TRUE ~ sprintf("%.0f%s", value, if_else(match_round, "*", ""))
    ),
    key = paste(level, family, geoid, coalesce(band, "all"), str_remove(metric, "total_|weighted_|energy_"))
  ) %>%
  select(key, tool = tool_value, short, shown) %>%
  pivot_wider(names_from = short, values_from = shown)

message("\nPer-value results (* = matches the tool under round()):")
print(as.data.frame(per_value), right = TRUE, row.names = FALSE)

# Income gap to the tool, in percent, for the six areas
message("\nIncome gap to the tool (percent), by variant:")
comparison %>%
  filter(metric == "weighted_income") %>%
  mutate(pct_gap = round(100 * (value - tool_value) / tool_value, 3), area = paste(level, geoid)) %>%
  select(area, variant, pct_gap) %>%
  pivot_wider(names_from = area, values_from = pct_gap) %>%
  print(n = Inf)

# Household counts by source, against the tool
message("\nHousehold counts by source:")
household_sources <- list(
  "FPL tract file" = fpl, "AMI tract file" = ami, "FPL county file" = county_fpl, "AMI county file" = county_ami
)
imap_dfr(household_sources, function(d, source) {
  bind_rows(
    d %>% group_by(geoid = sprintf("%02.0f", state)) %>% summarize(households = sum(units)) %>% ungroup(),
    d %>% filter(county_fip %in% c(26163, 1105)) %>% group_by(geoid = sprintf("%05.0f", county_fip)) %>%
      summarize(households = sum(units)) %>% ungroup()
  ) %>%
    mutate(source = source)
}) %>%
  left_join(tool_values %>% filter(metric == "total_households", level != "tract") %>% select(geoid, tool = tool_value), by = "geoid") %>%
  mutate(gap = round(households - tool, 2)) %>%
  arrange(geoid, source) %>%
  print(n = Inf)

# ---- Upstream processor checks (P1, P3, P4) ----

# P3: does the processor's read_csv() type guessing lose values? Compare raw sums,
# read as text and parsed explicitly, with the parquet sums for MI and AL.
message("\nRaw tract CSV vs parquet (P1, P3):")
sum_cols <- c("units", "hincp_x_units", "elep_x_units", "gasp_x_units", "fulp_x_units",
              "hincp_valid_units", "elep_valid_units", "gasp_valid_units", "fulp_valid_units")
raw_vs_parquet <- expand_grid(abbr = c("MI", "AL"), family = c("FPL", "AMI")) %>%
  pmap_dfr(function(abbr, family) {
    raw_file <- file.path(raw_dir, paste0(abbr, "-2022-LEAD-data"), paste0(abbr, " ", family, " Census Tracts 2022.csv"))
    guessed <- read_csv(raw_file, show_col_types = FALSE)
    raw <- read_csv(raw_file, col_types = cols(.default = col_character())) %>%
      janitor::clean_names() %>%
      rename(
        hincp_x_units = hincp_units, elep_x_units = elep_units, gasp_x_units = gasp_units, fulp_x_units = fulp_units,
        hincp_valid_units = hincp_units_2, elep_valid_units = elep_units_2,
        gasp_valid_units = gasp_units_2, fulp_valid_units = fulp_units_2
      ) %>%
      mutate(across(all_of(sum_cols), as.numeric))
    parquet <- (if (family == "FPL") fpl else ami) %>% filter(state == if (abbr == "MI") 26 else 1)
    tibble(
      file = paste(abbr, family),
      raw_rows = nrow(raw), parquet_rows = nrow(parquet),
      read_csv_problems = nrow(problems(guessed)),
      raw_na_cells = sum(is.na(raw[sum_cols])),
      max_rel_sum_gap = max(map_dbl(sum_cols, ~ abs(sum(raw[[.x]]) - sum(parquet[[.x]])) / abs(sum(raw[[.x]]))))
    )
  })
print(raw_vs_parquet)

# P4: rows whose numerator is nonzero but whose valid units are <= 0, so the processor
# sets the average to NA and drops the numerator. National counts from both files.
message("\nNonzero numerator with valid units <= 0 (P4), national:")
map_dfr(c(fpl = paths[["LEAD_NATIONAL_FILE"]], ami = paths[["LEAD_AMI_NATIONAL_FILE"]]), function(file) {
  arrow::open_dataset(file) %>%
    summarize(
      income = sum(hincp_x_units != 0 & hincp_valid_units <= 0, na.rm = TRUE),
      electricity = sum(elep_x_units != 0 & elep_valid_units <= 0, na.rm = TRUE),
      gas = sum(gasp_x_units != 0 & gasp_valid_units <= 0, na.rm = TRUE),
      other_fuel = sum(fulp_x_units != 0 & fulp_valid_units <= 0, na.rm = TRUE)
    ) %>%
    collect()
}, .id = "file") %>%
  print()

# ---- T4 follow-up: is the tool's band burden an average of area burdens? ----
# The band misses survive every cohort-level variant, so test averages of tract x band
# and county x band burdens (unfiltered, which reproduces the tool's income): plain
# mean, household-weighted mean and median across the state's areas.
message("\nState x band burden as an average of area x band burdens (unfiltered), with matches marked *:")
area_band_averages <- function(d, family, area_col) {
  unfiltered_rule(d, state, area = .data[[area_col]], band) %>%
    filter(total_households > 0, !is.na(energy_burden)) %>%
    group_by(state, band) %>%
    summarize(
      mean = mean(energy_burden),
      household_mean = sum(energy_burden * total_households) / sum(total_households),
      median = median(energy_burden)
    ) %>%
    ungroup() %>%
    mutate(family = family, geoid = sprintf("%02.0f", state), areas = area_col)
}
band_averages <- bind_rows(
  area_band_averages(fpl, "fpl", "fip"), area_band_averages(fpl, "fpl", "county_fip"),
  area_band_averages(ami, "ami", "fip"), area_band_averages(ami, "ami", "county_fip")
) %>%
  pivot_longer(c(mean, household_mean, median), names_to = "stat", values_to = "value") %>%
  inner_join(tool_values %>% filter(level == "state", !is.na(band), metric == "energy_burden"), by = c("family", "geoid", "band"))

band_averages %>%
  mutate(shown = sprintf("%.2f%s", value, if_else(round(value, tool_digits) == tool_value, "*", "")),
         col = paste(if_else(areas == "fip", "tract", "county"), stat, sep = "_")) %>%
  select(family, geoid, band, tool = tool_value, col, shown) %>%
  pivot_wider(names_from = col, values_from = shown) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

band_averages %>%
  group_by(areas, stat) %>%
  summarize(matches = sum(round(value, tool_digits) == tool_value), values = n()) %>%
  ungroup() %>%
  print()

# ---- C1 follow-up: does the tool add rounded fuel costs? ----
message("\nUnfiltered fuel costs and two ways of totalling them, against the tool's total:")
comparison_cost <- bind_rows(
  unfiltered_rule(fpl, state) %>% mutate(geoid = sprintf("%02.0f", state), level = "state"),
  unfiltered_rule(fpl, county_fip) %>% mutate(geoid = sprintf("%05.0f", county_fip), level = "county"),
  unfiltered_rule(fpl, fip) %>% mutate(geoid = sprintf("%011.0f", fip), level = "tract")
) %>%
  inner_join(tool_values %>% filter(metric == "total_utility_cost") %>% select(level, geoid, tool = tool_value), by = c("level", "geoid")) %>%
  transmute(
    level, geoid, tool,
    electricity = round(weighted_electricity_cost, 2), gas = round(weighted_gas_cost, 2),
    other_fuel = round(weighted_other_fuel_cost, 2), total = round(total_utility_cost, 2),
    sum_of_rounded = round(weighted_electricity_cost) + round(weighted_gas_cost) + round(weighted_other_fuel_cost)
  )
print(comparison_cost)

# ---- C4: does the tool total rounded fuel burdens? ----
# For the FPL bands with tool fuel burdens: our fuel burdens (shipped rule) next to the
# tool's, our fuel burdens totalled after rounding each one three ways, and the tool's
# own fuel burdens totalled, each against the tool's total burden. Then every state band
# and overall burden, rounded as a whole and as the sum of rounded fuel burdens.
fuel_cols <- c("electricity", "gas", "other_fuel")
tool_fuel <- tool_values %>%
  filter(level == "state", family == "fpl", !is.na(band),
         metric %in% c("energy_burden", "electricity_burden", "gas_burden", "other_fuel_burden")) %>%
  mutate(metric = paste0("tool_", str_remove(metric, "_burden"))) %>%
  select(geoid, band, metric, tool_value) %>%
  pivot_wider(names_from = metric, values_from = tool_value) %>%
  filter(!is.na(tool_electricity)) %>%
  rename(tool_total = tool_energy)

fuel_bands <- shipped_rule(fpl, state, band) %>%
  transmute(
    geoid = sprintf("%02.0f", state), band = as.character(band),
    electricity = 100 * coalesce(weighted_electricity_cost, 0) / weighted_income,
    gas = 100 * coalesce(weighted_gas_cost, 0) / weighted_income,
    other_fuel = 100 * coalesce(weighted_other_fuel_cost, 0) / weighted_income,
    total = energy_burden
  ) %>%
  inner_join(tool_fuel, by = c("geoid", "band")) %>%
  mutate(
    sum_nearest = round(electricity) + round(gas) + round(other_fuel),
    sum_up = ceiling(electricity) + ceiling(gas) + ceiling(other_fuel),
    sum_down = floor(electricity) + floor(gas) + floor(other_fuel),
    tool_sum = tool_electricity + tool_gas + tool_other_fuel
  )
stopifnot(nrow(fuel_bands) == nrow(tool_fuel))

message("\nFuel burdens (percent of income) and totals, shipped rule vs the tool:")
fuel_bands %>%
  mutate(across(c(all_of(fuel_cols), total), ~ round(.x, 3))) %>%
  select(geoid, band, electricity, tool_electricity, gas, tool_gas, other_fuel, tool_other_fuel,
         total, tool_total, sum_nearest, sum_up, sum_down, tool_sum) %>%
  print(width = Inf)

message("\nBand totals matching the tool, by rule (of ", nrow(fuel_bands), "):")
fuel_bands %>%
  summarize(
    fuel_burdens_matched = paste0(sum(round(electricity) == tool_electricity & round(gas) == tool_gas &
                                        round(other_fuel) == tool_other_fuel), " bands"),
    shipped_total_rounded = sum(round(total) == tool_total),
    sum_nearest = sum(sum_nearest == tool_total),
    sum_up = sum(sum_up == tool_total),
    sum_down = sum(sum_down == tool_total),
    tool_own_sum = sum(tool_sum == tool_total)
  ) %>%
  print(width = Inf)

# Range of multipliers that make all four of our values round to the tool's displays.
# A display d holds values in [d - 0.5, d + 0.5); for a value v divided by k that gives
# v / (d + 0.5) < k <= v / (d - 0.5), with no upper bound when d is 0.
upper_k <- function(v, d) case_when(d > 0 ~ v / (d - 0.5), TRUE ~ Inf)
fits_display <- function(v, d) v >= d - 0.5 & v < d + 0.5

multipliers <- fuel_bands %>%
  mutate(
    # Income times k divides every burden by k
    income_k_low = pmax(electricity / (tool_electricity + 0.5), gas / (tool_gas + 0.5),
                        other_fuel / (tool_other_fuel + 0.5), total / (tool_total + 0.5)),
    income_k_high = pmin(upper_k(electricity, tool_electricity), upper_k(gas, tool_gas),
                         upper_k(other_fuel, tool_other_fuel), upper_k(total, tool_total)),
    income_k_mid = (income_k_low + income_k_high) / 2,
    income_mid_fits = fits_display(electricity / income_k_mid, tool_electricity) &
      fits_display(gas / income_k_mid, tool_gas) & fits_display(other_fuel / income_k_mid, tool_other_fuel) &
      fits_display(total / income_k_mid, tool_total),
    # Electricity cost times m changes only the electricity burden and the total
    rest = total - electricity,
    others_fit = fits_display(gas, tool_gas) & fits_display(other_fuel, tool_other_fuel),
    electricity_m_low = pmax((tool_electricity - 0.5) / electricity, (tool_total - 0.5 - rest) / electricity),
    electricity_m_high = pmin((tool_electricity + 0.5) / electricity, (tool_total + 0.5 - rest) / electricity),
    electricity_m_mid = (electricity_m_low + electricity_m_high) / 2,
    electricity_mid_fits = others_fit & fits_display(electricity * electricity_m_mid, tool_electricity) &
      fits_display(rest + electricity * electricity_m_mid, tool_total),
    income_range = case_when(
      income_k_low < income_k_high ~ sprintf("%.3f to %.3f", income_k_low, income_k_high),
      TRUE ~ "none"
    ),
    electricity_range = case_when(
      others_fit & electricity_m_low < electricity_m_high ~ sprintf("%.3f to %.3f", electricity_m_low, electricity_m_high),
      TRUE ~ "none"
    )
  )

message("\nMultipliers under which all four values round to the tool's (income: our values / k; ",
        "electricity cost: our electricity x m). 1 means no change:")
multipliers %>%
  select(geoid, band, income_range, income_mid_fits, electricity_range, electricity_mid_fits) %>%
  print(width = Inf)

# Every state burden the tool shows, rounded as a whole and as the sum of nearest-rounded
# fuel burdens. The tool's band panel follows the second; its overall values the first.
state_burdens <- bind_rows(
  shipped_rule(fpl, state) %>% mutate(family = "fpl", band = NA_character_),
  shipped_rule(fpl, state, band) %>% mutate(family = "fpl", band = as.character(band)),
  shipped_rule(ami, state, band) %>% mutate(family = "ami", band = as.character(band))
) %>%
  transmute(
    family, geoid = sprintf("%02.0f", state), band, total = energy_burden,
    rounded_sum = round(100 * coalesce(weighted_electricity_cost, 0) / weighted_income) +
      round(100 * coalesce(weighted_gas_cost, 0) / weighted_income) +
      round(100 * coalesce(weighted_other_fuel_cost, 0) / weighted_income)
  ) %>%
  inner_join(tool_values %>% filter(level == "state", metric == "energy_burden") %>%
               select(family, geoid, band, tool = tool_value), by = c("family", "geoid", "band")) %>%
  mutate(row = case_when(is.na(band) ~ "overall", TRUE ~ "band"),
         total_rounded = round(total) == tool, sum_of_rounded = rounded_sum == tool)

message("\nState burdens: total rounded vs sum of rounded fuel burdens, against the tool:")
state_burdens %>%
  mutate(total = round(total, 3)) %>%
  select(family, geoid, band, total, rounded_sum, tool, total_rounded, sum_of_rounded) %>%
  print(n = Inf, width = Inf)
state_burdens %>%
  group_by(row, family) %>%
  summarize(values = n(), total_rounded = sum(total_rounded), sum_of_rounded = sum(sum_of_rounded)) %>%
  ungroup() %>%
  print()
