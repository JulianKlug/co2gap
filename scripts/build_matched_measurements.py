#!/usr/bin/env python3
"""Build matched measurement panels using cardiac output timestamps as anchors."""
from __future__ import annotations
import argparse
import csv
from bisect import bisect_left
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

DATA_DIR = Path('output')
BLOOD_GAS_FILE = DATA_DIR / 'cardiac_swan_blood_gases.csv'
HGB_TEMP_FILE = DATA_DIR / 'cardiac_swan_hemoglobin_temperature.csv'
SWAN_FILE = DATA_DIR / 'cardiac_swan_swanmeasures.csv'
OUT_FILE = DATA_DIR / 'cardiac_swan_matched_measurements.csv'

ARTERIAL_ITEMS = {50817: 'arterial_sat', 50818: 'arterial_pco2', 50820: 'arterial_ph'}
CENTRAL_ITEMS = {50817: 'central_sat', 50818: 'central_pco2'}
HGB_ITEMIDS = {50811, 51222}
TEMP_CHART_ITEMIDS = {223761, 223762, 224027, 676, 677, 678, 679}
CO_ITEMIDS = {2136, 220088, 224604, 224842, 227543, 228117, 228369}
CI_ITEMIDS = {90, 116, 2135, 224368, 228368}


def parse_dt(value: str) -> datetime:
    return datetime.strptime(value, '%Y-%m-%d %H:%M:%S')


def parse_float(value: str) -> Optional[float]:
    if value in ('', None):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def normalize_int(value: str) -> int:
    return int(value) if value not in (None, '', 'nan') else -1


def build_anchor_entries(args) -> List[Dict]:
    anchors: List[Dict] = []
    with SWAN_FILE.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            itemid = int(row['itemid'])
            if itemid not in CO_ITEMIDS:
                continue
            subject_id = normalize_int(row['subject_id'])
            hadm_id = normalize_int(row['hadm_id'])
            icustay_id = normalize_int(row['icustay_id'])
            charttime = parse_dt(row['charttime'])
            anchors.append({
                'anchor_type': 'cardiac_output',
                'subject_id': subject_id,
                'hadm_id': hadm_id,
                'icustay_id': icustay_id,
                'anchor_time': charttime,
                'cardiac_output_value': parse_float(row.get('valuenum', '')),
                'cardiac_output_unit': row.get('valueuom', ''),
                'cardiac_output_label': row.get('label', ''),
                'cardiac_output_source': 'chartevents',
                'cardiac_output_time': charttime.strftime('%Y-%m-%d %H:%M:%S'),
                'cardiac_output_delta_minutes': 0.0
            })
    anchors.sort(key=lambda r: (r['subject_id'], r['hadm_id'], r['icustay_id'], r['anchor_time']))
    return anchors

@dataclass
class MeasurementSeries:
    times: List[datetime]
    records: List[Dict]


def build_series_from_rows(rows: Iterable[Dict]) -> Dict[Tuple[int, int, int], MeasurementSeries]:
    series: Dict[Tuple[int, int, int], MeasurementSeries] = defaultdict(lambda: MeasurementSeries([], []))
    for rec in rows:
        key = (rec.pop('subject_id'), rec.pop('hadm_id'), rec.pop('icustay_id'))
        bucket = series[key]
        bucket.times.append(rec['time'])
        bucket.records.append(rec)
    for bucket in series.values():
        combined = sorted(zip(bucket.times, bucket.records), key=lambda x: x[0])
        if combined:
            bucket.times, bucket.records = map(list, zip(*combined))
    return series


