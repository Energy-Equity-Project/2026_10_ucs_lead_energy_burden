# Discrepancies between the shipped files and the DOE LEAD interactive tool

Measured 2026-10-14.

**Update, 2026-10-14: the $1,000 income rule (B2) has been removed.** The files were rebuilt and 31 of 46
values now match, with 25 before. The catalog and the scores below record the measurement made
against the earlier 08-10-2026 outputs, which still had the rule. In today's `R/04` output, V0 (shipped)
equals V3 (unfiltered) at all 46 keys, and V1 recomputes the former rule (25 of 46). Line references
are to the code after the removal.

This file lists every point where data is dropped, zeroed or redefined, from the
raw DOE CSVs to the comparison, and measures each one's effect on the 46 tool values in
`R/03_check_lead_tool.R`.

## How it was measured
- `R/03_check_lead_tool.R` against the 08-10-2026 outputs: **25 of 46 match**.
- `R/04_diagnose_tool_gaps.R` recomputes the 46 values for MI and AL under variants that each turn
  off one rule or test one hypothesis about the tool. It reads the raw LEAD folder from
  `LEAD_RAW_DIR` in `.Renviron`, takes about 35 seconds and writes nothing. Both scripts read the tool
  values from `R/lead_tool_values.R`. Two sanity checks pass before it scores anything:
  - V0 (the shipped rule) equals the shipped CSVs to 5.7e-14, so the 08-10-2026 outputs are current.
  - V3 and V4 equal the shared tract rollup exactly for the two checked tracts.
- DOE's methodology (`lead-methodology_122024.pdf`, §§ 2.1 and 2.3) and `Data Dictionary 2022.xlsx`.
  - Burden is "average annual housing energy costs divided by the average annual household income".
    That is the ratio of averages we use.
  - Income is taken as reported, from −$59,999 up; no exclusion is described.
  - County values come from census blocks, weighted by occupied housing units, separately from the tracts.
  - `* UNITS` (valid units) is "Sum of UNITS without null value" for that measure.

## Findings
1. **Overall values: all 24 explained.** The tool keeps the cohorts we drop under the $1,000 income rule.
   - Unfiltered, our income equals the tool's to the dollar in all six areas. The shipped income is
     +0.05% to +1.48% higher.
   - The tool's total cost is the sum of the three fuel costs, each rounded to the dollar first. With the
     unfiltered data, that reproduces all 6 totals; summing before rounding reproduces only 2.
     - The 4 shipped totals that miss are each $1 off. This is a display artifact: each fuel cost
       matches the tool, and the shipped totals stay unrounded.

     | Area | Tool | Shipped | Shipped fuels, rounded and added |
     |---|---|---|---|
     | MI | 2,687 | 2,687.64 | 1,430 + 1,181 + 76 = 2,687 |
     | AL | 2,419 | 2,419.62 | 2,041 + 358 + 20 = 2,419 |
     | Wayne 26163 | 2,835 | 2,835.67 | 1,639 + 1,181 + 15 = 2,835 |
     | Wayne 5452 `26163545200` | 3,533 | 3,532.04 | 2,028 + 1,486 + 19 = 3,533 |
   - MI's household count (4,009,261) is the AMI file's, in both the tract and county files. The FPL file
     has 4,009,253. AL, Wayne and Perry are identical in all four files.
   - The overall burdens already match (6 of 6).
2. **Band values: 9 to 10 of 22 unexplained.** No variant or averaging rule we tried reproduces them.
   - The shipped rule misses 9 bands, and the unfiltered method misses 10.
   - Misses go both ways, by up to 1.5 points, and include bands no filter touches (FPL `100-150%`,
     `150-200%`; AMI `30-60%`).
   - Dropping the income rule only trades misses. It fixes MI AMI `0-30%` but breaks MI FPL `0-100%`
     and AL AMI `0-30%`.
3. **Best single method:** unfiltered, with fuel costs rounded before summing and the MI household count from
   the AMI file. That gives 36 of 46: all 24 overall values and 12 of 22 bands.

## Catalog

Rows affected are national counts (FPL / AMI) unless noted. "Effect" is the change in matches out of 46
when the item is switched off or tested, measured against the shipped rule's 25.

