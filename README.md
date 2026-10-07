# [request_id]

## The request

| | |
|---|---|
| Partner | [org name] |
| Contact | [name, role, email] |
| Received | [yyyy-mm-dd] |
| Due | [yyyy-mm-dd] |
| Ask | [what the partner asked for, in their words where possible] |

## Data sources

| Dataset | Path | Version / vintage | Notes |
|---|---|---|---|
| [e.g. DOE LEAD 2022] | `../../Cleaned_Data/doe/lead/...` | [version] | |

## Method

[Short description of filters, aggregations and joins. Enough for someone else to
rebuild the outputs.]

## How to rebuild

1. Open `[request_id].Rproj`.
2. Run `R/01_build.R`. It writes every file in `outputs/`.

## Deliveries

| Delivery | Sent to | Notes |
|---|---|---|
| [delivered_yyyy-mm-dd] | [name] | [first delivery / revision because ...] |

Archived at `s3://eep-data-requests/[request_id]/`. Get a new download link with
`../eep_data_request_tools/scripts/deliver.sh --relink [request_id]/[delivery]`.

## Caveats

- [Known limitations the partner was told about]
