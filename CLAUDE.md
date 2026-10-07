# [request_id]

## Purpose
[1-2 sentences: what the partner asked for and what EEP is sending them]

## Type
Data request — this repo CONSUMES data from the shared Data/ and Cleaned_Data/ folders
and produces a one-off deliverable for an external partner. It does not collect or
clean new data; if that is needed, it belongs in `Internal/data-pipelines/eep-pipeline-core/`.

## Status
[active | delivered | archived]

## Partner
- Organization: [org name]
- Contact: [name, role]
- Received: [yyyy-mm-dd]
- Due: [yyyy-mm-dd]
- Data restrictions: [none, or any terms on use, sharing or deletion]

## Data Dependencies
- Cleaned: `../../Cleaned_Data/[source]/[file]` — [description, version used]

## Key Files
- `R/01_build.R` — builds every file in `outputs/`
- `outputs/README.md` — partner-facing data dictionary; ships inside the delivery zip

## Outputs and Delivery
- `outputs/` is gitignored except `README.md`; files there are temporary.
- Deliver with `../eep_data_request_tools/scripts/deliver.sh .` after committing.
  It archives the outputs in `s3://eep-data-requests/[request_id]/` and prints a
  download link that expires in up to 7 days.
- After the partner confirms receipt, run `deliver.sh --clean .` to delete local outputs.
- Record each delivery in the README.md "Deliveries" table.
