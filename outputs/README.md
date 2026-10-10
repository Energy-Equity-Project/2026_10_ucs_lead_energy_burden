# Energy burden by census tract, county and state, overall, by poverty level and by area median income, DOE LEAD 2022

Prepared by the Energy Equity Project (EEP) for the Union of Concerned Scientists, [delivery date].

## Contents

| File | Description |
|---|---|
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden.csv` | One row per census tract, 84,280 rows |
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-fpl.csv` | One row per census tract and Federal Poverty Level band, 421,400 rows (84,280 tracts × 5 bands) |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden.csv` | One row per county or county equivalent, 3,222 rows |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden-fpl.csv` | One row per county and Federal Poverty Level band, 16,110 rows (3,222 counties × 5 bands) |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden.csv` | One row per state, 52 rows |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden-fpl.csv` | One row per state and Federal Poverty Level band, 260 rows (52 states × 5 bands) |
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden-ami.csv` | One row per census tract and Area Median Income band, 505,680 rows (84,280 tracts × 6 bands) |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden-ami.csv` | One row per county and Area Median Income band, 19,332 rows (3,222 counties × 6 bands) |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden-ami.csv` | One row per state and Area Median Income band, 312 rows (52 states × 6 bands) |

All nine files cover the 50 states, the District of Columbia and Puerto Rico. Each date prefix is
the day the file was built.

There is no overall area median income file. The three overall files (tract, county and state, with
no band) come from DOE's poverty level data, so they are not the totals of the area median income
bands. See "AMI files come from a separate DOE LEAD file" below.

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
| `tract_geoid` | text | 11-digit census tract GEOID (tract file only) | — |
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
  area median income files only.

## Methods and caveats

- **How the averages are built.** DOE LEAD reports modeled estimates for groups of households
  within each census tract. The groups are defined by poverty level (area median income band in
  the AMI files), tenure, building age, building type and heating fuel. Within each tract, county or state:
  - Income and each fuel cost are averaged across these groups, weighted by the number of
    households with valid data for that measure.
  - Two kinds of group are left out of the averages: groups whose average income is below $1,000,
    and, for a single fuel, groups whose average cost for that fuel is negative. See "Household groups
    left out of the averages" below.
  - Total utility cost is the sum of the three fuel costs.
  - Energy burden is total utility cost divided by income.
- **Energy burden is an area-level ratio.** It divides average energy cost by average income, as
  in DOE's LEAD Tool. It is not the average of individual household burdens, which would generally
  be higher because low-income households carry the highest burdens.
- **State values come from the household groups, not from the tract or county files.** Each state
  average is computed from all LEAD household groups in the state, in the same way as the tract and
  county averages. A state's burden is therefore not the average of its tract or county burdens.
- **Poverty level values use the same method within each band.** Each state and poverty level row
  is computed from only that band's household groups in the state. Its burden is the band's average
  energy cost divided by its average income. The five band burdens do not average to the state
  burden; the state value combines the bands' costs and incomes, weighted by households.
- **Tract and county poverty level values work the same way.** Each tract or county and poverty
  level row is computed from only that band's household groups in the area, so the five band
  burdens do not average to the tract or county burden.
- **Every area has all five poverty levels.** In 358 tracts and 2 counties, LEAD has no households
  in one or more bands. Those rows are still included, with 0 in `total_households` and the four
  `*_households` columns and blank averages, costs and burden. There are 754 such tract rows and 2
  county rows; both county rows are in the `0-100%` band.
- **Poverty level rows are small.** Splitting an area by band leaves few households in many rows:
  4,486 tract and poverty level rows have fewer than 10 households. Burdens in the `0-100%` band are
  high by nature (38,255 tract rows in that band are above 20%), and some rows are extreme: 423 tract
  rows in that band are above 100%, up to 1,214%. Consider filtering or flagging on
  `total_households` when mapping.
- **Area median income values use the same method.** Each area and AMI band row is computed from
  only that band's household groups in the area. The six band burdens do not average to the area's
  overall burden.
- **AMI files come from a separate DOE LEAD file, and their household counts do not match the
  other files exactly.** DOE publishes the AMI and poverty level data as separate files, and in
  some areas they estimate different numbers of households. Nationally, the AMI bands total
  127,451,762 households, against 126,917,028 in the overall and poverty level files (0.4% more).
  The gap is concentrated in California, New York, Massachusetts, Hawaii and Connecticut:
  - 6,258 tracts (7.4%) differ by more than 0.1%, by up to 93%.
  - 29 counties differ by more than 0.1%.
  - Five states differ by more than 0.1%, led by Connecticut (3.7%) and California (3.3%).

  Summing an area's AMI bands therefore does not always reproduce the `total_households` in the
  overall tract, county or state files. **The overall files are poverty level totals, not AMI
  totals.** Compare an AMI band with other AMI bands or areas, not with the overall files, and do not
  combine the AMI files with the poverty level files in a single calculation. No overall AMI file is
  delivered.
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
  `0-30%` band are high by nature (31,758 tract rows in that band are above 20%), and 198 tract rows
  in that band are above 100%, up to 627%.
- **Missing fuels count as $0.** If no households in an area have valid data for a fuel, that
  fuel's cost column is blank, and it adds $0 to `total_utility_cost`. If no fuel has valid data,
  `total_utility_cost` is blank too.
- **Blank burdens.** `energy_burden` is blank for 17 small census tracts (40 households or fewer)
  where no household group has an average income of $1,000 or more. All counties have a value.
  - In the poverty level files, it is blank for 858 tract rows: the 754 rows with no households, 103
    rows with no group at $1,000 or more of income and 1 row with no valid fuel data. It is also blank
    for the 2 county rows with no households.
  - In the area median income files, it is blank for 1,044 tract rows: the 935 rows with no
    households, 106 rows with no group at $1,000 or more of income and 3 rows with no valid fuel
    data. It is also blank for the 1 county row with no households.
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

Two rules apply in the same way to every file, area and band:

- **Average income below $1,000.** A household group whose average income is below $1,000 is left
  out of every average: income and all three fuel costs. These incomes are near zero or negative
  (the Census data behind LEAD records business and investment losses as negative income), and they
  produced burdens in the thousands of percent, up to 2.9 million percent in one tract row.
- **Negative fuel cost.** A household group with a negative average cost for a fuel is left out of
  that fuel's average only. Its income and other fuel costs still count.

The households in these groups still count in `total_households`, but not in the `*_households`
weight columns. In the tables below, "weight left out" is the share of a measure's households with
valid data that the rules remove, and "no valid data" is the share of all households that DOE
reports without a valid value for income, electricity, gas or other fuel. Both shares are national.

**Poverty level bands**

| Band | Groups under $1,000 income | Income weight left out | Fuel weight left out | Groups with a negative cost | No valid data: income / electricity / gas / other fuel | National burden, before → after |
|---|---|---|---|---|---|---|
| `0-100%` | 196,592 | 5.0% | 4.8–5.0% | 0 | 14% / 19% / 23% / 15% | 19.64% → 18.74% |
| `100-150%` | 0 | 0% | 0% | 0 | 12% / 16% / 19% / 13% | 8.34%, unchanged |
| `150-200%` | 0 | 0% | 0% | 0 | 10% / 13% / 16% / 11% | 6.05%, unchanged |
| `200-400%` | 0 | 0% | 0% | 0 | 7% / 9% / 12% / 8% | 3.73%, unchanged |
| `400%+` | 0 | 0% | < 0.01% | 10 | 4% / 5% / 8% / 5% | 1.55%, unchanged |
| All households | 196,592 | 0.5% | 0.4–0.5% | 10 | 7% / 9% / 12% / 8% | 2.30% → 2.29% |

**Area median income bands**

| Band | Groups under $1,000 income | Income weight left out | Fuel weight left out | Groups with a negative cost | No valid data: income / electricity / gas / other fuel | National burden, before → after |
|---|---|---|---|---|---|---|
| `0-30%` | 160,344 | 3.5% | 3.4% | 0 | 14% / 19% / 24% / 16% | 16.11% → 15.60% |
| `30-60%` | 0 | 0% | 0% | 0 | 10% / 13% / 17% / 11% | 6.05%, unchanged |
| `60-80%` | 0 | 0% | 0% | 0 | 8% / 9% / 13% / 8% | 4.09%, unchanged |
| `80-100%` | 0 | 0% | 0% | 0 | 7% / 8% / 11% / 7% | 3.14%, unchanged |
| `100-150%` | 0 | 0% | 0% | 0 | 5% / 6% / 9% / 6% | 2.07%, unchanged |
| `150%+` | 1,874 | < 0.01% | 0.02–0.11% | 15,635 | 4% / 4% / 6% / 4% | 1.36%, unchanged (+0.001) |
| All households | 162,218 | 0.4% | 0.4% | 15,635 | 7% / 9% / 12% / 8% | 2.27%, down 0.007 points |

**Which groups and statistics this affects**

- **The lowest band.** Nearly all the excluded groups are in `0-100%` and `0-30%`, so these bands
  carry nearly all of the effect. The middle bands are unchanged in every file.
- **States.** Burden in the lowest band falls in every state:
  - `0-100%`: by 0.15 to 2.40 percentage points (median 0.93).
  - `0-30%`: by 0.29 to 3.78 points (median 0.60).

  The `150%+` AMI burden rises by at most 0.04 points, in 18 states.
- **Counties.** Lowest-band burden changes by more than 1 point in 804 counties (`0-100%`) and
  825 counties (`0-30%`). The largest changes are in small rural counties where these groups held
  much of the band's income weight, up to 27 points (`0-100%`) and 35 points (`0-30%`).
- **Overall files.** The overall files include the lowest-band groups, so they change too:
  - Tract burden changes in 62,432 tracts, by up to 12.4 points.
  - County burden changes by at most 0.25 points.
  - State burden changes by at most 0.02 points.
- **Direction.** The excluded groups have the lowest incomes and the highest burdens. Lowest-band
  burdens are therefore lower than they would be with those households included. Read them as the
  burden of households with an average income of at least $1,000.
- **Data coverage differs by band.** DOE has no valid value for a larger share of low-income
  households: 14–24% per measure in the lowest band, against 4–8% in the highest. Those households
  are not in the averages either. This comes from DOE's data, not from the rules above, so
  lowest-band averages rest on a smaller share of the band's households.

## Contact

[EEP contact name and email]

## Suggested citation

Energy Equity Project. (2026). Energy burden by census tract, county and state, overall, by poverty level and by area median income, DOE LEAD 2022. Prepared for
the Union of Concerned Scientists. Underlying data: U.S. Department of Energy, Low-Income Energy
Affordability Data (LEAD) Tool, 2022.
