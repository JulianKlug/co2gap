-- Extracts cohort-level CSVs for cardiac surgery patients with Swan-Ganz catheters.
-- Outputs live under ./output/ (ensure directory exists and is gitignored).

\set ON_ERROR_STOP on
SET search_path TO mimiciii;

-- Build the cohort once per session.
DROP TABLE IF EXISTS temp_cardiac_swan_cohort;
CREATE TEMP TABLE temp_cardiac_swan_cohort AS
WITH cardiac_surgery_hadm AS (
  SELECT DISTINCT hadm_id
  FROM procedures_icd
  WHERE (
        icd9_code BETWEEN '3500' AND '3599'
     OR icd9_code BETWEEN '3610' AND '3619'
     OR icd9_code BETWEEN '3630' AND '3639'
     OR icd9_code IN ('3751','3752','3753','3754','3755','3760','3763','3764','3765','3766','3768','3961','3962','3966')
  )
),
procedure_events AS (
  SELECT hadm_id, MIN(starttime) AS proc_time
  FROM procedureevents_mv
  WHERE itemid IN (225467,225469,225470)
  GROUP BY hadm_id
),
csru_transfer AS (
  SELECT t.hadm_id, MIN(t.intime) AS csru_time
  FROM transfers t
  JOIN cardiac_surgery_hadm cs ON cs.hadm_id = t.hadm_id
  WHERE t.curr_careunit = 'CSRU'
    AND (t.prev_careunit IS DISTINCT FROM 'CSRU' OR t.prev_careunit IS NULL)
  GROUP BY t.hadm_id
),
cardiac_hadm AS (
  SELECT cs.hadm_id,
         pe.proc_time,
         ct.csru_time,
         COALESCE(pe.proc_time, ct.csru_time) AS anchor_time
  FROM cardiac_surgery_hadm cs
  LEFT JOIN procedure_events pe ON pe.hadm_id = cs.hadm_id
  LEFT JOIN csru_transfer ct ON ct.hadm_id = cs.hadm_id
),
icu_surgery AS (
  SELECT icu.subject_id,
         icu.hadm_id,
         icu.icustay_id,
         icu.intime,
         icu.outtime,
         icu.first_careunit,
         ch.proc_time,
         ch.csru_time,
         COALESCE(ch.anchor_time, icu.intime) AS surgery_time,
         COALESCE(ch.anchor_time, icu.intime) + INTERVAL '30 day' AS surgery_time_end
  FROM icustays icu
  JOIN cardiac_hadm ch ON ch.hadm_id = icu.hadm_id
),
pa_catheter_proc AS (
  SELECT DISTINCT icustay_id FROM procedureevents_mv WHERE itemid = 224560
),
pa_catheter_chart AS (
  SELECT DISTINCT icustay_id
  FROM chartevents
  WHERE itemid IN (491,492,664,8448,220059,220060,220061,225355,225357,225358,225730,225745,225781,226114,227351)
),
pa_catheter_datetime AS (
  SELECT DISTINCT icustay_id
  FROM datetimeevents
  WHERE itemid IN (225351,225352,225353,225354,225356)
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
       isur.surgery_time_end,
       isur.proc_time,
       isur.csru_time,
       CASE
         WHEN isur.proc_time IS NOT NULL THEN 'procedureevents_mv'
         WHEN isur.csru_time IS NOT NULL THEN 'csru_transfer'
         ELSE 'icustay_intime'
       END AS surgery_time_source
FROM icu_surgery isur
JOIN pa_catheter_any pa ON pa.icustay_id = isur.icustay_id;

-- Demographics extract (subject/hadm/icustay level).
DROP TABLE IF EXISTS temp_cardiac_swan_demographics;
CREATE TEMP TABLE temp_cardiac_swan_demographics AS
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.first_careunit,
       c.intime AS icu_intime,
       c.outtime AS icu_outtime,
       c.surgery_time,
       c.surgery_time_source,
       a.admittime,
       a.dischtime,
       a.deathtime,
       a.ethnicity,
       a.hospital_expire_flag,
       p.gender,
       p.dob,
       p.dod,
       FLOOR(EXTRACT(EPOCH FROM (a.admittime - p.dob))/31557600) AS age_years
FROM temp_cardiac_swan_cohort c
JOIN admissions a ON a.hadm_id = c.hadm_id
JOIN patients p ON p.subject_id = c.subject_id;
\copy temp_cardiac_swan_demographics TO 'output/cardiac_swan_demographics.csv' CSV HEADER

-- Surgery ICD-9 catalog for each qualifying admission.
DROP TABLE IF EXISTS temp_cardiac_swan_surgery_icd;
CREATE TEMP TABLE temp_cardiac_swan_surgery_icd AS
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.surgery_time,
       c.surgery_time_source,
       c.proc_time AS or_event_time,
       c.csru_time AS csru_arrival_time,
       pi.seq_num,
       pi.icd9_code,
       dip.short_title,
       dip.long_title
FROM temp_cardiac_swan_cohort c
JOIN procedures_icd pi ON pi.hadm_id = c.hadm_id
JOIN d_icd_procedures dip ON dip.icd9_code = pi.icd9_code;
\copy temp_cardiac_swan_surgery_icd TO 'output/cardiac_swan_surgery_icd.csv' CSV HEADER

-- Blood gases within the day 0–30 window, retaining SPECIMEN TYPE entries.
DROP TABLE IF EXISTS temp_cardiac_swan_blood_gases;
CREATE TEMP TABLE temp_cardiac_swan_blood_gases AS
WITH bloodgas_items AS (
  SELECT itemid, label, fluid, category
  FROM d_labitems
  WHERE category ILIKE 'BLOOD GAS%'
)
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.surgery_time,
       l.charttime,
       l.itemid,
       bi.label AS lab_label,
       bi.fluid AS specimen,
       bi.category,
       l.value,
       l.valuenum,
       l.valueuom,
       l.flag,
       sp.specimen_type
FROM temp_cardiac_swan_cohort c
JOIN labevents l ON l.hadm_id = c.hadm_id
JOIN bloodgas_items bi ON bi.itemid = l.itemid
LEFT JOIN LATERAL (
  SELECT value AS specimen_type
  FROM labevents sp
  WHERE sp.subject_id = l.subject_id
    AND sp.hadm_id = l.hadm_id
    AND sp.charttime = l.charttime
    AND sp.itemid IN (50800, 50801)
  ORDER BY CASE WHEN sp.itemid = 50800 THEN 0 ELSE 1 END
  LIMIT 1
) sp ON TRUE
WHERE l.charttime BETWEEN c.surgery_time AND c.surgery_time_end;
\copy temp_cardiac_swan_blood_gases TO 'output/cardiac_swan_blood_gases.csv' CSV HEADER

-- Swan-Ganz derived measures from chartevents.
DROP TABLE IF EXISTS temp_cardiac_swan_measures;
CREATE TEMP TABLE temp_cardiac_swan_measures AS
WITH swan_items AS (
  SELECT itemid, label
  FROM d_items
  WHERE itemid IN (
    90,116,2135,2136,491,492,664,838,1624,2194,2669,2933,6486,6860,7645,8186,8448,
    220059,220060,220061,220088,223772,224604,224842,226329,226858,227543,227805,228117,228368,228369
  )
)
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.surgery_time,
       ce.charttime,
       ce.storetime,
       ce.itemid,
       si.label,
       ce.value,
       ce.valuenum,
       ce.valueuom
FROM temp_cardiac_swan_cohort c
JOIN chartevents ce ON ce.icustay_id = c.icustay_id
JOIN swan_items si ON si.itemid = ce.itemid
WHERE ce.charttime BETWEEN c.surgery_time AND c.surgery_time_end;
\copy temp_cardiac_swan_measures TO 'output/cardiac_swan_swanmeasures.csv' CSV HEADER

-- Hemoglobin (lab) and temperature (lab + chart) measurements.
DROP TABLE IF EXISTS temp_cardiac_swan_hgb_temp;
CREATE TEMP TABLE temp_cardiac_swan_hgb_temp AS
WITH hgb_lab_items AS (
  SELECT itemid, label
  FROM d_labitems
  WHERE itemid IN (50811, 51222) -- Hgb from blood gas + hematology
),
temp_lab_items AS (
  SELECT itemid, label
  FROM d_labitems
  WHERE itemid IN (50825) -- Blood gas temperature
),
temp_chart_items AS (
  SELECT itemid, label
  FROM d_items
  WHERE itemid IN (676,677,678,679,223761,223762,224027)
)
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.surgery_time,
       l.charttime,
       'hemoglobin' AS measurement,
       'labevents' AS source_table,
       l.itemid,
       hi.label,
       l.value,
       l.valuenum,
       l.valueuom
FROM temp_cardiac_swan_cohort c
JOIN labevents l ON l.hadm_id = c.hadm_id
JOIN hgb_lab_items hi ON hi.itemid = l.itemid
WHERE l.charttime BETWEEN c.surgery_time AND c.surgery_time_end
UNION ALL
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.surgery_time,
       l.charttime,
       'temperature' AS measurement,
       'labevents' AS source_table,
       l.itemid,
       ti.label,
       l.value,
       l.valuenum,
       l.valueuom
FROM temp_cardiac_swan_cohort c
JOIN labevents l ON l.hadm_id = c.hadm_id
JOIN temp_lab_items ti ON ti.itemid = l.itemid
WHERE l.charttime BETWEEN c.surgery_time AND c.surgery_time_end
UNION ALL
SELECT c.subject_id,
       c.hadm_id,
       c.icustay_id,
       c.surgery_time,
       ce.charttime,
       'temperature' AS measurement,
       'chartevents' AS source_table,
       ce.itemid,
       ci.label,
       ce.value,
       ce.valuenum,
       ce.valueuom
FROM temp_cardiac_swan_cohort c
JOIN chartevents ce ON ce.icustay_id = c.icustay_id
JOIN temp_chart_items ci ON ci.itemid = ce.itemid
WHERE ce.charttime BETWEEN c.surgery_time AND c.surgery_time_end;
\copy temp_cardiac_swan_hgb_temp TO 'output/cardiac_swan_hemoglobin_temperature.csv' CSV HEADER
