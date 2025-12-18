# cardiac_swan_cohort.sql explained

1. `SET search_path TO mimiciii;`
   - Ensures every unqualified table reference (e.g., `icustays`) resolves inside the `mimiciii` schema so the query is portable.

2. `cardiac_surgery_hadm` CTE
   - Collects every hospital admission (`hadm_id`) that contains at least one ICD-9 procedure code corresponding to major cardiac surgery (valve/septal work 3500-3599, CABG 3610-3619, revascularization 3630-3639, VAD/transplant/extracorporeal support codes).
   - Result: distinct list of candidate postoperative cardiac surgery hospitalizations.

3. `procedure_events` CTE
   - Uses MetaVision `procedureevents_mv` timestamps for OR-centric events (`itemid` 225467 Chest Opened, 225469 OR Received, 225470 OR Sent) and keeps the earliest one per admission.
   - Provides a high-fidelity operative timestamp whenever these procedure logs exist.

4. `csru_transfer` CTE
   - Finds the first transfer into `curr_careunit = 'CSRU'` (where the previous unit was not already CSRU`) for each admission that already passes the cardiac-surgery ICD-9 filter.
   - Acts as a fallback operative timestamp based on the OR→CSRU handoff, covering eras without detailed procedure logs.

5. `cardiac_hadm` CTE
   - Merges the procedure-based and CSRU-based timestamps, preferring the procedure timestamp when available.
   - Admission-level result with the best-known `surgery_time` (or `NULL` if neither signal exists).

6. `icu_surgery` CTE
   - Joins each qualifying admission to its ICU stays and derives:
     * `surgery_time`: the chosen operative timestamp or, if absent, the ICU `intime` as a conservative fallback.
     * `surgery_time_end`: 30 days after `surgery_time`, defining the observation window.
   - Carries forward ICU metadata (`subject_id`, `hadm_id`, `icustay_id`, `intime`, `outtime`, `first_careunit`).

7. `pa_catheter_proc` CTE
   - Searches `procedureevents_mv` for item 224560 (explicit PA catheter placement) that occurred between `surgery_time` and `surgery_time_end` for the matching ICU stay.
   - Ensures procedural documentation is temporally aligned with the day 0–30 window.

8. `pa_catheter_chart` CTE
   - Looks in `chartevents` for all Swan-Ganz / pulmonary artery measurement item IDs, again restricting entries to the window `[surgery_time, surgery_time_end]` per ICU stay.
   - Captures both hemodynamic readings (e.g., PAP) and line assessments/dressings that imply catheter presence.

9. `pa_catheter_datetime` CTE
   - Similar to the previous step but uses `datetimeevents` entries (cap changes, insert timestamps) to broaden coverage, still bound to the same window.

10. `pa_catheter_any` CTE
   - Union of the three evidence sources, producing a distinct list of ICU stays with Swan-Ganz documentation within the specified timeframe.

11. Final SELECT
    - Joins `icu_surgery` with `pa_catheter_any` to keep only those ICU stays that (a) occur after cardiac surgery and (b) show Swan-Ganz activity between day 0 and day 30.
    - Returns subject/hospital/ICU identifiers plus the stay timing, the inferred surgery timestamp, and the 30-day cutoff for downstream analyses.
