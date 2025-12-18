# extract_data.sql explained

1. Cohort build (`temp_cardiac_swan_cohort`)
   - Reuses the cardiac surgery ICD-9 filters and Swan-Ganz item logic from `cardiac_swan_cohort.sql`.
   - Computes `surgery_time` by preferring procedureevents (OR timestamps) and falling back to first CSRU transfer (if any) or ICU `intime` as a last resort, with the observation window set to day 0–30.
   - Keeps metadata per ICU stay (subject/hadm/icustay IDs, ICU times, surgery-time source) for downstream joins.

2. Demographics extract (`temp_cardiac_swan_demographics`)
   - Joins the cohort to `admissions` and `patients` to get admission/discharge/death times, ethnicity, mortality flag, gender, DOB/DOD.
   - Adds ICU timing fields and derives age at admission.
   - Export: `output/cardiac_swan_demographics.csv` via `\copy`.

3. Surgery ICD catalog (`temp_cardiac_swan_surgery_icd`)
   - Joins each cohort admission to its `procedures_icd` rows and annotates with the `d_icd_procedures` titles.
   - Includes the inferred surgery timestamp, OR event time (if available), and CSRU arrival time for context.
   - Export: `output/cardiac_swan_surgery_icd.csv`.

4. Blood gas panel extraction (`temp_cardiac_swan_blood_gases`)
   - Filters `labevents` to items whose lab category is “Blood Gas”.
   - Restricts charttimes to the surgery day 0–30 window.
   - Uses a lateral join on `labevents` (itemids 50800/50801) to copy the explicit SPECIMEN TYPE string (ART/VEN/etc.) into a `specimen_type` column while preserving the original `fluid` field.
   - Export: `output/cardiac_swan_blood_gases.csv`.

5. Swan-Ganz measurements (`temp_cardiac_swan_measures`)
   - Defines a curated set of `chartevents` itemids covering PAP, cardiac output/index, SvO₂, thermodilution entries, and related derived metrics.
   - Pulls all matching events per ICU stay within the day 0–30 window, keeping chart/store times, labels, numeric values, and units.
   - Export: `output/cardiac_swan_swanmeasures.csv`.

Each section follows the same pattern: create/refresh a temp table, then `\copy` it to the corresponding CSV under `output/`. Running `psql -f sql/extract_data.sql` reproduces all four files.
