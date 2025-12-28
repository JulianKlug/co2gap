# Cohort source
## cardiac surgery admissions
We consider admissions to be "post cardiac surgery" when the hospital stay (`hadm_id`) contains at least one ICD-9 procedure code that reflects major open-heart operations. The following buckets cover the typical postoperative CVICU population:

| Bucket | ICD-9 codes | Notes |
| --- | --- | --- |
| Valve or septal surgery | `3500-3599` | Closed/open valvotomies, valve replacements, annuloplasty, atrial/ventricular septal repairs, percutaneous valve interventions. |
| Coronary artery bypass (CABG) | `3610-3619` plus `3630-3634`, `3639` | Aortocoronary bypass (1-4 grafts), internal mammary grafts, transmyocardial revascularization procedures. |
| Major mechanical support or transplant | `3751-3755`, `3760`, `3763-3766`, `3768`, `3961`, `3962`, `3966` | Heart transplant, ventricular assist device implantation/removal, extracorporeal circulation/hypothermia used during open-heart surgery. |


## Surgery time derivation
infer the operative "day 0" timestamp per admission using the following hierarchy:
1. **MetaVision OR procedureevents** – if any `procedureevents_mv` row records `itemid` 225467 (Chest Opened), 225469 (OR Received), or 225470 (OR Sent), take the earliest `starttime` as `surgery_time`.
2. **CSRU transfer** – absent OR events, use the first `transfers` record whose `curr_careunit = 'CSRU'` and previous unit wasn’t CSRU. This captures the OR→CSRU handoff common after cardiac surgery.
3. **ICU intime fallback** – if neither signal exists (e.g., sparse legacy documentation), fall back to `icustays.intime` to keep the stay in scope while aligning the day-0 anchor near the ICU admission.


## Swan-Ganz catheter use
| Source table | Item IDs | Description |
| --- | --- | --- |
| `procedureevents_mv` | `224560` | Explicit "PA Catheter" insertion procedure (MetaVision only). |
| `datetimeevents` | `225351-225356` | PA catheter cap/tubing/dressing/insertion timestamps (MetaVision, Access Lines category). |
| `chartevents` (MetaVision) | `225355`, `225357`, `225358`, `225730`, `225745`, `225781`, `226114`, `227351` | Ongoing PA catheter site assessment, waveform, dressing, discontinuation, placement confirmation. |
| `chartevents` hemodynamics (MetaVision) | `220059`, `220060`, `220061` | Pulmonary artery systolic/diastolic/mean pressures; these values exist only when a PA catheter is connected. |
| `chartevents` hemodynamics (CareVue) | `491`, `492`, `8448` | PAP mean / systolic / diastolic in CareVue. |
| `chartevents` Swan-specific (CareVue) | `664` | "Swan SVO2" measurement, indicating a Swan-Ganz line. |

