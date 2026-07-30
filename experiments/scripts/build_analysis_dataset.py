#!/usr/bin/env python3
"""Build the combined benchmark and manual-quality analysis datasets."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path

QUALITY_COLUMNS = [
    "hardware", "model", "workload", "accuracy", "completeness",
    "correctness", "usefulness", "overall_score", "comments",
]
QUALITY_SOURCE_COLUMNS = {
    "Model": "model", "Workload": "workload", "Accuracy": "accuracy",
    "Completeness": "completeness", "Correctness": "correctness",
    "Usefulness": "usefulness", "Overall Score": "overall_score",
    "Notes": "comments",
}
MERGE_KEYS = ("hardware", "model", "workload")
DERIVED_COLUMNS = ["experiment_category", "model_size_b", "architecture", "quantization"]

# Includes both the canonical names from the analysis specification and the
# model names currently used in benchmark-results.csv.
MODEL_METADATA = {
    "Qwen3.5-0.8B": {"model_size_b": "0.8", "architecture": "dense", "quantization": "Q8_0"},
    "Qwen3.5-2B": {"model_size_b": "2", "architecture": "dense", "quantization": "Q4_K_M"},
    "Qwen3.5-4B": {"model_size_b": "4", "architecture": "dense", "quantization": "Q4_K_M"},
    "Qwen3.5-9B": {"model_size_b": "9", "architecture": "dense", "quantization": "Q4_K_M"},
    "Qwen3.6-27B": {"model_size_b": "27", "architecture": "dense", "quantization": "Q4_K_M"},
    "Qwen3.6-35B-A3B": {"model_size_b": "35", "architecture": "MoE", "quantization": "Q4_K_M"},
    "Gemma4-E2B": {"model_size_b": "2", "architecture": "MoE", "quantization": "Q4_K_M"},
    "gemma-4-E2B-it": {"model_size_b": "2", "architecture": "MoE", "quantization": "Q4_K_M"},
    "Gemma4-12B": {"model_size_b": "12", "architecture": "dense", "quantization": "Q4_0"},
    "gemma-4-12B-it-QAT": {"model_size_b": "12", "architecture": "dense", "quantization": "Q4_0"},
    "Gemma4-26B-A4B": {"model_size_b": "26", "architecture": "MoE", "quantization": "Q4_K_M"},
    "gemma-4-26B-A4B-it": {"model_size_b": "26", "architecture": "MoE", "quantization": "Q4_K_M"},
}


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


def numeric_value(value: str | None) -> float | None:
    try:
        return float(clean(value))
    except ValueError:
        return None


def classify_experiment(row: dict[str, str]) -> str:
    backend = clean(row.get("backend")).lower()
    gpu_layers = numeric_value(row.get("gpu_layers"))
    n_cpu_moe = numeric_value(row.get("n_cpu_moe"))
    offload_type = clean(row.get("offload_type")).lower()

    # MoE classification takes precedence when CPU experts are offloaded.
    if n_cpu_moe is not None and n_cpu_moe > 0:
        return "gpu_moe_offload"
    if "moe" in offload_type or "expert" in offload_type:
        return "gpu_moe_offload"
    if backend == "cpu" and (gpu_layers is None or gpu_layers == 0) and offload_type in {"", "none"}:
        return "cpu_only"
    if backend == "cuda" and gpu_layers == 999:
        return "gpu_full_offload"
    if backend == "cuda" and gpu_layers is not None and 0 < gpu_layers < 999:
        return "gpu_partial_offload"
    return "unknown"


def add_derived_columns(rows: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[str]]:
    missing_metadata = sorted({
        clean(row.get("model"))
        for row in rows
        if clean(row.get("model")) not in MODEL_METADATA
    })
    derived_rows = []
    for row in rows:
        metadata = MODEL_METADATA.get(clean(row.get("model")), {})
        derived = dict(row)
        derived["experiment_category"] = classify_experiment(row)
        for column in DERIVED_COLUMNS[1:]:
            derived[column] = metadata.get(column, "")
        derived_rows.append(derived)
    return derived_rows, missing_metadata


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
    derived_rows, missing_metadata = add_derived_columns(benchmark_rows)
    print("Experiment category distribution:")
    for category, count in sorted(Counter(row["experiment_category"] for row in derived_rows).items()):
        print(f"  {category}: {count}")
    print(f"Models missing metadata: {len(missing_metadata)}")
    for model in missing_metadata:
        print(f"  {model}")

    # The benchmark columns and values are copied unchanged; derived and
    # quality columns are appended to the final analysis dataset.
    final_columns = benchmark_columns + DERIVED_COLUMNS + [
        column for column in QUALITY_COLUMNS if column not in benchmark_columns
    ]
    final_rows = []
    for derived_row in derived_rows:
        merged = dict(derived_row)
        merged.update(quality_by_key.get(key_for(merged), {}))
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
