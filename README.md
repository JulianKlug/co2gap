# Cardiac Surgery + Swan-Ganz Extraction Guide

This repository contains the SQL and documentation required to reproduce a cohort of postoperative cardiac-surgery ICU stays with Swan-Ganz catheters and to export the downstream demographic, surgical, laboratory, and hemodynamic datasets from MIMIC-III v1.4.

## Prerequisites
- Access to the raw MIMIC-III v1.4 CSVs (stored read-only at `/mnt/hdd1/datasets/mimiciii_1.4`).
- The `co2gap` conda environment activated for all work.
- PostgreSQL 9.6+ running locally with a superuser you can use (e.g., `postgres`). The `.pgpass` file already stores the password for `postgres` on `localhost`.
- The [mimic-code](https://github.com/MIT-LCP/mimic-code) repository cloned so you can run the official build scripts (`create.sql`, `load.sql`, `indexes.sql`, `constraints.sql`).

## 1. Build the MIMIC-III database
1. Ensure PostgreSQL is running: `sudo systemctl status postgresql`.
2. Clone mimic-code and enter the Postgres build folder:
   ```bash
   git clone https://github.com/MIT-LCP/mimic-code.git ~/src/mimic-code
   cd ~/src/mimic-code/mimic-iii/buildmimic/postgres
   ```
3. Set up a database and schema:
   ```bash
   createuser --superuser mimicuser   # or reuse postgres
   createdb -O mimicuser mimic
   psql -d mimic -c "CREATE SCHEMA IF NOT EXISTS mimiciii AUTHORIZATION mimicuser;"
   ```
4. Load the data (point to the `/mnt/hdd1/datasets/mimiciii_1.4` directory):
   ```bash
   export MIMIC_DATA_DIR=/mnt/hdd1/datasets/mimiciii_1.4
   psql -d mimic -v mimic_data_dir="$MIMIC_DATA_DIR" -f create.sql
   psql -d mimic -v mimic_data_dir="$MIMIC_DATA_DIR" -f load.sql
   psql -d mimic -f indexes.sql
   psql -d mimic -f constraints.sql
   ```
5. Validate the install:
   ```bash
   psql -h localhost -U postgres -d mimic -c "SET search_path TO mimiciii; SELECT count(*) FROM admissions;"
   ```

## 2. Review cohort definitions
- `docs/cardiac_swan_cohort.md` explains the ICD-9 ranges, Swan-Ganz item IDs, surgery-day logic, and example SQL to retrieve the cohort.
- `sql/cardiac_swan_cohort.sql` contains the executable CTE query.
- `sql/cardiac_swan_cohort_explained.md` walks through each CTE.

## 3. Run the extraction
1. Ensure the `output/` folder exists and is gitignored (already set up).
2. Execute the export script:
   ```bash
   psql -h localhost -U postgres -d mimic -f sql/extract_data.sql
   ```
   This script:
   - Rebuilds the cohort temp table with day 0–30 constraints.
   - Exports five CSVs to `output/`:
     * `cardiac_swan_demographics.csv`
     * `cardiac_swan_surgery_icd.csv`
     * `cardiac_swan_blood_gases.csv` (includes `specimen_type` from itemids 50800/50801)
     * `cardiac_swan_swanmeasures.csv` (PAP, SvO₂, cardiac output/index, etc.)
     * `cardiac_swan_hemoglobin_temperature.csv` (hemoglobin labs + lab/charted temperatures)
3. Refer to `sql/extract_data_explained.md` for a narrative description of each temp table and output.

## 4. Post-processing
- The CSVs are large (~300 MB combined). Compress or subset them before sharing.
- If you need to adjust the cohort definition or add new measures, edit `sql/cardiac_swan_cohort.sql` and/or extend `sql/extract_data.sql`.
- Update `progress.md` after each major run to keep the project log current.

## Troubleshooting
- Collation warnings: run `ALTER DATABASE mimic REFRESH COLLATION VERSION;` if libc updates cause version mismatches.
- PostgreSQL auth: credentials live in `~/.pgpass`. If you add new roles, update that file accordingly.
- SPECIMEN TYPE decoding: `cardiac_swan_blood_gases.csv` now includes the raw strings (e.g., `ART`, `VEN`, `MIX`, `CENTRAL VENOUS`). Use those to classify arterial vs. venous samples.
- Temperatures: `cardiac_swan_hemoglobin_temperature.csv` captures both blood-gas temperature labs (`itemid` 50825) and charted temperatures (CareVue + MetaVision itemids) within the day 0–30 window.

Following these steps will let you rebuild the entire pipeline from raw MIMIC-III CSVs to the final analytic extracts housed in `output/`.
