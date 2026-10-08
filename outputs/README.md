# Energy burden by census tract, county and state, DOE LEAD 2022

Prepared by the Energy Equity Project (EEP) for the Union of Concerned Scientists, [delivery date].

## Contents

| File | Description |
|---|---|
| `dd-mm-yyyy-ucs-lead-2022-tract-energy-burden.csv` | One row per census tract, 84,280 rows |
| `dd-mm-yyyy-ucs-lead-2022-county-energy-burden.csv` | One row per county or county equivalent, 3,222 rows |
| `dd-mm-yyyy-ucs-lead-2022-state-energy-burden.csv` | One row per state, 52 rows |

All three files cover the 50 states, the District of Columbia and Puerto Rico. Each date prefix is
the day the file was built.

## Data dictionary

The tract and county files share the same columns, and the tract file adds `tract_geoid`. The state
file has `state_fips`, `state_abbr`, `state_name`, `total_households` and the six dollar and burden
columns, from `weighted_income` to `energy_burden`. It does not have the geography codes below the
state level or the four `*_households` weight columns.

| Column | Type | Description | Units |
|---|---|---|---|
| `state_fips` | text | 2-digit state FIPS code | — |
| `state_abbr` | text | 2-letter postal abbreviation (state file only) | — |
| `state_name` | text | State name (state file only) | — |
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

## Methods and caveats

- **How the averages are built.** DOE LEAD reports modeled estimates for groups of households
  within each census tract. The groups are defined by poverty level, tenure, building age,
  building type and heating fuel. Within each tract, county or state:
  - Income and each fuel cost are averaged across these groups, weighted by the number of
    households with valid data for that measure.
  - Total utility cost is the sum of the three fuel costs.
  - Energy burden is total utility cost divided by income.
- **Energy burden is an area-level ratio.** It divides average energy cost by average income, as
  in DOE's LEAD Tool. It is not the average of individual household burdens, which would generally
  be higher because low-income households carry the highest burdens.
- **State values come from the household groups, not from the tract or county files.** Each state
  average is computed from all LEAD household groups in the state, in the same way as the tract and
  county averages. A state's burden is therefore not the average of its tract or county burdens.
- **Missing fuels count as $0.** If no households in an area have valid data for a fuel, that
  fuel's cost column is blank, and it adds $0 to `total_utility_cost`. If no fuel has valid data,
  `total_utility_cost` is blank too.
- **Blank burdens.** `energy_burden` is blank for 17 small census tracts whose modeled income in
  the DOE data is effectively zero. All counties have a value.
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

## Contact

[EEP contact name and email]

## Suggested citation

Energy Equity Project. (2026). Energy burden by census tract, county and state, DOE LEAD 2022. Prepared for
the Union of Concerned Scientists. Underlying data: U.S. Department of Energy, Low-Income Energy
Affordability Data (LEAD) Tool, 2022.
