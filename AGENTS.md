## Project overview

Goal:
- extract a cohort of patients admitted after cardiac surgery and having a swan-ganz catheter (pulmonary artery catheter) in place.
- then extract following data for these patients: demographics, surgery information (type, date, ...), all blood gas values along with their timings and SPECIMEN type, all measures derived from the swan-ganz catheters (especially cardiac output). all data should be timed, and attributed to a specific patient id and admission id
- save this data into csv files
- data should then be preprocessed to match general lab values (hemoglobin) with values from an arterial blood gas (arterial saturation, arterial CO2, arterial pH), from a central venous blood gas (central venous saturation, central venous CO2), values obtained from swan-ganz monitoring (cardiac output, cardiac index), and monitoring values (temperature). Values from the same patient will be considered as matched based on pre-specified time delta values
- the preprocessed data should be saved in a single CSV  

Extraction Steps:
- locate mimic database
- build database (postgres)
- identify selection criteria to be able to select patients after cardiac surgery
- identify selection citeria to be able to select patients with a swan-ganz catheter in place
- extract demographics
- extract surgery information 
- extract all blood gas values (along with date time and specimen)
- extract all swan-ganz catheter values (especially cardiac output, along with date time)
- extract all temperature values
- extract all hemoglobin values 

Preprocessing steps
- language: python
- define delta-time variables for blood gases (default 15min), lab values (default 12h), monitoring values (default 60min). Reference time is the timing of the cardiac output / cardiac index
- extract matching values for lab values (hemoglobin), values from an arterial blood gas (arterial saturation, arterial CO2, arterial pH), from a central venous blood gas (central venous saturation, central venous CO2), values obtained from swan-ganz monitoring (cardiac output, cardiac index), and monitoring values (temperature) based on matching patient id and time steps (with respect to the prespecified time deltas). Time and origin of each extracted value should be also extracted
- save matching data in a single dataframe 

path to mimic data: /mnt/hdd1/datasets/mimiciii_1.4
! the data should not be modified !

## Repository expectations

- always use the conda environment co2gap
- at the end of every work step, summarize progress in the progess.md file, it should be continuously updated 
- no data or files outside of this folder should be modified

