# Output Data Dictionary

This document explains the source and derivation of every column contained in the exported CSV files under `output/`.

## cardiac_swan_demographics.csv
| Column | Description | Source |
| --- | --- | --- |
| subject_id | MIMIC-III `SUBJECT_ID`. | `patients.subject_id` |
| hadm_id | Hospital admission ID. | `admissions.hadm_id` |
| icustay_id | ICU stay identifier. | `icustays.icustay_id` |
| first_careunit | ICU care unit at admission (e.g., CSRU). | `icustays.first_careunit` |
| icu_intime | ICU admission timestamp. | `icustays.intime` |
| icu_outtime | ICU discharge timestamp. | `icustays.outtime` |
| surgery_time | Inferred day-0 timestamp (procedureevents OR CSRU transfer fallback). | Derived in cohort CTE (`sql/extract_data.sql`) |
| surgery_time_source | Source used for `surgery_time` (`procedureevents_mv`, `csru_transfer`, or `icustay_intime`). | Derived flag |
| admittime | Hospital admission time. | `admissions.admittime` |
| dischtime | Hospital discharge time. | `admissions.dischtime` |
| deathtime | In-hospital death time (if any). | `admissions.deathtime` |
| ethnicity | Documented ethnicity string. | `admissions.ethnicity` |
| hospital_expire_flag | 1 if the patient died during the admission, else 0. | `admissions.hospital_expire_flag` |
| gender | Biological sex. | `patients.gender` |
| dob | Date of birth (shifted per HIPAA rules). | `patients.dob` |
| dod | Date of death (if any). | `patients.dod` |
| age_years | Approximate age at admission. | Computed: `(admittime - dob)` in years |

## cardiac_swan_surgery_icd.csv
| Column | Description | Source |
| --- | --- | --- |
| subject_id | Patient ID. | `temp_cardiac_swan_cohort.subject_id` |
| hadm_id | Admission ID. | `temp_cardiac_swan_cohort.hadm_id` |
| icustay_id | ICU stay ID. | `temp_cardiac_swan_cohort.icustay_id` |
| surgery_time | Inferred day-0 timestamp. | From cohort CTE |
| surgery_time_source | Indicates whether `surgery_time` came from procedureevents, CSRU transfer, or ICU intime. | Derived flag |
| or_event_time | Earliest OR timestamp from `procedureevents_mv` (if present). | `procedure_events.proc_time` |
| csru_arrival_time | First CSRU transfer time. | `csru_transfer.csru_time` |
| seq_num | Order of the ICD-9 procedure code within the admission. | `procedures_icd.seq_num` |
| icd9_code | ICD-9 procedure code. | `procedures_icd.icd9_code` |
| short_title | Short description of the ICD-9 code. | `d_icd_procedures.short_title` |
| long_title | Long description of the ICD-9 code. | `d_icd_procedures.long_title` |

## cardiac_swan_blood_gases.csv
| Column | Description | Source |
| --- | --- | --- |
| subject_id / hadm_id / icustay_id | Identifiers for the cohort ICU stay. | Cohort temp table |
| surgery_time | Day-0 anchor for windowing. | Cohort CTE |
| charttime | Timestamp when the lab was charted. | `labevents.charttime` |
| itemid | LOINC-like identifier for the blood gas analyte. | `labevents.itemid` |
| lab_label | Human-readable label. | `d_labitems.label` |
| specimen | Original `fluid` field from `d_labitems` (e.g., `Blood`, `BLOOD`). | `d_labitems.fluid` |
| category | `d_labitems.category` (should be `Blood Gas`). | `d_labitems.category` |
| value | String representation reported in `labevents.value`. | `labevents.value` |
| valuenum | Numeric measurement (if parseable). | `labevents.valuenum` |
| valueuom | Reported units. | `labevents.valueuom` |
| flag | Lab flag (e.g., `abnormal`). | `labevents.flag` |
| specimen_type | SPECIMEN TYPE text (e.g., `ART`, `VEN`, `MIX`, `CENTRAL VENOUS`). | Lateral join to `labevents` itemids 50800/50801 at same charttime |

