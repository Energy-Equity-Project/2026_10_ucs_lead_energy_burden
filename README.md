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
heating fuel. For each census tract, county (the first 5 digits of the tract GEOID) and state,
overall and by FPL band (`fpl150`), the build works from the cohort rows:

1. Takes the weighted mean of each average, using that measure's own valid-units column as the
   weight:
   - income is weighted by `hincp_valid_units`
   - electricity cost by `elep_valid_units`
   - gas cost by `gasp_valid_units`
   - other fuel cost by `fulp_valid_units`
2. Sums `units` to get `total_households`.
3. After `ungroup()`, computes `total_utility_cost = electricity + gas + other fuel` and
   `energy_burden = 100 * total_utility_cost / weighted_income`.

`add_cohort_weights()` in `R/functions.R` sets one weight rule for every table. A measure's weight is
zero when:
- its average is `NA`, or its valid units are `<= 0`. Negative valid units are a LEAD artifact.
- its cost average is negative. That fuel only; the row still counts for its other measures.

The negative-cost rule removes 10 FPL rows (`400%+`) and 15,635 AMI rows (`150%+`). In the AMI file
these rows gave 53 negative tract × band burdens.

Every cohort income is kept, including near-zero and negative ones, as in the DOE LEAD tool. A $1,000
cohort income rule was used until 2026-10-14. It was removed because the tool keeps those cohorts; see
`LEAD_TOOL_DISCREPANCIES.md`. National lowest-band burdens are FPL `0-100%` 19.64% and AMI `0-30%`
16.11%.

Cohorts whose valid units exceed their `units` (36,706 AMI `150%+` rows, 51 FPL `400%+` rows) are kept.
`outputs/README.md` has the full per-band table, which each build prints through
`exclusion_summary()`.

A fuel with no valid units in a group counts as $0 in the total; a group with no valid units for any
fuel gets no total (`NA`). Burden is `NA` when the group has no valid income, or when its income is
below the `1e-9` floor in `add_totals()` (zero, negative or a fraction of a cent: 23 FPL and 24 AMI
tract × band rows, 2 tracts). The build stops if any cohort row has a missing household
count or weight. Missing values are written as blank cells.

**Checks.** Both scripts run the same checks from `R/functions.R`, and only the `expected` counts
differ:
- `check_tables()`: row counts, unique keys, GEOID widths and nesting, household totals against the
  cohorts, every band present, and empty-band and blank-burden counts. It also checks validity: no
  negative cost, total cost or burden.
- `check_rollups()`: re-weights every finer table up to every coarser one (< 1e-9 relative, weight
  columns included): tract → county → state, each band table → its overall table, and
  tract × band → county × band → state × band.
- `check_regression()`: an unfiltered tract table (`exclude_invalid = FALSE`) must match the shared
  rollup in `Cleaned_Data/doe/lead/` to ~1e-16. The exception is tracts with negative-weight cohorts,
  which the rollup keeps: 4 FPL tracts (≤ 0.0013 percentage points) and 4,441 AMI tracts (≤ 0.083
  points). The filtered tract table must also match the unfiltered one in every tract with no
  negative-cost cohort (84,270 FPL and 77,863 AMI tracts).

The state files are not rolled up from the tract or county files. They carry `state_abbr` and
`state_name` from `tidycensus::fips_codes` and leave out the `*_households` weight columns. Every band
table gets all of its bands. A band with no LEAD cohorts in the area is filled in with 0 households
and `NA` averages, cost and burden: 754 tract rows in 358 tracts and 2 county rows for FPL, and 935
tract rows and 1 county row for AMI.

The three AMI files (`R/02_build_ami.R`) apply the same method to LEAD's AMI cohort file, grouped by
`ami150` (six bands, `0-30%` to `150%+`), with `ami` in place of `fpl`. The AMI file is a separate
LEAD run with its own household counts. It holds 127,451,762 households against 126,917,028 in the
FPL file. 6,258 tracts (7.4%) differ by more than 0.1%, mostly in CA (51% of them), NY (29%) and MA
(11%), then HI and CT. **The shipped overall files are FPL-based, so the AMI bands don't sum to them,
and no overall AMI file is delivered.** The AMI build makes overall AMI tables in memory as check
targets only.

Arrow sums the cohort rows in parallel, so a rebuild can change the county, county × band, state and
state × band values in the last digits (observed ≤ 1e-13 relative). The tract and tract × band files
have been byte-identical across rebuilds.

## How to rebuild

1. Copy `.Renviron.example` to `.Renviron` and fill in the six paths. Relative paths resolve
   from the repo root. `.Renviron` is gitignored, and a local pre-commit hook blocks it as well.
2. Open `2026_10_ucs_lead_energy_burden.Rproj`, or start R from the repo root, so that R reads
   `.Renviron` at startup. Restart R after editing it.
3. Run `R/01_build.R`, which writes the six FPL-file CSVs, then `R/02_build_ami.R`, which writes the
   three AMI CSVs. Both write to `OUTPUT_DIR`, and each stops if a path is missing or any check fails.
4. Optional: `R/03_check_lead_tool.R` compares the shipped CSVs with values read off the DOE LEAD
   interactive tool, and `R/04_diagnose_tool_gaps.R` measures what causes the gaps (see
   `LEAD_TOOL_DISCREPANCIES.md`). Neither writes files.

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
- Lowest-band tract rows can be far above 100%: 945 FPL `0-100%` rows and 490 AMI `0-30%` rows. 21 FPL
  and 14 AMI rows are above 1,000%, up to about 2.9 million % (FPL) and 40,599% (AMI). They come from
  cohorts LEAD models with near-zero or negative income, which are kept as in the LEAD tool.