### Upstream processor (`Internal/data-pipelines/eep-pipeline-core/processors/doe-lead_processor.R`)
| ID | Where | What it drops or changes | Rows affected | Effect on tool values | Verdict |
|---|---|---|---|---|---|
| P1 | `:29-47` | State folders found by name; a missing tract file is skipped with only a console note | none: all 52 states present; MI and AL raw rows = parquet rows | none | not a cause |
| P2 | `:39-42` | Only the "Census Tracts" files are read; the county files are ignored | n/a | Raw county files give the same values as the tract files (V10a = V4 at every state and county key) | not a cause |
| P3 | `:51` | `read_csv()` guesses types, and parsing problems are never checked | MI and AL: 0 parse problems, 0 NA cells, sums equal to ≤ 5e-14 | none | not a cause |
| P4 | `:68-85` | `avg_*` is NA when valid units ≤ 0, so a nonzero numerator in such a row is dropped | rows with a nonzero numerator: income 1 / 4,568, electricity 1 / 4,996, gas 3 / 6,609, other fuel 2 / 4,763 | none in MI or AL (V3 = V4 exactly) | can't test here: the AMI rows are in NY, CA and MA `150%+`, the FPL rows in AK |
| P5 | `:92`, `:116` | CSV round trip (`write_csv` → `read.csv`) before the parquet | — | sums equal to ≤ 5e-14 | not a cause |
| P6 | `:207` | 1e-9 income floor in the shared rollup | 17 tracts | the rollup is only a regression target | not a cause |

### Build (`R/functions.R`, `R/01_build.R`, `R/02_build_ami.R`)
| ID | Where | What it drops or changes | Rows affected | Effect on tool values | Verdict |
|---|---|---|---|---|---|
| B1 | `functions.R:34-52` | Weight 0 when the average is NA or valid units ≤ 0 | negative weights: 4 / 7,992 | none in MI or AL (V3 = V4) | not a cause here |
| B2 | removed 2026-10-14 | **`avg_income < $1,000` zeroed all four measures** | 196,592 / 162,218 | **+6** (31 vs 25). Gains: all 6 incomes, Perry 6871 cost, MI AMI `0-30%`. Losses: MI FPL `0-100%`, AL AMI `0-30%` | **caused every income gap and most of the cost gap**; the tool keeps these cohorts. **Removed** |
| B3 | `functions.R:25-27` | A negative cost average zeroes that fuel | 10 / 15,635 | 0 (V2 = V0 at all 46 keys) | not a cause in MI or AL |
| B4 | not filtered | Valid units > `units` kept by decision | 51 / 36,706 | none: V4, which keeps every row, matches the tool's overall values | consistent with the tool |
| B5 | `functions.R:64-72` | Each measure averages over its own valid units | — | Averaging costs over all `units` keeps the income matches but lowers every cost by about $300 (V6); averaging everything over `units` drops income 5–14% (V7) | our denominators match the tool's |
| B6 | `functions.R:86-92` | A missing fuel counts as $0; all fuels missing → NA | — | no checked area lacks a fuel | can't test here |
| B7 | `functions.R:93-96` | 1e-9 income floor → NA burden | 2 tracts; 23 FPL / 24 AMI tract × band rows (since B2 was removed) | none of the checked areas | not a cause |
| B8 | `functions.R:63` | `total_households = sum(units)`, including zero-weight cohorts | — | 5 of 6 counts match; MI is the B10 issue | consistent with the tool |
| B9 | `functions.R:121-137` | County = first 5 digits of the tract GEOID; CT planning regions | — | the checked county and tract keys all resolve and match | not a cause here |
| B10 | `01_build.R:66` | The overall files come from the FPL cohort file | MI: 4,009,253 FPL vs 4,009,261 AMI | MI households match with the AMI file (V9a, V9b) | **causes the MI household gap**; the tool's MI count is the AMI run's |

### Comparison (`R/03_check_lead_tool.R`)
| ID | Where | What it drops or changes | Effect on tool values | Verdict |
|---|---|---|---|---|
| C1 | `:126` | `round()` (half to even); the tool's display rule was unknown | Round half up gives the same results (no ties). `floor()` is worse in every variant (16 vs 25 shipped, 23 vs 31 unfiltered). The tool rounds; it doesn't truncate | not a cause |
| C1b | `:126` | Our `total_utility_cost` is rounded once; the tool rounds each fuel and then adds | 6 of 6 totals match when the fuels are rounded first (unfiltered); 2 of 6 otherwise | **causes the remaining ±$1 cost gaps** |
| C2 | `:95-100` | The latest dated file wins | V0 = shipped to 5.7e-14 | outputs are current |
| C3 | `tool_values` | Values are read by hand at whole-number precision | — | can't test; a candidate for the band misses |