def load_bloodgas_series(prefixes: List[str], mapping: Dict[int, str]) -> Dict[str, Dict[Tuple[int, int, int], MeasurementSeries]]:
    series_map: Dict[str, Dict[Tuple[int, int, int], MeasurementSeries]] = {name: defaultdict(lambda: MeasurementSeries([], [])) for name in mapping.values()}
    with BLOOD_GAS_FILE.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            spec = (row.get('specimen_type') or '').upper()
            if not any(spec.startswith(pref) for pref in prefixes):
                continue
            itemid = int(row['itemid'])
            if itemid not in mapping:
                continue
            meas_name = mapping[itemid]
            record = {
                'subject_id': normalize_int(row['subject_id']),
                'hadm_id': normalize_int(row['hadm_id']),
                'icustay_id': normalize_int(row['icustay_id']),
                'time': parse_dt(row['charttime']),
                'value': parse_float(row.get('valuenum', '')),
                'unit': row.get('valueuom', ''),
                'label': row.get('lab_label', ''),
                'source': 'labevents'
            }
            key = (record.pop('subject_id'), record.pop('hadm_id'), record.pop('icustay_id'))
            bucket = series_map[meas_name].setdefault(key, MeasurementSeries([], []))
            bucket.times.append(record['time'])
            bucket.records.append(record)
    for series in series_map.values():
        for bucket in series.values():
            combined = sorted(zip(bucket.times, bucket.records), key=lambda x: x[0])
            if combined:
                bucket.times, bucket.records = map(list, zip(*combined))
    return series_map


def nearest_record(series: Dict[Tuple[int, int, int], MeasurementSeries], key, target: datetime, tolerance: timedelta):
    bucket = series.get(key)
    if not bucket or not bucket.times:
        return None
    idx = bisect_left(bucket.times, target)
    best = None
    best_delta = None
    for cand in (idx - 1, idx):
        if 0 <= cand < len(bucket.times):
            t = bucket.times[cand]
            delta = abs((t - target).total_seconds())
            if best_delta is None or delta < best_delta:
                best_delta = delta
                best = bucket.records[cand]
    if best is None or best_delta is None or best_delta > tolerance.total_seconds():
        return None
    result = best.copy()
    result['delta_minutes'] = best_delta / 60.0
    return result


def append_measurement(row: Dict, name: str, record: Optional[Dict]):
    row[f'{name}_value'] = record['value'] if record else ''
    row[f'{name}_unit'] = record['unit'] if record else ''
    row[f'{name}_label'] = record.get('label', '') if record else ''
    row[f'{name}_source'] = record.get('source', '') if record else ''
    row[f'{name}_time'] = record['time'].strftime('%Y-%m-%d %H:%M:%S') if record and isinstance(record.get('time'), datetime) else ''
    row[f'{name}_delta_minutes'] = round(record['delta_minutes'], 3) if record else ''


