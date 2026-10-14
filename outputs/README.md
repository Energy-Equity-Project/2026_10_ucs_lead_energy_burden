# Energy burden by census tract, county and state, overall, by poverty level and by area median income, DOE LEAD 2022

Prepared by the Energy Equity Project (EEP) for the Union of Concerned Scientists, October 14, 2026.

## Contents

| File | Description |
|---|---|
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden.csv` | One row per census tract, 84,280 rows |
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-fpl.csv` | One row per census tract and Federal Poverty Level band, 421,400 rows (84,280 tracts × 5 bands) |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden.csv` | One row per county or county equivalent, 3,222 rows |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden-fpl.csv` | One row per county and Federal Poverty Level band, 16,110 rows (3,222 counties × 5 bands) |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden.csv` | One row per state, 52 rows, from DOE's area median income data |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden-fpl.csv` | One row per state and Federal Poverty Level band, 260 rows (52 states × 5 bands) |
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-ami.csv` | One row per census tract and Area Median Income band, 505,680 rows (84,280 tracts × 6 bands) |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden-ami.csv` | One row per county and Area Median Income band, 19,332 rows (3,222 counties × 6 bands) |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden-ami.csv` | One row per state and Area Median Income band, 312 rows (52 states × 6 bands) |

All nine files cover the 50 states, the District of Columbia and Puerto Rico. Each date prefix is
the day the file was built.

The overall state file comes from DOE's area median income data, the data behind DOE's LEAD Tool's
state household counts, so it is the total of the state area median income bands. The overall tract
and county files come from DOE's poverty level data, so they are the totals of the tract and county
poverty level bands. In five states the two DOE files differ by more than 0.1% of households, so
there the state file is not the total of the state poverty level bands or of the state's counties.
See "AMI files come from a separate DOE LEAD file" below.

## Data dictionary

The tract and county files share the same columns, and the tract file adds `tract_geoid`. The tract
and poverty level file has the tract file's columns, with `fpl` after `tract_geoid`; the county and
poverty level file has the county file's columns, with `fpl` after `county_geoid`. The state
file has `state_fips`, `state_abbr`, `state_name`, `total_households` and the six dollar and burden
columns, from `weighted_income` to `energy_burden`. It does not have the geography codes below the
state level or the four `*_households` weight columns. The state and poverty level file has the
state file's columns, with `fpl` after `state_name`. The three area median income files match the
three poverty level files, with `ami` in place of `fpl`.

| Column | Type | Description | Units |
|---|---|---|---|
| `state_fips` | text | 2-digit state FIPS code | — |
| `state_abbr` | text | 2-letter postal abbreviation (state files only) | — |
| `state_name` | text | State name (state files only) | — |
| `fpl` | text | Household income as a share of the federal poverty guideline, in DOE LEAD's five bands: `0-100%`, `100-150%`, `150-200%`, `200-400%`, `400%+` (poverty level files only) | — |
| `ami` | text | Household income as a share of the area median income (AMI), in DOE LEAD's six bands: `0-30%`, `30-60%`, `60-80%`, `80-100%`, `100-150%`, `150%+` (area median income files only) | — |
| `county_geoid` | text | 5-digit county FIPS code (state + county; tract and county files) | — |
| `tract_geoid` | text | 11-digit census tract GEOID (tract files only) | — |
| `total_households` | decimal | Estimated total households (housing units) | households |
| `income_households` | decimal | Households with valid income data, used as the weight for `weighted_income` | households |
| `electric_households` | decimal | Households with valid electricity cost data, used as the weight for `weighted_electricity_cost` | households |
| `gas_households` | decimal | Households with valid gas cost data, used as the weight for `weighted_gas_cost` | households |
| `other_fuel_households` | decimal | Households with valid other-fuel cost data, used as the weight for `weighted_other_fuel_cost` | households |
| `weighted_income` | decimal | Average annual household income | $ per year |
| `weighted_electricity_cost` | decimal | Average annual electricity cost per household | $ per year |
| `weighted_gas_cost` | decimal | Average annual utility gas cost per household | $ per year |
| `weighted_other_fuel_cost` | decimal | Average annual cost of other fuels (fuel oil, propane, wood, etc.) per household | $ per year |
| `total_utility_cost` | decimal | Electricity + gas + other fuel cost | $ per year |
| `energy_burden` | decimal | `100 × total_utility_cost / weighted_income` | percent (3.2 = 3.2%) |

**Keep the GEOID columns as text.** A spreadsheet that reads them as numbers drops the leading
zeros, so Alabama tract `01001020100` becomes `1001020100`. In R, use
`read.csv(..., colClasses = c(state_fips = "character", county_geoid = "character", tract_geoid = "character"))`.

Missing values are blank cells. `read.csv()` reads blank numeric cells as `NA`.

## Sources

- U.S. Department of Energy, Low-Income Energy Affordability Data (LEAD) Tool, 2022 release.
  Census tract data by Federal Poverty Level band, https://data.openei.org/submissions/6219
  (downloaded 2025-08-06).
- U.S. Department of Energy, Low-Income Energy Affordability Data (LEAD) Tool, 2022 release.
  Census tract data by Area Median Income band, same source and download date. Used for the three
  area median income files and the overall state file.

## Methods and caveats

- **How the averages are built.** DOE LEAD reports modeled estimates for groups of households
  within each census tract. The groups are defined by poverty level (area median income band in
  the AMI files), tenure, building age, building type and heating fuel. Within each tract, county or state:
  - Income and each fuel cost are averaged across these groups, weighted by the number of
    households with valid data for that measure.
  - Every group's income is kept, including the near-zero and negative incomes DOE models for some
    groups, as in DOE's LEAD Tool. The one exclusion is for a single fuel: a group whose average cost
    for that fuel is negative is left out of that fuel's average. See "Household groups left out of
    the averages" below.
  - Total utility cost is the sum of the three fuel costs.
  - Energy burden is total utility cost divided by income.
- **Energy burden is an area-level ratio.** It divides average energy cost by average income, as
  in DOE's LEAD Tool. It is not the average of individual household burdens, which would generally
  be higher because low-income households carry the highest burdens.
- **Comparing with DOE's interactive LEAD Tool.** EEP checked the overall values for Michigan,
  Alabama, two counties and two tracts against the tool. Income, household counts and burden match the
  tool at its display precision. Total cost differs by at most $1, because the tool rounds each fuel
  before adding them. The tool's poverty level and AMI band burdens are built the same way: it rounds
  each fuel's burden to a whole percent and shows their sum. A band can therefore differ from these
  files by up to about 1 point while its electricity, gas and other fuel burdens all agree. Built that
  way, all 22 state band burdens EEP checked match. The tool's poverty level breakdown does not change
  when a county is selected, so it cannot be used to check the county (or tract) poverty level
  files.
- **State values come from the household groups, not from the tract or county files.** Each state
  average is computed from all LEAD household groups in the state, in the same way as the tract and
  county averages. A state's burden is therefore not the average of its tract or county burdens. The
  overall state file uses the household groups in DOE's area median income file; the state poverty
  level file uses those in the poverty level file.
- **Poverty level values use the same method within each band.** Each state and poverty level row
  is computed from only that band's household groups in the state. Its burden is the band's average
  energy cost divided by its average income. The five band burdens do not average to the state
  burden. The overall state value combines the area median income bands' costs and incomes, weighted
  by the households with valid data for each measure.
- **Tract and county poverty level values work the same way.** Each tract or county and poverty
  level row is computed from only that band's household groups in the area, so the five band
  burdens do not average to the tract or county burden.
- **Every area has all five poverty levels.** In 358 tracts and 2 counties, LEAD has no households
  in one or more bands. Those rows are still included, with 0 in `total_households` and the four
  `*_households` columns and blank averages, costs and burden. There are 754 such tract rows and 2
  county rows; both county rows are in the `0-100%` band.
- **Poverty level rows are small, and some have extreme burdens.** Splitting an area by band leaves
  few households in many rows: 4,486 tract and poverty level rows have fewer than 10 households.
  Burdens in the `0-100%` band are high by nature (42,013 tract rows in that band are above 20%), and
  some rows are extreme:
  - 945 tract rows in that band are above 100%, plus 1 in the `150-200%` band.
  - 21 tract rows are above 1,000%, up to about 2.9 million percent.

  These rows come from household groups whose modeled average income is near zero or negative. The
  Census data behind LEAD records business and investment losses as negative income. The values are
  kept as DOE's data gives them, and every row above 1,000% has 166 households or fewer. Consider
  filtering or flagging on `total_households` and `weighted_income` when mapping.
- **Area median income values use the same method.** Each area and AMI band row is computed from
  only that band's household groups in the area. The six band burdens do not average to the area's
  overall burden.
- **AMI files come from a separate DOE LEAD file, and their household counts do not match the
  other files exactly.** DOE publishes the AMI and poverty level data as separate files, and in
  some areas they estimate different numbers of households. Nationally, the AMI bands total
  127,451,762 households, against 126,917,028 in the poverty level files and the overall tract and
  county files (0.4% more).
  The gap is concentrated in California, New York, Massachusetts, Hawaii and Connecticut:
  - 6,258 tracts (7.4%) differ by more than 0.1%, by up to 93%.
  - 29 counties differ by more than 0.1%.
  - Five states differ by more than 0.1%, led by Connecticut (3.7%) and California (3.3%).

  Summing a tract's or county's AMI bands therefore does not always reproduce the
  `total_households` in the overall tract or county files. **The overall tract and county files are
  poverty level totals; the overall state file is the AMI total.** It is built from the AMI file
  because DOE's LEAD Tool shows the AMI file's state household counts (Michigan: 4,009,261 against
  4,009,253 in the poverty level file). Compared with a state file built from the poverty level
  data, it changes Connecticut's burden by −0.28 points, California's by −0.10 and Hawaii's, New
  York's and Massachusetts' by about −0.01; every other state changes by less than 0.001 points.
  As a result, the state poverty level bands and the county file sum to the state file's households
  only to within 0.02% in 47 states, and differ by 0.4% to 3.7% in those five. Do not combine the AMI files with the poverty level files in a single calculation.
  There are no overall tract or county AMI files.
- **DOE's `150%+` AMI records have modeling artifacts.** The DOE AMI file has three kinds of
  implausible household group, almost all in the `150%+` band:
  - 7,992 groups in 4,441 tracts (mostly in New York, California and Massachusetts) have a negative
    count of households with valid data. They carry no usable average and are left out.
  - 15,635 groups have a negative average electricity, gas or other fuel cost. That cost is left out,
    and the group's other measures still count. Before this rule, 53 tract rows in the band had a
    negative energy burden.
  - 36,706 groups report more households with valid data than households, up to 929 times as many.
    They are kept as DOE published them; leaving them out changes state `150%+` burdens by at most
    0.04 percentage points.

  Household totals are unaffected. The poverty level file has the same artifacts on a much smaller
  scale: 4 negative counts, 10 negative costs and 51 inflated counts, all in `400%+`.
- **Every area has all six AMI bands.** In 442 tracts and 1 county, LEAD has no households in one or
  more AMI bands. Those rows are included, with 0 in the five `*_households` columns and blank
  averages, costs and burden. There are 935 such tract rows. The county row is Kenedy County, Texas
  (`48261`), in the `0-30%` band.
- **AMI rows are small too.** 3,306 tract and AMI rows have fewer than 10 households. Burdens in the
  `0-30%` band are high by nature (34,124 tract rows in that band are above 20%). 490 tract rows in
  that band are above 100%, and 14 tract rows are above 1,000%, up to 40,599%. These extremes have the
  same cause as in the poverty level files.
- **Missing fuels count as $0.** If no households in an area have valid data for a fuel, that
  fuel's cost column is blank, and it adds $0 to `total_utility_cost`. If no fuel has valid data,
  `total_utility_cost` is blank too.
- **Blank burdens.** `energy_burden` is blank where there is no usable income to divide by. That
  covers 17 small census tracts (40 households or fewer): 15 with no valid income data and 2 whose
  average income is a fraction of a cent. All counties have a value.
  - In the poverty level files, it is blank for 866 tract rows:
    - the 754 rows with no households;
    - 88 rows with no valid income data;
    - 23 rows whose average income is zero, negative or a fraction of a cent;
    - 1 row with no valid fuel data.

    It is also blank for the 2 county rows with no households.
  - In the area median income files, it is blank for 1,055 tract rows:
    - the 935 rows with no households;
    - 93 rows with no valid income data;
    - 24 rows whose average income is zero, negative or a fraction of a cent;
    - 3 rows with no valid fuel data.

    It is also blank for the 1 county row with no households.
- **Small areas.** A few tracts with very few households have extreme burdens. 7 tracts are above
  20%, and all of them have fewer than 100 households. Consider filtering or flagging on
  `total_households` when mapping.
- **Geography.** Tracts use 2020 census boundaries. Connecticut is reported by its 9 planning
  regions (`09110`–`09190`), which the Census Bureau now uses as county equivalents, not by its 8
  legacy counties.
- **Modeled data.** LEAD values are estimates DOE derived from Census survey data. They are not
  utility billing records, and they cover every household regardless of utility.
- **Household counts are decimals.** DOE's modeled household counts are fractional, so the totals
  are not whole numbers.

## Household groups left out of the averages

One rule applies in the same way to every file, area and band:

- **Negative fuel cost.** A household group with a negative average cost for a fuel is left out of
  that fuel's average only. Its income and other fuel costs still count.

Every household group's income is kept, including near-zero and negative incomes, as in DOE's LEAD
Tool. The households in excluded groups still count in `total_households`, but not in that fuel's
`*_households` weight column.

In the tables below:
- "Fuel weight left out" is the share of a fuel's households with valid data that the rule removes.
- "No valid data" is the share of all households that DOE reports without a valid value for income,
  electricity, gas or other fuel.

Both shares are national.

**Poverty level bands**

| Band | Groups with a negative cost | Fuel weight left out | No valid data: income / electricity / gas / other fuel | National burden |
|---|---|---|---|---|
| `0-100%` | 0 | 0% | 14% / 19% / 23% / 15% | 19.64% |
| `100-150%` | 0 | 0% | 12% / 16% / 19% / 13% | 8.34% |
| `150-200%` | 0 | 0% | 10% / 13% / 16% / 11% | 6.05% |
| `200-400%` | 0 | 0% | 7% / 9% / 12% / 8% | 3.73% |
| `400%+` | 10 | < 0.01% | 4% / 5% / 8% / 5% | 1.55% |
| All households | 10 | < 0.01% | 7% / 9% / 12% / 8% | 2.30% |

**Area median income bands**

| Band | Groups with a negative cost | Fuel weight left out | No valid data: income / electricity / gas / other fuel | National burden |
|---|---|---|---|---|
| `0-30%` | 0 | 0% | 14% / 19% / 24% / 16% | 16.11% |
| `30-60%` | 0 | 0% | 10% / 13% / 17% / 11% | 6.05% |
| `60-80%` | 0 | 0% | 8% / 9% / 13% / 8% | 4.09% |
| `80-100%` | 0 | 0% | 7% / 8% / 11% / 7% | 3.14% |
| `100-150%` | 0 | 0% | 5% / 6% / 9% / 6% | 2.07% |
| `150%+` | 15,635 | 0.02–0.11% | 4% / 4% / 6% / 4% | 1.36% |
| All households | 15,635 | < 0.04% | 7% / 9% / 12% / 8% | 2.27% |

**What the rule changes**

- **Poverty level files.** The 10 groups are in `400%+`. They change one state's `400%+` burden by
  less than 0.001 points.
- **AMI files.** The rule raises the `150%+` burden by at most 0.04 points, in 18 states. Without
  it, 53 tract rows in that band would have a negative burden.
- **Data coverage differs by band.** DOE has no valid value for a larger share of low-income
  households: 14–24% per measure in the lowest band, against 4–8% in the highest. Those households
  are not in the averages. This comes from DOE's data, not from the rule above, so lowest-band
  averages rest on a smaller share of the band's households.

## Contact

Rahul Agrawal Bejarano, data@energyequityproject.org

## Suggested citation

Energy Equity Project. (2026). Energy burden by census tract, county and state, overall, by poverty level and by area median income, DOE LEAD 2022. Prepared for
the Union of Concerned Scientists. Underlying data: U.S. Department of Energy, Low-Income Energy
Affordability Data (LEAD) Tool, 2022.
