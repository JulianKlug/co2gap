# Cardiac Surgery + Swan-Ganz Cohort Plan

## Data location
- All raw CSVs live at `/mnt/hdd1/datasets/mimiciii_1.4` (see `AGENTS.md`). The files are compressed (`*.csv.gz`) and **must stay read-only**.
- Always work inside the `co2gap` conda environment (`echo $CONDA_DEFAULT_ENV` should return `co2gap`).
- Notebook/editor work should stay under this repository so we avoid mutating `/mnt/hdd1`.

## Build the PostgreSQL copy of MIMIC-III
1. Make sure PostgreSQL is running locally (e.g. `sudo systemctl status postgresql`) and that your `$USER` can create databases.
2. Clone the official SQL build scripts once (they are not stored in this repo):
   ```bash
   git clone https://github.com/MIT-LCP/mimic-code.git ~/src/mimic-code
   cd ~/src/mimic-code/mimic-iii/buildmimic/postgres
   ```
3. Create a dedicated role/database (run inside the `co2gap` env):
   ```bash
   createuser --superuser mimicuser           # or ALTER ROLE if it already exists
   createdb -O mimicuser mimic
   psql -d mimic -c "CREATE SCHEMA IF NOT EXISTS mimiciii AUTHORIZATION mimicuser;"
   ```
4. Load the schema and data (the build scripts stream the gz files so no extra disk copies are needed):
   ```bash
   export MIMIC_DATA_DIR=/mnt/hdd1/datasets/mimiciii_1.4
   psql -d mimic -v mimic_data_dir="$MIMIC_DATA_DIR" -f create.sql
   psql -d mimic -v mimic_data_dir="$MIMIC_DATA_DIR" -f load.sql
   psql -d mimic -f indexes.sql
   psql -d mimic -f constraints.sql
   ```
   The `create/load/indexes/constraints.sql` files come from the cloned `mimic-code` repo. `load.sql` uses `COPY FROM PROGRAM 'gzip -dc ...'`, so the original gz files remain untouched.
5. Smoke-test the install:
   ```bash
   psql -d mimic -c "SET search_path TO mimiciii; SELECT count(*) FROM admissions;"
   psql -d mimic -c "SELECT tablename, tableowner FROM pg_tables WHERE schemaname='mimiciii';"
   ```
   If these succeed you have a working database ready for cohort-building SQL.

## Identify cardiac surgery admissions
We consider admissions to be "post cardiac surgery" when the hospital stay (`hadm_id`) contains at least one ICD-9 procedure code that reflects major open-heart operations. The following buckets cover the typical postoperative CVICU population and were verified from `D_ICD_PROCEDURES.csv.gz`:

| Bucket | ICD-9 codes | Notes |
| --- | --- | --- |
| Valve or septal surgery | `3500-3599` | Closed/open valvotomies, valve replacements, annuloplasty, atrial/ventricular septal repairs, percutaneous valve interventions. |
| Coronary artery bypass (CABG) | `3610-3619` plus `3630-3634`, `3639` | Aortocoronary bypass (1-4 grafts), internal mammary grafts, transmyocardial revascularization procedures. |
| Major mechanical support or transplant | `3751-3755`, `3760`, `3763-3766`, `3768`, `3961`, `3962`, `3966` | Heart transplant, ventricular assist device implantation/removal, extracorporeal circulation/hypothermia used during open-heart surgery. |

In SQL this becomes:

```sql
WITH cardiac_surgery_hadm AS (
  SELECT DISTINCT hadm_id
  FROM mimiciii.procedures_icd
  WHERE (
        icd9_code BETWEEN '3500' AND '3599'
     OR icd9_code BETWEEN '3610' AND '3619'
     OR icd9_code BETWEEN '3630' AND '3639'
     OR icd9_code IN ('3751','3752','3753','3754','3755','3760','3763','3764','3765','3766','3768','3961','3962','3966')
  )
)
```

You can tighten the definition further by requiring the hospital `services` table to show a `CSURG` service at or after the operative date:

```sql
SELECT DISTINCT hadm_id
FROM mimiciii.services
WHERE curr_service LIKE 'CSURG%';
```

Intersecting `cardiac_surgery_hadm` with this service filter usually keeps only the post-cardiac-surgery admissions.

## Identify Swan-Ganz (PA catheter) use
Pulmonary artery (PA, Swan-Ganz) catheters are charted differently in CareVue (2001-2008) versus MetaVision (2008-2012). Use multiple signal sources to get high sensitivity:

| Source table | Item IDs | Description |
| --- | --- | --- |
| `procedureevents_mv` | `224560` | Explicit "PA Catheter" insertion procedure (MetaVision only). |
| `datetimeevents` | `225351-225356` | PA catheter cap/tubing/dressing/insertion timestamps (MetaVision, Access Lines category). |
| `chartevents` (MetaVision) | `225355`, `225357`, `225358`, `225730`, `225745`, `225781`, `226114`, `227351` | Ongoing PA catheter site assessment, waveform, dressing, discontinuation, placement confirmation. |
| `chartevents` hemodynamics (MetaVision) | `220059`, `220060`, `220061` | Pulmonary artery systolic/diastolic/mean pressures; these values exist only when a PA catheter is connected. |
| `chartevents` hemodynamics (CareVue) | `491`, `492`, `8448` | PAP mean / systolic / diastolic in CareVue. |
| `chartevents` Swan-specific (CareVue) | `664` | "Swan SVO2" measurement, indicating a Swan-Ganz line. |