def build_rows(args):
    anchors = build_anchor_entries(args)

    art_prefixes = ['ART']
    central_prefixes = ['CENTRAL']
    if args.include_venous:
        central_prefixes.append('VEN')
    arterial_series = load_bloodgas_series(art_prefixes, ARTERIAL_ITEMS)
    central_series = load_bloodgas_series(central_prefixes, CENTRAL_ITEMS)

    def load_htemp(filter_fn):
        records = []
        with HGB_TEMP_FILE.open() as f:
            reader = csv.DictReader(f)
            for row in reader:
                record = filter_fn(row)
                if record is not None:
                    records.append(record)
        return build_series_from_rows(records)

    def hgb_filter(row):
        if row['measurement'].lower() != 'hemoglobin':
            return None
        return {
            'subject_id': normalize_int(row['subject_id']),
            'hadm_id': normalize_int(row['hadm_id']),
            'icustay_id': normalize_int(row['icustay_id']),
            'time': parse_dt(row['charttime']),
            'value': parse_float(row.get('valuenum', '')),
            'unit': row.get('valueuom', ''),
            'label': row.get('label', ''),
            'source': row.get('source_table', '')
        }

    def temp_filter(row):
        if row['measurement'].lower() != 'temperature':
            return None
        return {
            'subject_id': normalize_int(row['subject_id']),
            'hadm_id': normalize_int(row['hadm_id']),
            'icustay_id': normalize_int(row['icustay_id']),
            'time': parse_dt(row['charttime']),
            'value': parse_float(row.get('valuenum', '')),
            'unit': row.get('valueuom', ''),
            'label': row.get('label', ''),
            'source': row.get('source_table', '')
        }

    hgb_series = load_htemp(hgb_filter)
    temp_series = load_htemp(temp_filter)

    def load_swan(valid_ids):
        rows = []
        with SWAN_FILE.open() as f:
            reader = csv.DictReader(f)
            for row in reader:
                itemid = int(row['itemid'])
                if itemid not in valid_ids:
                    continue
                rows.append({
                    'subject_id': normalize_int(row['subject_id']),
                    'hadm_id': normalize_int(row['hadm_id']),
                    'icustay_id': normalize_int(row['icustay_id']),
                    'time': parse_dt(row['charttime']),
                    'value': parse_float(row.get('valuenum', '')),
                    'unit': row.get('valueuom', ''),
                    'label': row.get('label', ''),
                    'source': 'chartevents'
                })
        return build_series_from_rows(rows)

    ci_series = load_swan(CI_ITEMIDS)

    rows = []
    for anchor in anchors:
        key = (anchor['subject_id'], anchor['hadm_id'], anchor['icustay_id'])
        anchor_time = anchor['anchor_time']
        row = anchor.copy()
        row['anchor_time'] = anchor_time.strftime('%Y-%m-%d %H:%M:%S')

        for meas_name, series_dict, tol in [
            ('arterial_sat', arterial_series['arterial_sat'], args.bloodgas_window),
            ('arterial_pco2', arterial_series['arterial_pco2'], args.bloodgas_window),
            ('arterial_ph', arterial_series['arterial_ph'], args.bloodgas_window),
            ('central_sat', central_series['central_sat'], args.bloodgas_window),
            ('central_pco2', central_series['central_pco2'], args.bloodgas_window)
        ]:
            record = nearest_record(series_dict, key, anchor_time, tol)
            append_measurement(row, meas_name, record)

        for meas_name, series_dict, tol in [
            ('hemoglobin', hgb_series, args.hemoglobin_window),
            ('temperature', temp_series, args.temperature_window),
            ('cardiac_index', ci_series, args.cardiac_index_window)
        ]:
            record = nearest_record(series_dict, key, anchor_time, tol)
            append_measurement(row, meas_name, record)

        rows.append(row)

    if not rows:
        raise SystemExit('No anchors found.')

    fieldnames = list(rows[0].keys())
    with OUT_FILE.open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f'Wrote {len(rows):,} rows to {OUT_FILE}')


def parse_args():
    parser = argparse.ArgumentParser(description='Match labs/hemodynamics around cardiac output measurements.')
    parser.add_argument('--bloodgas-window-min', type=float, default=15, help='Tolerance (minutes) for arterial/central blood gas matching (default: 15).')
    parser.add_argument('--hemoglobin-window-min', type=float, default=720, help='Tolerance (minutes) for hemoglobin labs (default: 720).')
    parser.add_argument('--temperature-window-min', type=float, default=30, help='Tolerance (minutes) for temperature readings (default: 30).')
    parser.add_argument('--cardiac-index-window-min', type=float, default=15, help='Tolerance (minutes) for cardiac index values (default: 15).')
    parser.add_argument('--include-venous', action='store_true', default=True, help='Include VEN specimen types when matching arterial values (default: enabled). To disable, pass --no-include-venous.')
    parser.add_argument('--no-include-venous', dest='include_venous', action='store_false')
    return parser.parse_args()


def main():
    args = parse_args()
    args.bloodgas_window = timedelta(minutes=args.bloodgas_window_min)
    args.hemoglobin_window = timedelta(minutes=args.hemoglobin_window_min)
    args.temperature_window = timedelta(minutes=args.temperature_window_min)
    args.cardiac_index_window = timedelta(minutes=args.cardiac_index_window_min)
    build_rows(args)


if __name__ == '__main__':
    main()
