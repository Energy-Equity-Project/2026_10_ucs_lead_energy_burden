# Discrepancies between the shipped files and the DOE LEAD interactive tool

Measured 2026-10-14.

**Update, 2026-10-14: the overall state file is built from the AMI cohort file (B10 resolved).**
- `R/02_build_ami.R` now writes the overall state file; `R/01_build.R` builds its FPL state table as a
  check target only.
- `R/03`: MI households now match (4,009,261). **46 of 46 headline values match under the tool's
  rule** (64 of 64 with the fuel burdens), and 36 of 46 rounded as a whole. MI and AL income, cost and
  burden are unchanged at the tool's precision (MI income +0.00001%, cost −$0.003; AL identical).
- Elsewhere, five states move. Burden changes by CT −0.276 points, CA −0.101, HI −0.013, NY −0.013 and
  MA −0.012, and households by +3.7%, +3.3%, +1.0%, +0.4% and +0.5%. Every other state moves by
  < 0.001 points and < 0.02% of households.
- The state file now equals the sum of the state AMI bands. The state FPL bands and the county file
  no longer sum to it.
- In `R/04`, V0 (shipped) takes its state overall from the AMI file, so V0 and V3 now differ only
  there. The other variants keep the FPL state overall.

**Update, 2026-10-14: the $1,000 income rule (B2) has been removed.** The files were rebuilt and 31 of 46
values now match, with 25 before. The catalog and the scores below record the measurement made
against the earlier 08-10-2026 outputs, which still had the rule. In today's `R/04` output, V0 (shipped)
equals V3 (unfiltered) at all 46 keys, and V1 recomputes the former rule (25 of 46). Line references
are to the code after the removal.

**Update, 2026-10-14: band readings corrected, fuel burdens added, band rounding rule found.**
- **Five band totals were misread (C3):** AL FPL `0-100%`, `100-150%` and `150-200%` (first read as 20, 8
  and 6; the tool shows 21, 9 and 7), MI FPL `0-100%` (23; shows 24) and MI FPL `150-200%` (8; shows 7).
  With the corrected values, 35 of 46 headline values match when our values are rounded as a whole.
- **18 fuel burdens all match.** These are the per-fuel band burdens read off the tool (electricity, gas
  and other fuel for six FPL bands).
- **The tool's band panel builds each burden as a sum of rounded fuel burdens (C4).** Scored that way
  (with total costs built the same way), 45 of 46 headline values match, and 63 of 64 with the fuel
  burdens.
- **One miss remains:** MI's household count, which the tool takes from the AMI file.

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
2. **Band values: 9 to 10 of 22 unexplained, as first measured.** No variant or averaging rule we tried
   reproduces them. *Since resolved:* 5 band totals were misread, and the tool's band
   panel adds rounded fuel burdens. See "Band burdens: the tool totals rounded fuel burdens".
   The record as first measured:
   - The shipped rule misses 9 bands, and the unfiltered method misses 10.
   - Misses go both ways, by up to 1.5 points, and include bands no filter touches (FPL `100-150%`,
     `150-200%`; AMI `30-60%`).
   - Dropping the income rule only trades misses. It fixes MI AMI `0-30%` but breaks MI FPL `0-100%`
     and AL AMI `0-30%`.
3. **Best single method, as first measured:** unfiltered, with fuel costs rounded before summing and the MI
   household count from the AMI file. That gave 36 of 46: all 24 overall values and 12 of 22 bands. With
   the corrected readings and band burdens built from rounded fuel burdens, the shipped files match
   45 of 46. The one miss is MI households.

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
| B10 | `02_build_ami.R` (state), `01_build.R` (tract, county) | The overall tract and county files come from the FPL cohort file; the overall state file from the AMI file since 2026-10-14 | MI: 4,009,253 FPL vs 4,009,261 AMI | MI households match with the AMI file (V9a, V9b, and V0 since the change) | **caused the MI household gap**; the tool's MI count is the AMI run's. **Resolved 2026-10-14** by building the state file from the AMI file |