Translate that into reusable views:

```sql
WITH pa_catheter_proc AS (
  SELECT DISTINCT icustay_id FROM mimiciii.procedureevents_mv WHERE itemid = 224560
),
pa_catheter_chart AS (
  SELECT DISTINCT icustay_id
  FROM mimiciii.chartevents
  WHERE itemid IN (491,492,664,8448,220059,220060,220061,225355,225357,225358,225730,225745,225781,226114,227351)
),
pa_catheter_datetime AS (
  SELECT DISTINCT icustay_id
  FROM mimiciii.datetimeevents
  WHERE itemid IN (225351,225352,225353,225354,225356)
),
pa_catheter_any AS (
  SELECT icustay_id FROM pa_catheter_proc
  UNION SELECT icustay_id FROM pa_catheter_chart
  UNION SELECT icustay_id FROM pa_catheter_datetime
)
```

Note: CareVue lacks `procedureevents_mv`, so the PAP/Swan charted values are crucial for that era. If you want extra confidence, you can also require at least two pulmonary artery pressure chart events within a 6-hour window to avoid spurious documentation.

## Putting it together
## Restrict to day 0-30 post surgery
Cardiac surgery patients typically arrive in the CSRU directly from the OR, so we treat the first `CSURG` service timestamp as the operative date ("day 0"). When that timestamp is missing we fall back to the ICU admission time, which keeps legacy encounters in the cohort while still anchoring the timeline close to the surgery. All Swan-Ganz evidence is then filtered to the `[day 0, day 30]` window:

```sql
surgery_services AS (
  SELECT hadm_id, MIN(transfertime) AS surgery_time
  FROM mimiciii.services
  WHERE curr_service LIKE 'CSURG%'
  GROUP BY hadm_id
),
icu_surgery AS (
  SELECT icu.*,
         COALESCE(ss.surgery_time, icu.intime) AS surgery_time,
         COALESCE(ss.surgery_time, icu.intime) + INTERVAL '30 day' AS surgery_time_end
  FROM mimiciii.icustays icu
  JOIN cardiac_surgery_hadm cs ON cs.hadm_id = icu.hadm_id
  LEFT JOIN surgery_services ss ON ss.hadm_id = icu.hadm_id
)
```

Every `procedureevents_mv`, `chartevents`, and `datetimeevents` filter now checks that the relevant timestamp falls between `surgery_time` and `surgery_time_end`.

## Putting it together
Combine the admissions (`hadm_id`) level cardiac surgery flag with the ICU-level PA catheter evidence and the day 0-30 window:

```sql
WITH cardiac_surgery_hadm AS (
  SELECT DISTINCT hadm_id
  FROM mimiciii.procedures_icd
  WHERE (
        icd9_code BETWEEN '3500' AND '3599'
     OR icd9_code BETWEEN '3610' AND '3619'
     OR icd9_code BETWEEN '3630' AND '3639'
     OR icd9_code IN ('3751','3752','3753','3754','3755','3760','3763','3764','3765','3766','3768','3961','3962','3966')
  )
),
pa_catheter_proc AS (
  SELECT DISTINCT pe.icustay_id
  FROM mimiciii.procedureevents_mv pe
  JOIN icu_surgery isur ON isur.icustay_id = pe.icustay_id
  WHERE pe.itemid = 224560
    AND pe.starttime BETWEEN isur.surgery_time AND isur.surgery_time_end
),
pa_catheter_chart AS (
  SELECT DISTINCT ce.icustay_id
  FROM mimiciii.chartevents ce
  JOIN icu_surgery isur ON isur.icustay_id = ce.icustay_id
  WHERE ce.itemid IN (491,492,664,8448,220059,220060,220061,225355,225357,225358,225730,225745,225781,226114,227351)
    AND ce.charttime BETWEEN isur.surgery_time AND isur.surgery_time_end
),
pa_catheter_datetime AS (
  SELECT DISTINCT de.icustay_id
  FROM mimiciii.datetimeevents de
  JOIN icu_surgery isur ON isur.icustay_id = de.icustay_id
  WHERE de.itemid IN (225351,225352,225353,225354,225356)
    AND de.charttime BETWEEN isur.surgery_time AND isur.surgery_time_end
),
pa_catheter_any AS (
  SELECT icustay_id FROM pa_catheter_proc
  UNION SELECT icustay_id FROM pa_catheter_chart
  UNION SELECT icustay_id FROM pa_catheter_datetime
)
SELECT isur.subject_id,
       isur.hadm_id,
       isur.icustay_id,
       isur.intime,
       isur.outtime,
       isur.first_careunit,
       isur.surgery_time,
       isur.surgery_time_end
FROM icu_surgery isur
JOIN pa_catheter_any pa ON pa.icustay_id = isur.icustay_id
ORDER BY isur.intime;
```

Optional refinements:
- Link to `services` to keep only cardiac-surgery services.
- Join `procedureevents_mv` to recover the PA catheter `starttime`/`endtime` for duration analysis.
- Apply time-window filters (e.g. ICU stay starts within 48h of cardiac surgery OR PA catheter inserted before ICU discharge).

Running this query on the freshly built PostgreSQL copy will produce the desired cohort of postoperative cardiac surgery patients carrying a Swan-Ganz catheter.
