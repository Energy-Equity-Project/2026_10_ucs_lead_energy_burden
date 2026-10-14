# Methodology

How EEP built the nine energy burden files for the Union of Concerned Scientists from DOE's
Low-Income Energy Affordability Data (LEAD) 2022, and how the results were checked against DOE's
LEAD interactive tool. The partner-facing data dictionary and caveats are in `outputs/README.md`.

## Data sources

All inputs are DOE LEAD 2022 (OpenEI submission 6219, downloaded 2025-08-06), cleaned by EEP's
shared LEAD processor. The scripts locate every file through variables in `.Renviron`, which is not
committed. `.Renviron.example` lists them.

| Input | `.Renviron` variable | Contents | Used for |
|---|---|---|---|
| LEAD FPL cohort file | `LEAD_NATIONAL_FILE` | 20,272,616 cohort rows, banded by Federal Poverty Level (FPL) | The overall tract and county files and the three FPL band files |
| LEAD AMI cohort file | `LEAD_AMI_NATIONAL_FILE` | 24,817,921 cohort rows, banded by Area Median Income (AMI) | The overall state file and the three AMI band files |
| LEAD FPL tract rollup | `LEAD_ROLLUP_FILE` | EEP's shared tract-level burden table built from the FPL file | Regression check only |
| LEAD AMI tract rollup | `LEAD_AMI_ROLLUP_FILE` | The same, built from the AMI file | Regression check only |
| LEAD tool readings | none (typed into `R/03_check_lead_tool.R`) | 64 values read off DOE's interactive tool | Tool check only |

Outputs are written to `OUTPUT_DIR`.

### What a cohort row is

LEAD does not report individual households. Each row is a **cohort**: a modeled group of households
in one census tract that share an income band, tenure (own or rent), building age, building type and
heating fuel. Each row gives the cohort's household count and the average income and energy costs
of its households.

| Column | Meaning |
|---|---|
| `state` | State FIPS code (stored as a number) |
| `fip` | 11-digit census tract GEOID, 2020 boundaries (stored as a number) |
| `fpl150` / `ami150` | Income band: FPL `0-100%`, `100-150%`, `150-200%`, `200-400%`, `400%+`; AMI `0-30%`, `30-60%`, `60-80%`, `80-100%`, `100-150%`, `150%+` |
| `units` | Households (occupied housing units) in the cohort |
| `avg_income` | Average annual household income (dollars per year) |
| `avg_electricity_cost`, `avg_gas_cost`, `avg_other_fuel_cost` | Average annual cost of electricity, utility gas and other fuels such as fuel oil, propane and wood (dollars per year) |
| `hincp_valid_units` | Households with a valid income value. The name comes from the Census variable `HINCP` |
| `elep_valid_units`, `gasp_valid_units`, `fulp_valid_units` | Households with a valid electricity, gas or other fuel cost (Census `ELEP`, `GASP`, `FULP`) |

DOE publishes each measure as a total (`*_x_units`) and a count of valid households. The upstream
processor turns them into averages, `avg = x_units / valid_units`, and sets the average to missing
when `valid_units` is zero or negative.

### Two LEAD files, two household counts

The FPL and AMI files are separate LEAD model runs, and they estimate slightly different numbers of
households: 127,451,762 in the AMI file against 126,917,028 in the FPL file (0.4% more). 6,258 tracts
(7.4%) differ by more than 0.1%, mostly in California, New York and Massachusetts, then Hawaii and
Connecticut.

| Output file | Built from |
|---|---|
| Tract, county (overall) | FPL file |
| Tract × FPL, county × FPL, state × FPL | FPL file |
| State (overall) | AMI file |
| Tract × AMI, county × AMI, state × AMI | AMI file |

The overall state file comes from the AMI file because DOE's tool shows the AMI run's state household
counts (Michigan: 4,009,261, against 4,009,253 in the FPL file). Using it changes the state burden by
−0.276 points in Connecticut, −0.101 in California and about −0.013 in Hawaii, New York and
Massachusetts. Every other state changes by less than 0.001 points. As a result, the state file
equals the sum of the state AMI bands, but not exactly the sum of the state FPL bands or of the
counties. Each build script also makes the tables it does not write, and uses them in its checks.

## Calculating Energy Burden

Every table is built the same way, straight from the cohort rows. A **group** is the set of
cohorts in one area (a tract, county or state), or in one area and income band. The county is the
first five digits of the tract GEOID; Connecticut appears as its nine planning regions
(`09110`–`09190`).

### Step 1: weights

Each cohort *i* gets a separate weight for each measure *m* (income, electricity, gas, other fuel):

$$
w_{i,m} =
\begin{cases}
v_{i,m} & \text{if } \bar{x}_{i,m} \text{ is not missing, } v_{i,m} > 0 \text{, and (for a cost) } \bar{x}_{i,m} \ge 0 \\
0 & \text{otherwise}
\end{cases}
$$