### Comparison (`R/03_check_lead_tool.R`)
| ID | Where | What it drops or changes | Effect on tool values | Verdict |
|---|---|---|---|---|
| C1 | `:126` | `round()` (half to even); the tool's display rule was unknown | Round half up gives the same results (no ties). `floor()` is worse in every variant (16 vs 25 shipped, 23 vs 31 unfiltered). The tool rounds; it doesn't truncate | not a cause |
| C1b | `:126` | Our `total_utility_cost` is rounded once; the tool rounds each fuel and then adds | 6 of 6 totals match when the fuels are rounded first (unfiltered); 2 of 6 otherwise | **causes the remaining ±$1 cost gaps** |
| C2 | `:95-100` | The latest dated file wins | V0 = shipped to 5.7e-14 | outputs are current |
| C3 | `tool_values` | Values are read by hand at whole-number precision | 5 band totals were misread and corrected on re-checking (2026-10-14): AL FPL `0-100%` 20 → 21, `100-150%` 8 → 9, `150-200%` 6 → 7; MI FPL `0-100%` 23 → 24, `150-200%` 8 → 7 | **caused 4 misses** (AL `100-150%`, AL `150-200%`, MI `0-100%`, MI `150-200%`) |
| C4 | `R/03` (`tool_rule`), `R/04` C4 section | The tool's band panel adds each fuel's burden after rounding it to a whole percent; we round the total once | Built the tool's way, 22 of 22 band burdens match, against 16 of 22 rounded as a whole. Overall burdens are rounded as a whole in the tool (the fuel rule would break 1 of 2 state and 2 of 2 tract overall values) | **causes 6 band misses**: AL FPL `0-100%`, `400%+`; MI FPL `100-150%`; AL AMI `0-30%`, `150%+`; MI AMI `30-60%`. A display artifact, like C1b |

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

## Band burdens: the tool totals rounded fuel burdens
Two things explained the band gaps:
- **Misread totals (C3).** Five band totals were misread.
- **A display rule (C4).** The tool's band panel shows each fuel's burden (cost as a percent of income)
  rounded to a whole percent, and shows the band's burden as the sum of those rounded values. Our files
  hold unrounded burdens, so a band can differ from the tool by up to about 1 point while every fuel
  agrees. This is the same rule as total cost (C1b), where the tool adds rounded fuel costs.

The shipped values are correct and stay unrounded.

### Every state band burden, 14-10-2026 files
"Rounded as a whole" is our burden rounded once. "Sum of rounded fuels" rounds our electricity, gas and
other fuel burdens to whole percents, then adds them.

| Band family | State | Band | Shipped burden | Rounded as a whole | Sum of rounded fuels | Tool |
|---|---|---|---|---|---|---|
| FPL | AL | `0-100%` | 21.523 | 22 | 18 + 3 + 0 = **21** | 21 |
| FPL | AL | `100-150%` | 9.481 | 9 | 8 + 1 + 0 = **9** | 9 |
| FPL | AL | `150-200%` | 6.527 | **7** | 6 + 1 + 0 = **7** | 7 |
| FPL | AL | `200-400%` | 3.953 | 4 | **4** | 4 |
| FPL | AL | `400%+` | 1.695 | 2 | 1 + 0 + 0 = **1** | 1 |
| FPL | MI | `0-100%` | 23.996 | 24 | 13 + 10 + 1 = **24** | 24 |
| FPL | MI | `100-150%` | 10.054 | 10 | 5 + 4 + 0 = **9** | 9 |
| FPL | MI | `150-200%` | 7.205 | 7 | 4 + 3 + 0 = **7** | 7 |
| FPL | MI | `200-400%` | 4.337 | 4 | **4** | 4 |
| FPL | MI | `400%+` | 1.794 | 2 | **2** | 2 |
| AMI | AL | `0-30%` | 22.580 | 23 | 19 + 3 + 0 = **22** | 22 |
| AMI | AL | `30-60%` | 8.168 | 8 | **8** | 8 |
| AMI | AL | `60-80%` | 5.213 | 5 | **5** | 5 |
| AMI | AL | `80-100%` | 4.118 | 4 | **4** | 4 |
| AMI | AL | `100-150%` | 3.067 | 3 | **3** | 3 |
| AMI | AL | `150%+` | 1.584 | 2 | 1 + 0 + 0 = **1** | 1 |
| AMI | MI | `0-30%` | 21.566 | 22 | **22** | 22 |
| AMI | MI | `30-60%` | 7.646 | 8 | 4 + 3 + 0 = **7** | 7 |
| AMI | MI | `60-80%` | 5.117 | 5 | **5** | 5 |
| AMI | MI | `80-100%` | 4.077 | 4 | **4** | 4 |
| AMI | MI | `100-150%` | 2.947 | 3 | **3** | 3 |
| AMI | MI | `150%+` | 1.574 | 2 | **2** | 2 |
| **Matches** | | | | **16 of 22** | **22 of 22** | |

