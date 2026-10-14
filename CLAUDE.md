# 2026_10_ucs_lead_energy_burden

## Purpose
The Union of Concerned Scientists (UCS) asked for national energy burden data. EEP is sending
nine CSVs built from DOE LEAD 2022, covering the 50 states, DC and Puerto Rico:
- Six from the FPL file: one row per census tract (84,280), per tract × FPL band (421,400), per county
  (3,222), per county × FPL band (16,110), per state (52) and per state × FPL band (260).
- Three from the AMI file: one row per tract × AMI band (505,680), per county × AMI band (19,332) and
  per state × AMI band (312). These are in addition to the FPL band files, not a replacement. There is
  no overall AMI file.
- Negative cost averages are left out of that fuel's average (2026-10-08 methodology audit). Every
  cohort income is kept, as in the DOE LEAD tool. A $1,000 cohort income rule was removed on
  2026-10-14 to align with the tool; see Method notes and `LEAD_TOOL_DISCREPANCIES.md`.

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
  `LEAD_AMI_NATIONAL_FILE`, `LEAD_AMI_ROLLUP_FILE`, `LEAD_RAW_DIR` (raw LEAD `Data_Unzipped`, used
  only by `R/04`) and `OUTPUT_DIR`. It is never committed. `.gitignore` excludes it, and `.git/hooks/pre-commit` rejects
  it even when force-added; the hook is local and must be reinstalled after a fresh clone.
  `.Renviron.example` is the committed template. Keep file paths out of the R code.
- `R/03_check_lead_tool.R` compares the latest shipped CSVs with values read off the DOE LEAD
  interactive tool. It reads the CSVs only, recomputes nothing and writes no files. A new check is a
  row in `tool_values` in `R/lead_tool_values.R` (plus a row in `shipped_files` for a new file).
- `R/04_diagnose_tool_gaps.R` recomputes the tool values for MI and AL under variants that each turn
  off one filter or test one hypothesis about the tool, and scores them. It reads the cohort
  parquets, the FPL rollup, the shipped CSVs and the raw MI and AL LEAD CSVs, writes no files and
  takes about 35 seconds. Its results are written up in `LEAD_TOOL_DISCREPANCIES.md`.
- `outputs/README.md` is the partner-facing data dictionary and ships inside the delivery zip.

## Method notes
- Each average is `weighted.mean(avg_x, x_valid_units, na.rm = TRUE)`, written as
  `sum(x * w) / sum(w)` so arrow can compute it. Every cost is weighted by its own valid-units
  column. `total_households` is `sum(units)`.
- **Weight rule (`add_cohort_weights()`), the same for every table.** A measure's weight is 0 when:
  - its average is `NA` or its valid units are `<= 0`;
  - its cost average is `< 0` (that fuel only).

  Units always stay in `total_households`. `exclude_invalid = FALSE` keeps only the first rule, which is
  the shared rollup's method and is used only for the regression.
  - The negative-cost rule hits 10 FPL rows (`400%+`) and 15,635 AMI rows (`150%+`).
  - Oversized weights (valid units > `units`: 36,706 AMI `150%+` rows, 51 FPL `400%+` rows) are
    kept by decision and documented.
- **$1,000 income rule removed (2026-10-14).**
  - The rule zeroed every measure for cohorts with `avg_income < 1000`: 196,592 FPL rows and 162,218 AMI
    rows.
  - The tool keeps these cohorts. Without the rule, our income matches the tool to the dollar, and tool
    matches rise from 25 to 31 of 46.
  - The 2026-10-14 rebuild against the 08-10-2026 files:
    - Lowest band by state: up 0.15–2.41 points (FPL) and 0.29–3.78 points (AMI).
    - Overall state burden: ≤ 0.017 points.
    - Tracts: 62,425 of the 62,427 tracts with such a cohort change; every other tract and county is
      identical.
    - National lowest band: FPL `0-100%` 18.74% → 19.64%, AMI `0-30%` 15.60% → 16.11%.
  - Extreme tract × band burdens return and ship as computed, with a partner README caveat: 946 FPL and
    490 AMI rows above 100%, 21 and 14 above 1,000%, max 2,878,457% (FPL) and 40,599% (AMI).
  - Groups with income ≤ $0 or a fraction of a cent get NA burden through the `1e-9` floor: 23 FPL and 24
    AMI tract × band rows, 2 tracts.
  - The negative-cost rule still prevents the 53 negative AMI burdens.
- After `ungroup()`, `add_totals()` sets `total_utility_cost` to electricity + gas + other fuel, with a
  missing fuel counted as $0. It is `NA` when no fuel has valid units. `energy_burden = 100 *
  total_utility_cost / weighted_income`, `NA` when income is missing or under the `1e-9` floor.
- **Checks, identical in both scripts.**
  - `check_tables()`: structure, household totals, empty-band and blank-burden counts, and validity
    (no negative cost, total cost or burden).
  - `check_rollups()`: 9 re-weightings across levels and from band to overall, weights included,
    < 1e-9.
  - `check_regression()`: the unfiltered tract table matches the shared rollup exactly (~1e-16),
    except in negative-weight tracts (4 FPL ≤ 0.0013 points; 4,441 AMI ≤ 0.083 points). The filtered
    table matches the unfiltered one in every tract without a negative-cost cohort (84,270 FPL, 77,863
    AMI).

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
  - After the 2026-10-14 rebuild without the $1,000 rule, 31 of 46 match (25 before):
    - state 8 of 18 (MI, AL overall and FPL bands);
    - state × AMI 9 of 12;
    - county 7 of 8 (Wayne 26163, Perry 01105);
    - tract 7 of 8 (Perry 6871 `01105687100`, Wayne 5452 `26163545200`).
  - `LEAD_TOOL_DISCREPANCIES.md` catalogs every filter point and its measured effect, and
    `R/04_diagnose_tool_gaps.R` reproduces it. The 15 misses:
    - **MI household count (1).** The tool's 4,009,261 is the AMI file's; ours comes from the FPL file
      (4,009,253).
    - **Total cost (4).** The tool rounds each fuel cost before adding them, so ours differs by $1.
    - **Band burdens (10), unexplained.** FPL: MI `0-100%`, `100-150%`, `150-200%`; AL `0-100%`,
      `100-150%`, `150-200%`, `400%+`. AMI: MI `30-60%`, AL `0-30%`, `150%+`. They miss by up to 1.5
      points in both directions. No cohort filter, averaging rule or county-file source reproduces them.
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