## cardiac_swan_swanmeasures.csv
| Column | Description | Source |
| --- | --- | --- |
| subject_id / hadm_id / icustay_id | Cohort identifiers. | Cohort temp table |
| surgery_time | Day-0 anchor. | Cohort CTE |
| charttime | Timestamp of the charted hemodynamic entry. | `chartevents.charttime` |
| storetime | Time the event was stored. | `chartevents.storetime` |
| itemid | MetaVision or CareVue item identifier. | `chartevents.itemid` |
| label | Pulled from `d_items.label` (e.g., `Pulmonary Artery Pressure mean`, `Cardiac Output (thermodilution)`). | `d_items` |
| value | Raw value string (for textual entries). | `chartevents.value` |
| valuenum | Numeric measurement (e.g., PAP in mmHg, CO in L/min). | `chartevents.valuenum` |
| valueuom | Units (mmHg, L/min, L/min/m2, etc.). | `chartevents.valueuom` |

## cardiac_swan_hemoglobin_temperature.csv
| Column | Description | Source |
| --- | --- | --- |
| subject_id / hadm_id / icustay_id | Cohort identifiers. | Cohort temp table |
| surgery_time | Day-0 anchor. | Cohort CTE |
| charttime | Timestamp of the measurement. | `labevents.charttime` or `chartevents.charttime` |
| measurement | Either `hemoglobin` or `temperature`. | Derived label |
| source_table | Indicates whether the row came from `labevents` or `chartevents`. | Derived label |
| itemid | Underlying MIMIC item identifier. | `labevents.itemid` or `chartevents.itemid` |
| label | Human-readable description from `d_labitems` or `d_items`. | `d_labitems.label` / `d_items.label` |
| value | String value (if textual). | `labevents.value` / `chartevents.value` |
| valuenum | Numeric measurement (g/dL, °F/°C). | `labevents.valuenum` / `chartevents.valuenum` |
| valueuom | Units reported with the measurement. | `labevents.valueuom` / `chartevents.valueuom` |

## cardiac_swan_matched_measurements.csv
| Column | Description | Source |
| --- | --- | --- |
| anchor_type | `cardiac_output` for every row (anchor chosen from Swan-Ganz cardiac output measurements). | Derived from `cardiac_swan_swanmeasures.csv` |
| subject_id / hadm_id / icustay_id | Cohort identifiers. | Propagated from anchors |
| anchor_time | Timestamp of the cardiac output measurement used as the reference point. | `cardiac_swan_swanmeasures.csv:charttime` |
| arterial_* / central_* | Blood-gas values (sat, pCO2, pH) along with units, timestamps, and source (`labevents`). | `cardiac_swan_blood_gases.csv` filtered by specimen type (`ART` for arterial, `CENTRAL` plus optional `VEN` when `--include-venous` is enabled) |
| hemoglobin_* | Nearest hemoglobin lab within ±30 min (value/unit/label/source/time/delta). | `cardiac_swan_hemoglobin_temperature.csv` (measurement=`hemoglobin`) |
| temperature_* | Nearest temperature (lab or chart) within ±30 min. | `cardiac_swan_hemoglobin_temperature.csv` (measurement=`temperature`) |
| cardiac_output_* | Nearest Swan-Ganz cardiac output entry within ±30 min. | `cardiac_swan_swanmeasures.csv` filtered by CO itemids |
| cardiac_index_* | Nearest cardiac index entry within ±30 min. | `cardiac_swan_swanmeasures.csv` filtered by CI itemids |
| *_delta_minutes | Absolute time difference (minutes) between the anchor and the matched value. | Computed in `scripts/build_matched_measurements.py` |

Each CSV row inherits the 30-day windowing constraint: only labs/measurements whose `charttime` falls between `surgery_time` and `surgery_time_end` are included.
