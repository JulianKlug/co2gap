### 2025-02-14
- Confirmed MIMIC-III gz files live at `/mnt/hdd1/datasets/mimiciii_1.4` (read-only) and that the `co2gap` conda env is active for all work.
- Wrote `docs/cardiac_swan_cohort.md` detailing the Postgres build steps plus the ICD-9 + PA-catheter logic needed for the cohort.
- Enumerated the exact ICD-9 ranges/item IDs for cardiac surgery admissions and Swan-Ganz use; captured the executable SQL in `sql/cardiac_swan_cohort.sql`.
- Verified PostgreSQL access via the `postgres` role/password stored in `~/.pgpass`; noted the libc collation mismatch warning that can be fixed later with `ALTER DATABASE ... REFRESH COLLATION VERSION` after rebuilds.
- Ran the cohort SQL over the loaded `mimic` DB: 6,272 ICU stays (6,196 hadm_id / 6,113 subjects) meet the cardiac-surgery + PA-catheter criteria; spot-checked the earliest admissions to confirm CSRU provenance.
- Addressed the libc collation mismatch by running `ALTER DATABASE ... REFRESH COLLATION VERSION` on both `mimic` and `postgres`; confirmed the warning disappears on reconnect.
- Refined the SQL to anchor each ICU stay to the earliest `CSURG` service transfer (fallback to ICU intime) and require PA-catheter documentation between surgery day (day 0) and day 30; refreshed docs to explain the assumption and reran the cohort, now yielding 6,198 ICU stays (6,148 hadm_id / 6,067 subjects).
- Added `sql/cardiac_swan_cohort_explained.md` to document each CTE/step in the refined SQL so future updates are easier to audit.
- Replaced the surgery-day anchor with a dual approach: earliest OR-related `procedureevents_mv` timestamp when available, otherwise the first transfer into CSRU (for cardiac-coded admissions). Reran the cohort query, now totaling 6,207 ICU stays (6,156 hadm_id / 6,074 subjects) under the day 0-30 rule.
