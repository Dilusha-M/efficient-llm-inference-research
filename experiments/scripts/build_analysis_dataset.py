#!/usr/bin/env python3
"""Build the combined benchmark and manual-quality analysis datasets."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path

QUALITY_COLUMNS = ["hardware", "model", "workload", "accuracy", "completeness", "correctness", "usefulness", "overall_score", "comments"]
QUALITY_SOURCE_COLUMNS = {"Model": "model", "Workload": "workload", "Accuracy": "accuracy", "Completeness": "completeness", "Correctness": "correctness", "Usefulness": "usefulness", "Overall Score": "overall_score", "Notes": "comments"}
MERGE_KEYS = ("hardware", "model", "workload")


def clean(value: str | None) -> str:
    return (value or "").strip()


def key_for(row: dict[str, str]) -> tuple[str, str, str]:
    return tuple(clean(row.get(column)) for column in MERGE_KEYS)


def duplicate_keys(rows: list[dict[str, str]]) -> list[tuple[tuple[str, str, str], int]]:
    counts = Counter(key_for(row) for row in rows)
    return sorted((key, count) for key, count in counts.items() if count > 1)


def read_csv(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no header: {path}")
        return list(reader), reader.fieldnames


def load_quality(quality_root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    paths = sorted(quality_root.rglob("quality_evaluation.csv"))
    if not paths:
        raise FileNotFoundError(f"No quality_evaluation.csv files found under {quality_root}")
    required = set(QUALITY_SOURCE_COLUMNS)
    for path in paths:
        source_rows, fieldnames = read_csv(path)
        missing = required.difference(fieldnames)
        if missing:
            raise ValueError(f"{path} is missing quality columns: {', '.join(sorted(missing))}")
        for source_row in source_rows:
            row = {column: "" for column in QUALITY_COLUMNS}
            row["hardware"] = path.parent.name
            for source_column, target_column in QUALITY_SOURCE_COLUMNS.items():
                row[target_column] = clean(source_row[source_column])
            rows.append(row)
    return rows


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def print_duplicate_keys(label: str, rows: list[dict[str, str]]) -> list[tuple[tuple[str, str, str], int]]:
    duplicates = duplicate_keys(rows)
    print(f"{label} duplicate keys: {len(duplicates)}")
    for key, count in duplicates:
        print(f"  {key}: {count} rows")
    return duplicates


def build_dataset(root: Path) -> None:
    benchmark_path = root / "results" / "processed" / "benchmark-results.csv"
    quality_root = root / "results" / "quality"
    processed_root = root / "results" / "processed"
    benchmark_rows, benchmark_columns = read_csv(benchmark_path)
    quality_rows = load_quality(quality_root)
    print(f"Benchmark rows: {len(benchmark_rows)}")
    print(f"Quality rows: {len(quality_rows)}")
    print_duplicate_keys("Benchmark", benchmark_rows)
    quality_duplicates = print_duplicate_keys("Quality", quality_rows)
    quality_by_key = {key_for(row): row for row in quality_rows}
    unmatched = [row for row in benchmark_rows if key_for(row) not in quality_by_key]
    print(f"Unmatched benchmark rows: {len(unmatched)}")
    if quality_duplicates:
        raise ValueError("Quality data contains duplicate merge keys; merge would be ambiguous")
    write_csv(processed_root / "quality-results.csv", quality_rows, QUALITY_COLUMNS)
    final_columns = benchmark_columns + [c for c in QUALITY_COLUMNS if c not in benchmark_columns]
    final_rows = []
    for benchmark_row in benchmark_rows:
        merged = dict(benchmark_row)
        merged.update(quality_by_key.get(key_for(benchmark_row), {}))
        final_rows.append(merged)
    write_csv(processed_root / "final-analysis-dataset.csv", final_rows, final_columns)
    print(f"Wrote quality dataset: {processed_root / 'quality-results.csv'}")
    print(f"Wrote final analysis dataset: {processed_root / 'final-analysis-dataset.csv'}")
    print(f"Final analysis rows: {len(final_rows)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2], help="Repository root")
    return parser.parse_args()


if __name__ == "__main__":
    build_dataset(parse_args().root.resolve())
