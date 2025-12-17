SET search_path TO mimiciii;

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
surgery_services AS (
  SELECT hadm_id, MIN(transfertime) AS surgery_time
  FROM services
  WHERE curr_service LIKE 'CSURG%'
  GROUP BY hadm_id
),
cardiac_hadm AS (
  SELECT cs.hadm_id,
         ss.surgery_time
  FROM cardiac_surgery_hadm cs
  LEFT JOIN surgery_services ss ON ss.hadm_id = cs.hadm_id
),
icu_surgery AS (
  SELECT icu.subject_id,
         icu.hadm_id,
         icu.icustay_id,
         icu.intime,
         icu.outtime,
         icu.first_careunit,
         COALESCE(ch.surgery_time, icu.intime) AS surgery_time,
         COALESCE(ch.surgery_time, icu.intime) + INTERVAL '30 day' AS surgery_time_end
  FROM icustays icu
  JOIN cardiac_hadm ch ON ch.hadm_id = icu.hadm_id
),
pa_catheter_proc AS (
  SELECT DISTINCT pe.icustay_id
  FROM procedureevents_mv pe
  JOIN icu_surgery isur ON isur.icustay_id = pe.icustay_id
  WHERE pe.itemid = 224560
    AND pe.starttime >= isur.surgery_time
    AND pe.starttime <= isur.surgery_time_end
),
pa_catheter_chart AS (
  SELECT DISTINCT ce.icustay_id
  FROM chartevents ce
  JOIN icu_surgery isur ON isur.icustay_id = ce.icustay_id
  WHERE ce.itemid IN (491,492,664,8448,220059,220060,220061,225355,225357,225358,225730,225745,225781,226114,227351)
    AND ce.charttime >= isur.surgery_time
    AND ce.charttime <= isur.surgery_time_end
),
pa_catheter_datetime AS (
  SELECT DISTINCT de.icustay_id
  FROM datetimeevents de
  JOIN icu_surgery isur ON isur.icustay_id = de.icustay_id
  WHERE de.itemid IN (225351,225352,225353,225354,225356)
    AND de.charttime >= isur.surgery_time
    AND de.charttime <= isur.surgery_time_end
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
