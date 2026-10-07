# 2026_10_ucs_lead_energy_burden

## The request

| | |
|---|---|
| Partner | Union of Concerned Scientists (UCS) |
| Contact | [name, role, email] |
| Received | 2026-10 |
| Due | [yyyy-mm-dd] |
| Ask | National energy burden from DOE LEAD 2022 at the census tract and county levels |

## Data sources

| Dataset | Path | Version / vintage | Notes |
|---|---|---|---|
| DOE LEAD 2022 (cohort level) | `../../Cleaned_Data/doe/lead/census_tract-lead-2022-national.parquet` | 2022 release, downloaded 2025-08-06 | Only input to the outputs |
| DOE LEAD 2022 (tract rollup) | `../../Cleaned_Data/doe/lead/census_tract-lead-2022-energy-burden.parquet` | same | Regression check only |

## Method

The cohort file has one row per tract × poverty band × tenure/year built × building type ×
heating fuel. For each census tract, and separately for each county (the first 5 digits of the
tract GEOID), the build script:

1. Takes the weighted mean of each average, using that measure's own valid-units column as the
   weight:
   - income is weighted by `hincp_valid_units`
   - electricity cost by `elep_valid_units`
   - gas cost by `gasp_valid_units`
   - other fuel cost by `fulp_valid_units`
2. Sums `units` to get `total_households`.
3. After `ungroup()`, computes `total_utility_cost = electricity + gas + other fuel` and
   `energy_burden = 100 * total_utility_cost / weighted_income`.

A fuel with no valid units in a group counts as $0 in the total. Burden is `NA` when weighted income
is below `1e-9`; 17 tiny tracts have a degenerate modeled income of about 1e-10. Both rules match
the shared rollup in `Cleaned_Data/doe/lead/`. The tract output reproduces that rollup to 1e-16,
except in 4 Alaska tracts. Those tracts contain cohort rows with negative weights, which the
weighted mean drops, and they differ by at most 0.0013 percentage points.

## How to rebuild

1. Open `2026_10_ucs_lead_energy_burden.Rproj`, or work from the repo root.
2. Run `R/01_build.R`. It writes both CSVs to `outputs/` and stops if any check fails.

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
