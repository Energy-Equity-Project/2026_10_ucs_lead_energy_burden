# 2026_10_ucs_lead_energy_burden

## Purpose
The Union of Concerned Scientists (UCS) asked for national energy burden data. EEP is sending
nine CSVs built from DOE LEAD 2022, covering the 50 states, DC and Puerto Rico:
- Six from the FPL file: one row per census tract (84,280), per tract × FPL band (421,400), per county
  (3,222), per county × FPL band (16,110), per state (52) and per state × FPL band (260).
- Three from the AMI file: one row per tract × AMI band (505,680), per county × AMI band (19,332) and
  per state × AMI band (312). These are in addition to the FPL band files, not a replacement. There is
  no overall AMI file.
- Cohorts with average income under $1,000 are left out of every average, and negative cost averages
  are left out of that fuel's average. Both rules came from the 2026-10-08 methodology audit; see
  Method notes.

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
- `R/functions.R` holds everything both builds share: the weight rule (`add_cohort_weights()`,
  `summarize_lead()`, `add_totals()`), the six-table build (`build_tables()`, `complete_bands()`,
  `select_output()`), the checks (`cohort_audit()`, `check_tables()`, `check_rollups()`,
  `check_regression()`), the summaries (`exclusion_summary()`, `print_build_summary()`) and
  `write_output()`. Change the method here, once, for both band families.
- `R/01_build.R` (FPL, writes six files) and `R/02_build_ami.R` (AMI, writes the three band files) have
  the same steps: config and `expected` counts, then `build_tables()`, the four checks, the summaries
  and the writes. Each reads its cohort file through arrow, aggregates during the scan and takes
  about 15–25 seconds.
- `.Renviron` holds every file path the scripts use: `LEAD_NATIONAL_FILE`, `LEAD_ROLLUP_FILE`,
  `LEAD_AMI_NATIONAL_FILE`, `LEAD_AMI_ROLLUP_FILE` and `OUTPUT_DIR`. It is never committed. `.gitignore` excludes it, and `.git/hooks/pre-commit` rejects
  it even when force-added; the hook is local and must be reinstalled after a fresh clone.
  `.Renviron.example` is the committed template. Keep file paths out of the R code.
- `R/03_check_lead_tool.R` compares the latest shipped CSVs with values read off the DOE LEAD
  interactive tool. It reads the CSVs only, recomputes nothing and writes no files. A new check is a
  row in `tool_values` (plus a row in `shipped_files` for a new file).
- `outputs/README.md` is the partner-facing data dictionary and ships inside the delivery zip.

## Method notes
- Each average is `weighted.mean(avg_x, x_valid_units, na.rm = TRUE)`, written as
  `sum(x * w) / sum(w)` so arrow can compute it. Every cost is weighted by its own valid-units
  column. `total_households` is `sum(units)`.
- **Weight rule (`add_cohort_weights()`), the same for every table.** A measure's weight is 0 when:
  - its average is `NA` or its valid units are `<= 0`;
  - its cost average is `< 0` (that fuel only);
  - the cohort's `avg_income < min_cohort_income` ($1,000), which zeroes all four measures.

  Units always stay in `total_households`. `exclude_invalid = FALSE` keeps only the first rule, which is
  the shared rollup's method and is used only for the regression.
  - The income rule hits 196,592 FPL rows (all `0-100%`) and 162,218 AMI rows (160,344 `0-30%`, 1,874
    `150%+`).
  - The negative-cost rule hits 10 FPL rows (`400%+`) and 15,635 AMI rows (`150%+`).
  - Oversized weights (valid units > `units`: 36,706 AMI `150%+` rows, 51 FPL `400%+` rows) are
    kept by decision and documented.
- **Effect (2026-10-08 rebuild vs the unfiltered build).**
  - Middle bands: unchanged in every file (≤ 2e-14).
  - National lowest band: FPL `0-100%` 19.64% → 18.74%, AMI `0-30%` 16.11% → 15.60%.
  - Lowest band by state: lower everywhere, by up to 2.40 points (FPL) and 3.78 points (AMI).
  - Lowest band by county: 804 FPL and 825 AMI counties move by more than 1 point, up to 27 and 35
    points in small rural counties.
  - Overall files: tract changes in 62,432 tracts (≤ 12.4 points), county ≤ 0.25 points, state
    ≤ 0.02 points.
  - All 53 former negative AMI burdens are gone.