| Symbol | Meaning | Column |
|---|---|---|
| $v_{i,m}$ | Households in cohort *i* with a valid value for measure *m* | `hincp_valid_units`, `elep_valid_units`, `gasp_valid_units`, `fulp_valid_units` |
| $\bar{x}_{i,m}$ | Cohort *i*'s average for measure *m* | `avg_income`, `avg_electricity_cost`, `avg_gas_cost`, `avg_other_fuel_cost` |

A cohort left out of one measure still counts toward the others.

### Step 2: weighted averages

For each group *g*:

$$
\bar{x}_{g,m} = \frac{\sum_{i \in g} w_{i,m}\,\bar{x}_{i,m}}{\sum_{i \in g} w_{i,m}}
$$

This gives `weighted_income` ($\bar{y}_g$), `weighted_electricity_cost`, `weighted_gas_cost` and
`weighted_other_fuel_cost`. The denominators are written out as `income_households`,
`electric_households`, `gas_households` and `other_fuel_households`. A group whose weights are all
zero gets a missing average.

### Step 3: households

$$
H_g = \sum_{i \in g} \text{units}_i
$$

`total_households` counts every cohort, including those with zero weight for some measure.

### Step 4: total cost and energy burden

$$
C_g = \bar{c}^{\,\text{elec}}_g + \bar{c}^{\,\text{gas}}_g + \bar{c}^{\,\text{other}}_g
\qquad\qquad
EB_g = 100 \times \frac{C_g}{\bar{y}_g}
$$

| Symbol | Meaning | Column |
|---|---|---|
| $\bar{c}^{\,f}_g$ | Group's average cost of fuel *f* from Step 2 | `weighted_electricity_cost`, `weighted_gas_cost`, `weighted_other_fuel_cost` |
| $C_g$ | Total annual energy cost | `total_utility_cost` |
| $\bar{y}_g$ | Group's average income from Step 2 | `weighted_income` |
| $EB_g$ | Energy burden, percent of income (3.2 = 3.2%) | `energy_burden` |

- A fuel with no valid data in the group adds nothing to $C_g$. If no fuel has valid data, $C_g$ is missing.
- $EB_g$ is missing when $\bar{y}_g$ is missing or below $10^{-9}$ (zero, negative or a fraction of a
  cent), since dividing by it would give a meaningless or negative burden.

Energy burden is a **ratio of averages**: the group's average energy cost divided by its average
income, as in DOE's tool. It is not the average of each household's burden, which would be higher,
because the households with the lowest incomes carry the highest burdens.

### Data quality rules

LEAD's modeled cohorts include some implausible rows, almost all in the top AMI band (`150%+`).

| Issue | FPL rows | AMI rows | Handling |
|---|---|---|---|
| Valid household count is negative | 4 | 7,992 | Weight set to 0 (Step 1) |
| Average cost is negative | 10 (`400%+`) | 15,635 (`150%+`) | Weight set to 0 for that fuel only. Without this, 53 AMI tract × band burdens would be negative |
| Valid household count exceeds `units` | 51 (`400%+`) | 36,706 (`150%+`) | Kept as published. Leaving them out moves state `150%+` burdens by at most 0.04 points |
| Near-zero or negative average income | 196,592 cohorts under \$1,000 | 162,218 cohorts under \$1,000 | Kept, as in DOE's tool |

Until 2026-10-14 the build also left out cohorts with average income under \$1,000. That rule was
removed because DOE's tool keeps those cohorts; without it, our incomes match the tool to the dollar.
Keeping them produces some extreme small-area burdens, which ship as computed:

- 946 FPL tract × band rows (945 of them in `0-100%`) and 490 AMI rows (all in `0-30%`) are above 100%.
- 21 FPL and 14 AMI rows are above 1,000%, up to 2,878,457% (FPL) and 40,599% (AMI).

### Empty bands and missing burdens

Every area gets every band. A band with no LEAD cohorts in the area is filled in with 0 households and
missing averages: 754 tract rows and 2 county rows for FPL, 935 tract rows and 1 county row for AMI.

`energy_burden` is missing in 17 tracts, in 866 FPL tract × band rows and in 1,055 AMI tract × band
rows: the empty bands, plus groups with no valid income, groups whose income is under the $10^{-9}$
floor (23 FPL and 24 AMI rows) and groups with no valid fuel data. Every county and state has a value.

### Build checks

`R/01_build.R` and `R/02_build_ami.R` run the same checks from `R/functions.R`, and stop before
writing if any fails.

**`check_tables()`**: row counts, unique keys, GEOID widths and nesting, household totals equal to the
cohort total, every band present, the empty-band and missing-burden counts above, and no negative
cost, total cost or burden.

**`check_rollups()`**: every table is built independently from the cohorts, so each finer table
re-weighted up to a coarser one must reproduce it. For a coarser group $G$ made of finer groups $g$:

$$
\bar{x}_{G,m} = \frac{\sum_{g \in G} W_{g,m}\,\bar{x}_{g,m}}{\sum_{g \in G} W_{g,m}},
\qquad W_{g,m} = \sum_{i \in g} w_{i,m}
$$

This is checked to a relative gap under $10^{-9}$ for 9 pairs: tract → county → state, each band
table → its overall table, and tract × band → county × band → state × band.

