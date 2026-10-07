# 2026_10_ucs_lead_energy_burden

## Purpose
The Union of Concerned Scientists (UCS) asked for national energy burden data. EEP is sending
two CSVs built from DOE LEAD 2022: one row per census tract (84,280) and one row per county (3,222),
covering the 50 states, DC and Puerto Rico.

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
- `R/01_build.R` builds both files in `outputs/`. It reads the cohort file through arrow, aggregates
  during the scan and runs `stopifnot()` checks before writing. It takes a few seconds.
- `outputs/README.md` is the partner-facing data dictionary and ships inside the delivery zip.

## Method notes
- Each average is `weighted.mean(avg_x, x_valid_units, na.rm = TRUE)`, written as
  `sum(x * w) / sum(w)` so arrow can compute it. Every cost is weighted by its own valid-units
  column. `total_households` is `sum(units)`.
- After `ungroup()`, `total_utility_cost` is electricity + gas + other fuel, with a missing fuel
  counted as $0. `energy_burden = 100 * total_utility_cost / weighted_income`, and it is `NA` when
  income is under `1e-9`. Both rules match the shared rollup.
- **The regression check is exact except for 4 Alaska tracts.** Those tracts contain 4 cohort rows
  with negative valid-unit weights, which are raw LEAD artifacts. A weighted mean drops these rows;
  the shared rollup's ratio of sums keeps them. The gap is at most 0.0013 percentage points. Every
  other tract matches to 1e-16.
- Counties are built from the cohort rows, not from the tract table. Connecticut appears as its 9
  planning regions (09110–09190).

## Outputs and Delivery
- `outputs/` is gitignored except `README.md`; files there are temporary.
- Deliver with `../eep_data_request_tools/scripts/deliver.sh .` after committing.
  It archives the outputs in `s3://eep-data-requests/2026_10_ucs_lead_energy_burden/` and prints a
  download link that expires in up to 7 days.
- After the partner confirms receipt, run `deliver.sh --clean .` to delete local outputs.
- Record each delivery in the README.md "Deliveries" table.
