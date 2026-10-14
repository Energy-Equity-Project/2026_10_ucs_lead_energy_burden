# 2026_10_ucs_lead_energy_burden

## Purpose
The Union of Concerned Scientists (UCS) asked for national energy burden data. EEP is sending
nine CSVs built from DOE LEAD 2022, covering the 50 states, DC and Puerto Rico:
- Five from the FPL file: one row per census tract (84,280), per tract × FPL band (421,400), per county
  (3,222), per county × FPL band (16,110) and per state × FPL band (260).
- Four from the AMI file: one row per tract × AMI band (505,680), per county × AMI band (19,332), per
  state × AMI band (312) and per state (52). The overall state file is AMI-based because the LEAD
  tool's state household counts are the AMI run's; the overall tract and county files are FPL-based.
- `METHODOLOGY.md` is the record of the data sources, the calculation and the LEAD tool check. Keep
  it current when the method changes.

## Type
Data request. This repo CONSUMES EEP's shared cleaned data and produces a one-off deliverable for
an external partner. It does not collect or clean new data; that work belongs in
`Internal/data-pipelines/eep-pipeline-core/`.

## Status
active

## Partner
- Organization: Union of Concerned Scientists (UCS)
- Contact: [name, role]
- Received: 2026-10
- Due: [yyyy-mm-dd]
- Data restrictions: none (all public data)

## Data Dependencies
Every file location comes from `.Renviron` (template: `.Renviron.example`). Never write a data
path in code or docs.
- `LEAD_NATIONAL_FILE`: cohort-level DOE LEAD 2022 FPL file (download 2025-08-06), 20,272,616 rows.
  The only input to the five FPL-file outputs.
- `LEAD_AMI_NATIONAL_FILE`: cohort-level DOE LEAD 2022 AMI file (same download, cleaned 2026-10-08),
  24,817,921 rows. The only input to the three AMI band outputs and the overall state file.
- `LEAD_ROLLUP_FILE`, `LEAD_AMI_ROLLUP_FILE`: the shared FPL and AMI tract rollups, read only by the
  regression checks.
- `OUTPUT_DIR`: where the builds write the CSVs and R/03 reads them.

## Key Files
- `R/functions.R` holds everything both builds share: the weight rule (`add_cohort_weights()`,
  `summarize_lead()`, `add_totals()`), the six-table build (`build_tables()`, `complete_bands()`,
  `select_output()`), the checks (`cohort_audit()`, `check_tables()`, `check_rollups()`,
  `check_regression()`), the summaries (`exclusion_summary()`, `print_build_summary()`) and
  `write_output()`. Change the method here, once, for both band families.
- `R/01_build.R` (FPL, writes five files) and `R/02_build_ami.R` (AMI, writes the three band files and
  the overall state file) have the same steps: config and `expected` counts, then `build_tables()`,
  the four checks, the summaries and the writes. Each reads its cohort file through arrow, aggregates
  during the scan and takes about 15–25 seconds.
- `R/03_check_lead_tool.R` is the only check against the DOE LEAD interactive tool. It reads the
  latest shipped CSVs, recomputes nothing and writes no files. A new check is a row in its
  `tool_values` table (plus a row in `shipped_files` for a new file).
- `.Renviron` is never committed. `.gitignore` excludes it, and `.git/hooks/pre-commit` rejects it
  even when force-added; the hook is local and must be reinstalled after a fresh clone.
- `METHODOLOGY.md` documents the method and tool check; `outputs/README.md` is the partner-facing
  data dictionary and ships inside the delivery zip.

## Method notes
Full method, formulas and counts are in `METHODOLOGY.md`. Rules to keep in mind when editing code:
- Each average is `weighted.mean(avg_x, x_valid_units, na.rm = TRUE)`, written as
  `sum(x * w) / sum(w)` so arrow can compute it. Every cost is weighted by its own valid-units
  column. `total_households` is `sum(units)`.
- **Weight rule (`add_cohort_weights()`), the same for every table.** A measure's weight is 0 when
  its average is `NA` or its valid units are `<= 0`, or (that fuel only) its cost average is `< 0`.
  `exclude_invalid = FALSE` drops the negative-cost rule; it is the shared rollup's method and is
  used only for the regression.
- Every cohort income is kept, as in the LEAD tool. A $1,000 cohort income rule was removed on
  2026-10-14; don't reintroduce an income threshold without asking. Oversized weights (valid units >
  `units`) are kept by decision.
- `add_totals()` counts a missing fuel as $0 in `total_utility_cost` (`NA` when no fuel has valid
  units) and sets `energy_burden` to `NA` when income is missing or under the `1e-9` floor.
- Counts the docs cite (empty bands, missing burdens, flagged rows) live in each build script's
  `expected` list; a changed input fails the build.
- `reweight_to()` computes the means before summing the weight columns. `summarize()` otherwise
  reuses the summed columns inside the means, which once produced false failures in the audit.
- The overall state file comes from `R/02` (`tables$state`); `R/01` builds its FPL state table as a
  check target only. The overall tract and county AMI tables are check targets only.
- The tool shows whole numbers and builds total cost and band burdens from rounded fuels (R/03's
  `tool_rule`). These are display rules: never round the shipped files to match.
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