**`check_regression()`**: the tract table rebuilt without the negative-cost rule must match EEP's
shared tract rollup to about $10^{-16}$. The exception is tracts with negative valid counts, which
the rollup keeps: 4 FPL tracts (within 0.0013 points) and 4,441 AMI tracts (within 0.083 points). The
shipped tract table must also equal the unfiltered one in every tract without a negative-cost
cohort.

Arrow adds the cohort rows in parallel, so a rebuild can change county and state values in the last
digits (relative changes of about $10^{-13}$ or less). Compare rebuilds numerically, not byte for byte.

## Checking against DOE LEAD interactive tool

`R/03_check_lead_tool.R` compares the latest files in `OUTPUT_DIR` with 64 values read by hand off DOE's
LEAD interactive tool. It recomputes nothing and writes no files.

### What was checked

| Area | Values |
|---|---|
| Michigan (`26`), Alabama (`01`) | Overall burden, total cost, households and income; burden for each FPL and AMI band |
| Wayne County, MI (`26163`); Perry County, AL (`01105`) | Overall burden, total cost, households and income |
| Wayne tract 5452 (`26163545200`); Perry tract 6871 (`01105687100`) | Overall burden, total cost, households and income |
| Michigan and Alabama, FPL `0-100%`, `100-150%`, `150-200%` | Electricity, gas and other fuel burden |

That is 46 headline values and 18 fuel burdens. The tool names a tract by its code without the last two
digits (tract 6871 is GEOID `01105687100`). The tool's FPL band panel does not change when a county or
tract is selected, so county and tract band values cannot be checked against it.

### How a match is scored

The tool shows whole numbers, so a value matches when ours rounds to the tool's number. The tool
builds two kinds of value from rounded parts, and R/03 also scores each of those the way the tool
builds it:

$$
\text{tool total cost} = \sum_{f} \text{round}\left(\bar{c}^{\,f}_g\right)
\qquad\qquad
\text{tool band burden} = \sum_{f} \text{round}\left(100 \times \frac{\bar{c}^{\,f}_g}{\bar{y}_g}\right)
$$

where *f* runs over electricity, gas and other fuel. Overall (unbanded) burdens are rounded once, as
a whole; building them from rounded fuel burdens breaks three of them.

### Results

| Scoring | Headline values | Fuel burdens |
|---|---|---|
| Our value rounded as a whole | 36 of 46 | 18 of 18 |
| Built as the tool builds it | **46 of 46** | **18 of 18** |

All 10 differences under whole-value rounding are display rules, not data differences.

**Total cost (4 values, \$1 each).** Each fuel cost matches the tool. Adding our fuel costs after
rounding them reproduces the tool's total.

| Area | Tool | Ours | Our fuels, rounded and added |
|---|---|---|---|
| Michigan | 2,687 | 2,687.64 | 1,430 + 1,181 + 76 = 2,687 |
| Alabama | 2,419 | 2,419.62 | 2,041 + 358 + 20 = 2,419 |
| Wayne County | 2,835 | 2,835.67 | 1,639 + 1,181 + 15 = 2,835 |
| Wayne tract 5452 | 3,533 | 3,532.04 | 2,028 + 1,486 + 19 = 3,533 |

**Band burdens (6 values, up to about 1 point).** The tool's band panel adds fuel burdens after
rounding each one, so a band can differ by up to a point while every fuel agrees.

| Band | Ours | Rounded | Our fuel burdens, rounded and added | Tool |
|---|---|---|---|---|
| AL FPL `0-100%` | 21.523 | 22 | 18 + 3 + 0 = 21 | 21 |
| AL FPL `400%+` | 1.695 | 2 | 1 + 0 + 0 = 1 | 1 |
| MI FPL `100-150%` | 10.054 | 10 | 5 + 4 + 0 = 9 | 9 |
| AL AMI `0-30%` | 22.580 | 23 | 19 + 3 + 0 = 22 | 22 |
| AL AMI `150%+` | 1.584 | 2 | 1 + 0 + 0 = 1 | 1 |
| MI AMI `30-60%` | 7.646 | 8 | 4 + 3 + 0 = 7 | 7 |

The shipped files keep the unrounded values.

### What the comparison changed

- **The \$1,000 income rule was removed** (2026-10-14). It was the main source of the gaps in income
  and cost.
- **The overall state file was moved to the AMI file** (2026-10-14), so Michigan's household count
  matches the tool.
- **Five band readings were corrected** on re-checking the tool (2026-10-14): AL FPL `0-100%` 20 → 21,
  `100-150%` 8 → 9, `150-200%` 6 → 7; MI FPL `0-100%` 23 → 24, `150-200%` 8 → 7.
- **The negative-cost rule was kept.** It changes none of the 64 values and prevents negative
  burdens.

During the diagnosis, alternatives to the shipped method were also tested on Michigan and Alabama:
other income cutoffs, averaging over all households instead of valid ones, averaging cohort burdens,
averaging tract or county burdens, and DOE's county-level files. None matched the tool better than the
shipped method.

To re-run the check, run `Rscript R/03_check_lead_tool.R` from the repo root. To add a check, add a
row to its `tool_values` table, and a row to `shipped_files` for a new file.