- After `ungroup()`, `add_totals()` sets `total_utility_cost` to electricity + gas + other fuel, with a
  missing fuel counted as $0. It is `NA` when no fuel has valid units. `energy_burden = 100 *
  total_utility_cost / weighted_income`, `NA` when income is missing or under the `1e-9` backstop.
- **Checks, identical in both scripts.**
  - `check_tables()`: structure, household totals, empty-band and blank-burden counts, and validity
    (no negative cost or burden, every group income ≥ $1,000).
  - `check_rollups()`: 9 re-weightings across levels and from band to overall, weights included,
    < 1e-9.
  - `check_regression()`: the unfiltered tract table matches the shared rollup exactly (~1e-16),
    except in negative-weight tracts (4 FPL ≤ 0.0013 points; 4,441 AMI ≤ 0.083 points). The filtered
    table matches the unfiltered one in every untouched tract (21,848 FPL, 23,505 AMI).

  Counts per family live in each script's `expected` list.
- `reweight_to()` computes the means before summing the weight columns. `summarize()` otherwise
  reuses the summed columns inside the means, which once produced false failures in the audit.
- The state files have only the averages and `total_households`, plus `state_abbr` and `state_name`
  from `tidycensus::fips_codes`. Band files add `fpl` or `ami` after the GEOID, as a factor in LEAD's
  label order. `complete_bands()` gives every area all bands; empty bands (FPL: 754 tract rows, 2
  county rows; AMI: 935 tract rows, 1 county row `48261` `0-30%`) get 0 in the `*_households` columns
  and `NA` values. Connecticut appears as its 9 planning regions (09110–09190).
- **AMI vs FPL.** The AMI file is a separate LEAD run: 127,451,762 households against 126,917,028.
  6,258 tracts (7.4%) differ by more than 0.1%, mostly CA (51%), NY (29%) and MA (11%), then HI and
  CT. AMI bands don't sum to the shipped FPL-based overall files, and no overall AMI file is written.
  The AMI build makes them in memory as check targets only.
- **Checks against the LEAD interactive tool (`R/03_check_lead_tool.R`).** The tool shows whole
  numbers, so a value matches when ours rounds to it.
  - The tool does not update its FPL band stats when a county or tract is selected, so county and
    tract FPL band values cannot be checked against it. Only overall county and tract values are checked.
  - The tool's tract name drops the code's last two digits: tract 6871 is GEOID `…687100`.
  - As of 2026-10-14, 25 of 46 match: state 7 of 18 (MI, AL overall and FPL bands), state × AMI 9 of
    12, county 5 of 8 (Wayne 26163, Perry 01105), tract 4 of 8 (Perry 6871 `01105687100`, Wayne 5452
    `26163545200`).
  - AMI bands track the tool more closely than FPL bands. The AMI misses are MI `0-30%` (20.97 vs 22)
    and `30-60%` (7.65 vs 7), and AL `150%+` (1.58 vs 1).
    Our income is higher than the tool's in all six areas (+$22 to +$447, up to +1.48% in Wayne 5452),
    and the state FPL band burdens miss by up to 1.5 points, including bands the filters don't touch.
    MI's tool household count (4,009,261) matches the AMI file, not the FPL file. The gaps are not
    explained yet.
- Arrow's parallel sums are not order-deterministic, so rebuilds change the county, county × band,
  state and state × band CSVs in the last digits (observed ≤ 1e-13 relative). Compare rebuilds
  numerically, not byte for byte. Two arrow `summarize()` calls on the same data can also return rows
  in different orders, so always join or filter by key, never by position.

## Outputs and Delivery
- `outputs/` is gitignored except `README.md`; files there are temporary.
- Deliver with `../eep_data_request_tools/scripts/deliver.sh .` after committing.
  It archives the outputs in `s3://eep-data-requests/2026_10_ucs_lead_energy_burden/` and prints a
  download link that expires in up to 7 days.
- After the partner confirms receipt, run `deliver.sh --clean .` to delete local outputs.
- Record each delivery in the README.md "Deliveries" table.
