# 2026_10_ucs_lead_energy_burden

## Purpose
The Union of Concerned Scientists (UCS) asked for national energy burden data. EEP is sending
nine CSVs built from DOE LEAD 2022, covering the 50 states, DC and Puerto Rico:
- Six from the FPL file: one row per census tract (84,280), per tract × FPL band (421,400), per county
  (3,222), per county × FPL band (16,110), per state (52) and per state × FPL band (260).
- Three from the AMI file: one row per tract × AMI band (505,680), per county × AMI band (19,332) and
  per state × AMI band (312). These are in addition to the FPL band files, not a replacement.

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
  DOE LEAD 2022 FPL file (download 2025-08-06), 20,272,616 rows. The only input to the six FPL-file outputs.
- Cleaned: `../../Cleaned_Data/doe/lead/census_tract-ami-lead-2022-national.parquet`. Cohort-level
  DOE LEAD 2022 AMI file (same download, cleaned 2026-10-08), 24,817,921 rows. The only input to the
  three AMI outputs.
- Cleaned: `../../Cleaned_Data/doe/lead/census_tract-lead-2022-energy-burden.parquet` and
  `census_tract-ami-lead-2022-energy-burden.parquet`. The shared FPL and AMI tract rollups. They are
  read only for the regression checks and do not feed the outputs.

## Key Files
- `R/functions.R` holds the helpers both builds share: `summarize_lead()`, `add_totals()`,
  `complete_bands()`, the GEOID formatters, `reweight_to()`, `check_gap()`, `cohort_audit()`,
  `rollup_regression()` and `write_output()`. Change the method here, once, for both band families.
- `R/01_build.R` builds the six FPL-file outputs. `R/02_build_ami.R` builds the three AMI outputs. Each
  reads its cohort file through arrow, aggregates during the scan and runs `stopifnot()` checks before
  writing. They are independent, and each takes 10–20 seconds.
- `.Renviron` holds every file path the scripts use: `LEAD_NATIONAL_FILE`, `LEAD_ROLLUP_FILE`,
  `LEAD_AMI_NATIONAL_FILE`, `LEAD_AMI_ROLLUP_FILE` and `OUTPUT_DIR`. It is never committed. `.gitignore` excludes it, and `.git/hooks/pre-commit` rejects
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
  tract and county columns plus `fpl` after the GEOID. `complete_bands()` gives every area all five
  bands; missing bands (754 tract rows, 2 county rows, both counts checked) get 0 in the `*_households`
  columns and `NA` values. Connecticut appears as its 9 planning regions
  (09110–09190).
- **AMI files** (`...-energy-burden-ami.csv`) mirror the three FPL band files with `ami` in place of
  `fpl` (LEAD's `ami150` labels, sorted by a factor from `0-30%` to `150%+`). Things that differ from FPL:
  - The AMI file is a separate LEAD run with its own household counts. It holds 127,451,762 households
    against FPL's 126,917,028, and 6,258 tracts differ by > 0.1% (mostly CA, NY, MA, HI and CT). AMI bands
    therefore cannot be checked against the shipped FPL-based overall files. `02_build_ami.R` builds
    overall AMI tract, county and state tables in memory, never written, and re-weights each band table
    up to them (< 1e-9).
  - 7,992 AMI cohort rows have negative valid-unit weights, all in `150%+`, in 4,441 tracts. Units are
    never negative. The regression against the AMI rollup is exact elsewhere (~1e-16). In those tracts
    it is checked loosely (< 1e-3 as a fraction), and the observed max is 0.083 percentage points.
  - Empty bands: 935 tract rows (442 tracts) and 1 county row (48261, `0-30%`), both counts checked.
- Arrow's parallel sums are not order-deterministic, so rebuilds change the county, county × FPL,
  state and state × FPL CSVs in the last digits (observed ≤ 1e-13 relative). Compare rebuilds
  numerically, not byte for byte. The tract and tract × FPL files have been byte-identical. Moving the
  helpers into `R/functions.R` (2026-10-08) left the tract files byte-identical and the others within
  9.4e-14 relative.

## Outputs and Delivery
- `outputs/` is gitignored except `README.md`; files there are temporary.
- Deliver with `../eep_data_request_tools/scripts/deliver.sh .` after committing.
  It archives the outputs in `s3://eep-data-requests/2026_10_ucs_lead_energy_burden/` and prints a
  download link that expires in up to 7 days.
- After the partner confirms receipt, run `deliver.sh --clean .` to delete local outputs.
- Record each delivery in the README.md "Deliveries" table.
