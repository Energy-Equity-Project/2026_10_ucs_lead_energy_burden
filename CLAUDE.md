# 2026_10_ucs_lead_energy_burden

## Purpose
The Union of Concerned Scientists (UCS) asked for national energy burden data. EEP is sending
six CSVs built from DOE LEAD 2022 (the FPL file, not AMI): one row per census tract (84,280), per
tract × FPL band (421,400), per county (3,222), per county × FPL band (16,110), per state (52) and per
state × FPL band (260), covering the 50 states, DC and Puerto Rico.

## Type
Data request. This repo CONSUMES data from the shared Data/ and Cleaned_Data/ folders
and produces a one-off deliverable for an external partner. It does not collect or
clean new data; that work belongs in `Internal/data-pipelines/eep-pipeline-core/`.

## Status
active

## Partner
- Organization: Union of Concerned Scientists (UCS)
- Contact: [name, role]
- Received: 2026-10
- Due: [yyyy-mm-dd]
- Data restrictions: none (all public data)

## Data Dependencies
- Cleaned: `../../Cleaned_Data/doe/lead/census_tract-lead-2022-national.parquet`. Cohort-level
  DOE LEAD 2022 (download 2025-08-06), 20,272,616 rows. This is the only input to the outputs.
- Cleaned: `../../Cleaned_Data/doe/lead/census_tract-lead-2022-energy-burden.parquet`. The shared
  tract rollup. It is read only for the regression check and does not feed the outputs.

## Key Files
- `R/01_build.R` builds all six files in `outputs/`. It reads the cohort file through arrow, aggregates
  during the scan and runs `stopifnot()` checks before writing. It takes about 10 seconds.
- `.Renviron` holds every file path the script uses: `LEAD_NATIONAL_FILE`, `LEAD_ROLLUP_FILE` and
  `OUTPUT_DIR`. It is never committed. `.gitignore` excludes it, and `.git/hooks/pre-commit` rejects
  it even when force-added; the hook is local and must be reinstalled after a fresh clone.
  `.Renviron.example` is the committed template. Keep file paths out of the R code.
- `outputs/README.md` is the partner-facing data dictionary and ships inside the delivery zip.

## Method notes
- Each average is `weighted.mean(avg_x, x_valid_units, na.rm = TRUE)`, written as
  `sum(x * w) / sum(w)` so arrow can compute it. Every cost is weighted by its own valid-units
  column. `total_households` is `sum(units)`.
- After `ungroup()`, `add_totals()` sets `total_utility_cost` to electricity + gas + other fuel,
  with a missing fuel counted as $0; it is `NA` when no fuel has valid units. `energy_burden = 100 * total_utility_cost /
  weighted_income`, and it is `NA` when income is under `1e-9`. Both rules match the shared rollup.
- Weights are zeroed when the average is `NA` or the weight is `<= 0`. The build stops if `units` or
  any `*_valid_units` column has a missing value. CSVs write missing values as blank cells.
- **The regression check is exact except for 4 Alaska tracts.** Those tracts contain 4 cohort rows
  with negative valid-unit weights, which are raw LEAD artifacts. The build drops these rows on
  purpose; the shared rollup's ratio of sums keeps them. The gap is at most 0.0013 percentage points.
  Every other tract matches to floating-point precision (checked < 1e-9; observed ~1e-16).
- Every table is built from the cohort rows, not from a finer table. As a check, `reweight_to()`
  re-weights county and state × FPL up to states, tract × FPL up to tracts and county × FPL up to
  counties (< 1e-9 relative), using `add_totals()` so the checks apply the output rules. The state
  file has only the averages and `total_households`, without the `*_households` weight columns, and adds
  `state_abbr` and `state_name` from `tidycensus::fips_codes`. The state × FPL file
  (`...-state-energy-burden-fpl.csv`) has the same columns plus `fpl` (LEAD's `fpl150` labels,
  sorted by a factor from `0-100%` to `400%+`). The tract × FPL and county × FPL files have the
  tract and county columns plus `fpl` after the GEOID. `complete_fpl()` gives every area all five
  bands; missing bands (754 tract rows, 2 county rows, both counts checked) get 0 in the `*_households`
  columns and `NA` values. Connecticut appears as its 9 planning regions
  (09110–09190).
- Arrow's parallel sums are not order-deterministic, so rebuilds change the county, county × FPL,
  state and state × FPL CSVs in the last digits (observed ≤ 1e-13 relative). Compare rebuilds
  numerically, not byte for byte. The tract and tract × FPL files have been byte-identical.

## Outputs and Delivery
- `outputs/` is gitignored except `README.md`; files there are temporary.
- Deliver with `../eep_data_request_tools/scripts/deliver.sh .` after committing.
  It archives the outputs in `s3://eep-data-requests/2026_10_ucs_lead_energy_burden/` and prints a
  download link that expires in up to 7 days.
- After the partner confirms receipt, run `deliver.sh --clean .` to delete local outputs.
- Record each delivery in the README.md "Deliveries" table.