- **The two rules disagree in 6 bands, and the tool follows the sum of rounded fuels in all 6.**
- **The rule applies only to the band panel.** Overall state and tract burdens match when rounded as a
  whole (6 of 6). The fuel rule would give AL state 2 instead of 3, Perry 6871 8 instead of 7, and Wayne
  5452 12 instead of 13.
- **Rounding up or down instead of to the nearest doesn't fit.** For the six bands with tool fuel readings:
  rounded up 0 of 6, rounded down 3 of 6, nearest 6 of 6.

### Fuel burdens read off the tool
| Band | Electric: ours / tool | Gas: ours / tool | Other fuel: ours / tool | Tool total | Tool's fuels added |
|---|---|---|---|---|---|
| MI FPL `0-100%` | 13.232 / 13 | 10.125 / 10 | 0.638 / 1 | 24 | 24 |
| MI FPL `100-150%` | 5.334 / 5 | 4.391 / 4 | 0.329 / 0 | 9 | 9 |
| MI FPL `150-200%` | 3.820 / 4 | 3.150 / 3 | 0.236 / 0 | 7 | 7 |
| AL FPL `0-100%` | 18.237 / 18 | 3.082 / 3 | 0.204 / 0 | 21 | 21 |
| AL FPL `100-150%` | 8.034 / 8 | 1.351 / 1 | 0.097 / 0 | 9 | 9 |
| AL FPL `150-200%` | 5.540 / 6 | 0.927 / 1 | 0.061 / 0 | 7 | 7 |

All 18 fuel burdens match, and in all 6 bands the tool's own fuel burdens add up to its total.

### What remains
Nothing among the 46 headline values. The MI household count (B10) was resolved on 2026-10-14 by
building the overall state file from the AMI file.

Every band burden is explained. The band-income and electricity-cost multipliers in `R/04` (C4 section)
are kept as a check. With the corrected readings, every band's income range includes 1 except MI
`100-150%` (1.058 to 1.183). That band is explained by the display rule above, not by a data
difference.

## Decision
The $1,000 income rule (B2) was a deliberate departure from LEAD, chosen in the 2026-10-08 audit. It was
the main reason our overall values differed from the tool, so it was removed on 2026-10-14.
- The negative-cost rule (B3) stays. It changes none of the 46 values and keeps 53 AMI tract × band
  burdens from going negative.
- The cohorts the rule dropped come back as extreme tract × band burdens, up to about 2.9 million %
  (FPL). They ship as computed, with a caveat in `outputs/README.md`.
- The remaining differences from the tool are display rules or readings, not data. The shipped files
  stay unrounded:
  - 4 total costs are $1 apart, because the tool adds rounded fuel costs (C1b).
  - 6 band burdens differ by up to about 1 point, because the tool adds rounded fuel burdens (C4).
  - The MI household count came from the tool's AMI file (B10). Since 2026-10-14 the overall state file
    is built from the AMI file, so it matches. The overall tract and county files stay FPL-based; the
    checked counties and tracts are identical in both files.
  - Five band totals were misread and have been corrected (C3).
