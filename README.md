# 2026_10_ucs_lead_energy_burden

## The request

| | |
|---|---|
| Partner | Union of Concerned Scientists (UCS) |
| Contact | [name, role, email] |
| Received | 2026-10 |
| Due | [yyyy-mm-dd] |
| Ask | National energy burden from DOE LEAD 2022 at the census tract, county and state levels, each overall and by Federal Poverty Level band, plus the same three levels by Area Median Income band |

## Data sources

| Dataset | Path | Version / vintage | Notes |
|---|---|---|---|
| DOE LEAD 2022 FPL (cohort level) | `../../Cleaned_Data/doe/lead/census_tract-lead-2022-national.parquet` | 2022 release, downloaded 2025-08-06 | Only input to the six FPL-file outputs |
| DOE LEAD 2022 FPL (tract rollup) | `../../Cleaned_Data/doe/lead/census_tract-lead-2022-energy-burden.parquet` | same | Regression check only |
| DOE LEAD 2022 AMI (cohort level) | `../../Cleaned_Data/doe/lead/census_tract-ami-lead-2022-national.parquet` | same download, cleaned 2026-10-08 | Only input to the three AMI outputs |
| DOE LEAD 2022 AMI (tract rollup) | `../../Cleaned_Data/doe/lead/census_tract-ami-lead-2022-energy-burden.parquet` | same | Regression check only |

## Method

The cohort file has one row per tract × poverty band × tenure/year built × building type ×
heating fuel. For each census tract, and separately for each county (the first 5 digits of the
tract GEOID) and each state, overall and by FPL band (`fpl150`), the build script works from the
cohort rows:

1. Takes the weighted mean of each average, using that measure's own valid-units column as the
   weight:
   - income is weighted by `hincp_valid_units`
   - electricity cost by `elep_valid_units`
   - gas cost by `gasp_valid_units`
   - other fuel cost by `fulp_valid_units`
2. Sums `units` to get `total_households`.
3. After `ungroup()`, computes `total_utility_cost = electricity + gas + other fuel` and
   `energy_burden = 100 * total_utility_cost / weighted_income`.

A fuel with no valid units in a group counts as $0 in the total; a group with no valid units for any
fuel gets no total (`NA`). Burden is `NA` when weighted income is below `1e-9`; 17 tiny tracts have a
degenerate modeled income of about 1e-10. Both rules match the shared rollup in
`Cleaned_Data/doe/lead/`. The tract output reproduces that rollup to floating-point precision (the
build checks < 1e-9; the observed gap is ~1e-16), except in 4 Alaska tracts. Those tracts contain
cohort rows with negative weights, which the build drops on purpose, and they differ by at most
0.0013 percentage points. The build stops if any cohort row has a missing household count or weight.
Missing values are written as blank cells.

The state file is not rolled up from the tract or county files. As a check, the build re-weights the
county table and the state × FPL table up to states, the tract × FPL table up to tracts and the
county × FPL table up to counties, and every value must match the directly built table to < 1e-9
relative. The state × FPL file has the state file's columns plus `fpl`, which keeps LEAD's five band
labels in order from lowest to highest income; it has 260 rows (52 states × 5 bands). State names and
abbreviations come from `tidycensus::fips_codes`.

The tract × FPL and county × FPL files have the tract and county files' columns plus `fpl`, placed
after the tract or county GEOID, and are grouped by that GEOID and band. Every area gets all five
bands: a band with no LEAD cohorts in the area (754 tract rows in 358 tracts, 2 county rows) is filled
in with 0 households and `NA` averages, cost and burden. The build checks both counts.

The three AMI files (`R/02_build_ami.R`) apply the same method to LEAD's AMI cohort file, grouped by
`ami150` (six bands, `0-30%` to `150%+`), with `ami` in place of `fpl`. The two scripts share their
helpers through `R/functions.R`. The AMI file is a separate LEAD run with its own household counts.
It holds 127,451,762 households against 126,917,028 in the FPL file, and 6,258 tracts differ by
more than 0.1%, mostly in CA, NY, MA, HI and CT. The AMI bands therefore cannot be checked against
the FPL-based overall files. Instead, the build re-weights each AMI band table up to overall AMI
tables that it builds in memory, and checks the AMI tract totals against the shared AMI rollup.
Those tract totals match exactly, except in 4,441 tracts holding the AMI file's 7,992
negative-weight cohort rows (all in `150%+`), where the gap is at most 0.083 percentage points.
Every area gets all six bands; the empty ones are 935 tract rows and 1 county row.

Arrow sums the cohort rows in parallel, so a rebuild can change the county, county × FPL, state and
state × FPL values in the last digits (observed ≤ 1e-13 relative). The tract and tract × FPL files
have been byte-identical across rebuilds.

## How to rebuild

1. Copy `.Renviron.example` to `.Renviron` and fill in the five paths. Relative paths resolve
   from the repo root. `.Renviron` is gitignored, and a local pre-commit hook blocks it as well.
2. Open `2026_10_ucs_lead_energy_burden.Rproj`, or start R from the repo root, so that R reads
   `.Renviron` at startup. Restart R after editing it.
3. Run `R/01_build.R`, which writes the six FPL-file CSVs, then `R/02_build_ami.R`, which writes the
   three AMI CSVs. Both write to `OUTPUT_DIR`, and each stops if a path is missing or any check fails.

## Deliveries

| Delivery | Sent to | Notes |
|---|---|---|
| [delivered_yyyy-mm-dd] | [name] | first delivery |

Archived at `s3://eep-data-requests/2026_10_ucs_lead_energy_burden/`. Get a new download link with
`../eep_data_request_tools/scripts/deliver.sh --relink 2026_10_ucs_lead_energy_burden/[delivery]`.

## Caveats

- LEAD values are modeled estimates, not metered bills.
- Connecticut counties are the 9 planning regions (09110–09190), not the 8 legacy counties.
- Puerto Rico is included (state FIPS `72`).
- Very small tracts can have extreme burdens. 7 tracts are above 20%, and all of them have fewer
  than 100 households.