### Tool-side hypotheses
| ID | Hypothesis | Result | Verdict |
|---|---|---|---|
| T1 | Overall values come from the AMI run | MI households match the AMI file exactly. Income can't tell the two files apart (both match unfiltered) | supported for households |
| T2 | County and state values come from the county files | County files equal the summed tract files in MI and AL | can't tell apart; makes no difference |
| T3 | The UI applies default housing filters | Overall income, cost and households reproduce exactly with no housing filter | ruled out for overall values |
| T4 | Burden is an average of cohort burdens | V8: 16 of 46, overall burdens 2–4× too high | ruled out |
| T4b | Band burden is an average of tract or county band burdens | plain, household-weighted and median averages at tract and county level: at best 12 of 22 bands | ruled out |
| T5 | The tool drops incomes ≤ $0 (not < $1,000) | V5: 24 of 46, incomes still 0.05–0.44% high | ruled out; the tool keeps every income, as the methodology says |
| T6 | Display truncation | see C1 | ruled out |
| T7 | Different data vintage | Income equals ours to the dollar in all six areas | ruled out |

## Variant scores (matches under `round()`)
| Variant | All | State FPL (18) | State AMI (12) | County (8) | Tract (8) |
|---|---|---|---|---|---|
| V0 shipped rule | 25 / 46 | 7 | 9 | 5 | 4 |
| V1 no $1,000 income rule (now the shipped rule) | 31 / 46 | 8 | 9 | 7 | 7 |
| V2 no negative-cost rule | 25 / 46 | 7 | 9 | 5 | 4 |
| V3 unfiltered (`weighted.mean`) | 31 / 46 | 8 | 9 | 7 | 7 |
| V4 ratio of raw sums (shared rollup method) | 31 / 46 | 8 | 9 | 7 | 7 |
| V5 income rule at ≤ $0 | 24 / 46 | 6 | 9 | 5 | 4 |
| V6 costs over all households | 25 / 46 | 9 | 6 | 5 | 5 |
| V7 everything over all households | 25 / 46 | 8 | 10 | 4 | 3 |
| V8 mean of cohort burdens | 16 / 46 | 4 | 7 | 3 | 2 |
| V9a overall from AMI file, shipped rule | 26 / 46 | 8 | 9 | 5 | 4 |
| V9b overall from AMI file, unfiltered | 32 / 46 | 9 | 9 | 7 | 7 |
| V10a county files, ratio of sums | 24 / 38 | 8 | 9 | 7 | — |
| V10b county files, shipped rule | 20 / 38 | 6 | 9 | 5 | — |
| V10c AMI county file overall, ratio | 25 / 38 | 9 | 9 | 7 | — |

V9b misses 4 costs. The unfiltered FPL-file costs, with each fuel rounded before summing (C1b), match
all 6. Combining the two (unfiltered, fuels rounded first, MI households from the AMI file) gives
**36 of 46**: all 24 overall values and 12 of 22 bands. This was not run as a single variant on the AMI-file costs.

## Still unexplained: 10 band burdens (shipped since 2026-10-14)
| Band | Tool | With the $1,000 rule (08-10-2026) | Shipped now, without it |
|---|---|---|---|
| MI FPL `0-100%` | 23 | 23.18 | 24.00 |
| MI FPL `100-150%` | 9 | 10.05 | 10.05 |
| MI FPL `150-200%` | 8 | 7.21 | 7.21 |
| AL FPL `0-100%` | 20 | 20.85 | 21.52 |
| AL FPL `100-150%` | 8 | 9.48 | 9.48 |
| AL FPL `150-200%` | 6 | 6.53 | 6.53 |
| AL FPL `400%+` | 1 | 1.69 | 1.69 |
| MI AMI `30-60%` | 7 | 7.65 | 7.65 |
| AL AMI `0-30%` | 22 | 21.81 | 22.58 |
| AL AMI `150%+` | 1 | 1.58 | 1.58 |

Our unfiltered band values roll up exactly to overall values that match the tool. If the tool's band
panel used the same cohorts and method, it would show our values, so it must use an input or method
we haven't identified. The next step that could settle this
is the tool's own data download for the MI and AL band panels: unrounded values, read off a file
rather than a chart (C3).

## Decision
The $1,000 income rule (B2) was a deliberate departure from LEAD, chosen in the 2026-10-08 audit. It was
the main reason our overall values differed from the tool, so it was removed on 2026-10-14.
- The negative-cost rule (B3) stays. It changes none of the 46 values and keeps 53 AMI tract × band
  burdens from going negative.
- The cohorts the rule dropped come back as extreme tract × band burdens, up to about 2.9 million %
  (FPL). They ship as computed, with a caveat in `outputs/README.md`.
- The remaining misses are:
  - the MI household count (the tool uses the AMI file);
  - 4 costs, $1 apart because the tool rounds each fuel first;
  - the 10 unexplained band burdens above.
