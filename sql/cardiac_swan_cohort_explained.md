# cardiac_swan_cohort.sql explained

1. `SET search_path TO mimiciii;`
   - Ensures every unqualified table reference (e.g., `icustays`) resolves inside the `mimiciii` schema so the query is portable.

2. `cardiac_surgery_hadm` CTE
   - Collects every hospital admission (`hadm_id`) that contains at least one ICD-9 procedure code corresponding to major cardiac surgery (valve/septal work 3500-3599, CABG 3610-3619, revascularization 3630-3639, VAD/transplant/extracorporeal support codes).
   - Result: distinct list of candidate postoperative cardiac surgery hospitalizations.

3. `surgery_services` CTE
   - Pulls the earliest timestamp when the admission was assigned to a cardiac surgery service (`curr_service LIKE 'CSURG%'`), treating it as the operative handoff time.
   - Result: `hadm_id -> surgery_time` map capturing the best proxy for "day 0" when available.

4. `cardiac_hadm` CTE
   - Left-joins the service timestamps onto the surgery admissions, keeping all cardiac-surgery `hadm_id` values even if they lack an explicit CSURG record.
   - Result: admissions with an optional `surgery_time` column.

5. `icu_surgery` CTE
   - Joins each qualifying admission to its ICU stays.
   - Adds two derived timestamps per ICU stay:
     * `surgery_time`: CSURG timestamp if known, otherwise the ICU admission (`intime`).
     * `surgery_time_end`: `surgery_time + 30 days` to define the observation window.
   - Carries forward ICU metadata (`subject_id`, `hadm_id`, `icustay_id`, `intime`, `outtime`, `first_careunit`).

6. `pa_catheter_proc` CTE
   - Searches `procedureevents_mv` for item 224560 (explicit PA catheter placement) that occurred between `surgery_time` and `surgery_time_end` for the matching ICU stay.
   - Ensures procedural documentation is temporally aligned with the day 0–30 window.

7. `pa_catheter_chart` CTE
   - Looks in `chartevents` for all Swan-Ganz / pulmonary artery measurement item IDs, again restricting entries to the window `[surgery_time, surgery_time_end]` per ICU stay.
   - Captures both hemodynamic readings (e.g., PAP) and line assessments/dressings that imply catheter presence.

8. `pa_catheter_datetime` CTE
   - Similar to the previous step but uses `datetimeevents` entries (cap changes, insert timestamps) to broaden coverage, still bound to the same window.

9. `pa_catheter_any` CTE
   - Union of the three evidence sources, producing a distinct list of ICU stays with Swan-Ganz documentation within the specified timeframe.

10. Final SELECT
    - Joins `icu_surgery` with `pa_catheter_any` to keep only those ICU stays that (a) occur after cardiac surgery and (b) show Swan-Ganz activity between day 0 and day 30.
    - Returns subject/hospital/ICU identifiers plus the stay timing, the inferred surgery timestamp, and the 30-day cutoff for downstream analyses.
