# 2026_10_ucs_lead_energy_burden

## The request

| | |
|---|---|
| Partner | Union of Concerned Scientists (UCS) |
| Contact | [name, role, email] |
| Received | 2026-10 |
| Due | [yyyy-mm-dd] |
| Ask | National energy burden from DOE LEAD 2022 at the census tract, county and state levels, each overall and by Federal Poverty Level band, plus the same three levels by Area Median Income band |

## Goals

- Give UCS national energy burden (energy cost as a percent of income) for every census tract, county
  and state in the 50 states, DC and Puerto Rico, overall and by income band.
- Follow the DOE LEAD tool's method, and confirm the files reproduce the values the tool displays.
- Document every rule and caveat so the files can be used without EEP's code.

## Data sources

DOE Low-Income Energy Affordability Data (LEAD), 2022 release (OpenEI submission 6219), downloaded
2025-08-06 and cleaned by EEP's shared LEAD processor. File locations come from `.Renviron`.

| Dataset | `.Renviron` variable | Used for |
|---|---|---|
| LEAD 2022 FPL cohort file | `LEAD_NATIONAL_FILE` | Overall tract and county files, the three FPL band files |
| LEAD 2022 AMI cohort file | `LEAD_AMI_NATIONAL_FILE` | Overall state file, the three AMI band files |
| LEAD 2022 FPL and AMI tract rollups | `LEAD_ROLLUP_FILE`, `LEAD_AMI_ROLLUP_FILE` | Regression check only |

See `METHODOLOGY.md` for the variables used and how energy burden is calculated.

## Files created

Nine CSVs in `OUTPUT_DIR`, each named `dd-mm-yyyy-ucs-lead-2022-<name>.csv` with the build date.

| Name | One row per | Rows | Built from |
|---|---|---|---|
| `tract-energy-burden` | Census tract | 84,280 | FPL file |
| `tract-energy-burden-fpl` | Tract × FPL band | 421,400 | FPL file |
| `county-energy-burden` | County | 3,222 | FPL file |
| `county-energy-burden-fpl` | County × FPL band | 16,110 | FPL file |
| `state-energy-burden` | State | 52 | AMI file |
| `state-energy-burden-fpl` | State × FPL band | 260 | FPL file |
| `tract-energy-burden-ami` | Tract × AMI band | 505,680 | AMI file |
| `county-energy-burden-ami` | County × AMI band | 19,332 | AMI file |
| `state-energy-burden-ami` | State × AMI band | 312 | AMI file |

`outputs/README.md` is the partner-facing data dictionary and caveats, and ships with the files.

## Repo files

- `METHODOLOGY.md`: data sources, the energy burden calculation and the check against the LEAD tool.
- `R/functions.R`: the weights, table builds, checks and summaries shared by both builds.
- `R/01_build.R`: builds from the FPL file and writes five CSVs.
- `R/02_build_ami.R`: builds from the AMI file and writes four CSVs.
- `R/03_check_lead_tool.R`: compares the latest CSVs with values read off the DOE LEAD tool.

## How to rebuild

1. Copy `.Renviron.example` to `.Renviron` and fill in the five variables. `.Renviron` is gitignored,
   and a local pre-commit hook blocks it as well.
2. Start R from the repo root (or open `2026_10_ucs_lead_energy_burden.Rproj`) so `.Renviron` is read.
   Restart R after editing it.
3. Run `R/01_build.R`, then `R/02_build_ami.R`. Each takes about 15–25 seconds and stops before writing
   if a variable is missing or any check fails.
4. Run `R/03_check_lead_tool.R` to confirm the files still match the LEAD tool (46 of 46 headline
   values under the tool's display rules).

## Deliveries

| Delivery | Sent to | Notes |
|---|---|---|
| [delivered_yyyy-mm-dd] | [name] | first delivery |

Archived at `s3://eep-data-requests/2026_10_ucs_lead_energy_burden/`. Get a new download link with
`../eep_data_request_tools/scripts/deliver.sh --relink 2026_10_ucs_lead_energy_burden/[delivery]`.
