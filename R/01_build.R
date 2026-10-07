# Build every file in outputs/ for this data request.
# Reads only cleaned, shared data; never copy shared data into this repo.

# Load required packages
library(tidyverse)
library(janitor)

# Shared cleaned data (paths are relative to the repo root)
cleaned_dir <- "../../Cleaned_Data"
output_dir <- "outputs"
run_date <- format(Sys.Date(), "%d-%m-%Y")

# Read inputs
source_data <- read.csv(file.path(cleaned_dir, "[source]/[file].csv")) %>%
  clean_names()

# Build the deliverable
request_summary <- source_data %>%
  group_by(state) %>%
  summarize(n = n()) %>%
  ungroup()

# Write outputs; document every file and column in outputs/README.md
write.csv(
  request_summary,
  file.path(output_dir, paste0(run_date, "-request-summary.csv")),
  row.names = FALSE
)
