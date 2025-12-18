## Project overview

Goal:
- extract a cohort of patients admitted after cardiac surgery and having a swan-ganz catheter (pulmonary artery catheter) in place.
- then extract following data for these patients: demographics, surgery information (type, date, ...), all blood gas values along with their timings and SPECIMEN type, all measures derived from the swan-ganz catheters (especially cardiac output). all data should be timed, and attributed to a specific patient id and admission id
- save this data into csv files

Steps:
- locate mimic database
- build database (postgres)
- identify selection criteria to be able to select patients after cardiac surgery
- identify selection citeria to be able to select patients with a swan-ganz catheter in place
- extract demographics
- extract surgery information 
- extract all blood gas values (along with date time and specimen)
- extract all swan-ganz catheter values (especially cardiac output, along with date time)

path to mimic data: /mnt/hdd1/datasets/mimiciii_1.4
! the data should not be modified !

## Repository expectations

- always use the conda environment co2gap
- at the end of every work step, summarize progress in the progess.md file, it should be continuously updated 
- no data or files outside of this folder should be modified

