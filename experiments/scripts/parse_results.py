#!/usr/bin/env python3

"""Parse raw llama.cpp benchmark artifacts into results/processed/benchmark-results.csv."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from statistics import mean


CSV_COLUMNS = [
    "experiment_id",
    "date",
    "hardware",
    "backend",
    "model",
    "workload",
    "context_length",
    "prompt_tokens",
    "generated_tokens",
    "prompt_eval_tps",
    "decode_tps",
    "time_to_first_token",
    "total_time",
    "ram_usage",
    "vram_usage",
    "gpu_power",
    "gpu_temperature",
    "status",
]


PROMPT_RE = re.compile(
    r"prompt eval time\s*=\s*([0-9.]+)\s*ms\s*/\s*(\d+)\s*tokens\s*\(\s*([0-9.]+)\s*tokens per second",
    re.IGNORECASE,
)
EVAL_RE = re.compile(
    r"^\s*eval time\s*=\s*([0-9.]+)\s*ms\s*/\s*(\d+)\s*tokens\s*\(\s*([0-9.]+)\s*tokens per second",
    re.IGNORECASE | re.MULTILINE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=str(Path.home() / "llm-research"))
    return parser.parse_args()


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def parse_perf(result_path: Path) -> dict:
    try:
        text = result_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""

    prompt_match = PROMPT_RE.search(text)
    eval_match = EVAL_RE.search(text)

    return {
        "prompt_eval_time_ms": prompt_match.group(1) if prompt_match else "",
        "prompt_tokens": prompt_match.group(2) if prompt_match else "",
        "prompt_eval_tps": prompt_match.group(3) if prompt_match else "",
        "eval_time_ms": eval_match.group(1) if eval_match else "",
        "generated_tokens": eval_match.group(2) if eval_match else "",
        "decode_tps": eval_match.group(3) if eval_match else "",
    }


def numeric_values(csv_path: Path, column: str) -> list[float]:
    if not csv_path.exists():
        return []
    values: list[float] = []
    try:
        with csv_path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                raw = (row.get(column) or "").strip()
                if not raw:
                    continue
                try:
                    values.append(float(raw))
                except ValueError:
                    continue
    except OSError:
        return []
    return values


def max_value(csv_path: Path, column: str) -> str:
    values = numeric_values(csv_path, column)
    if not values:
        return ""
    return f"{max(values):.3f}"


def avg_value(csv_path: Path, column: str) -> str:
    values = numeric_values(csv_path, column)
    if not values:
        return ""
    return f"{mean(values):.3f}"


def build_row(run_dir: Path) -> dict:
    metadata = read_json(run_dir / "metadata.json")
    perf = parse_perf(run_dir / "result.txt")

    return {
        "experiment_id": metadata.get("experiment_id", run_dir.name),
        "date": metadata.get("date", ""),
        "hardware": metadata.get("hardware", ""),
        "backend": metadata.get("backend", ""),
        "model": metadata.get("model_label") or metadata.get("model_filename", ""),
        "workload": metadata.get("workload", ""),
        "context_length": metadata.get("context_length", ""),
        "prompt_tokens": perf["prompt_tokens"],
        "generated_tokens": perf["generated_tokens"],
        "prompt_eval_tps": perf["prompt_eval_tps"],
        "decode_tps": perf["decode_tps"],
        "time_to_first_token": metadata.get("time_to_first_token", ""),
        "total_time": metadata.get("total_time", ""),
        "ram_usage": max_value(run_dir / "system-monitor.csv", "ram_used_mb"),
        "vram_usage": max_value(run_dir / "gpu-monitor.csv", "memory_used_mb"),
        "gpu_power": avg_value(run_dir / "gpu-monitor.csv", "power_w"),
        "gpu_temperature": avg_value(run_dir / "gpu-monitor.csv", "temperature_c"),
        "status": metadata.get("status", ""),
    }


def main() -> int:
    args = parse_args()
    base = Path(args.base).expanduser()
    raw_root = base / "results" / "raw"
    processed = base / "results" / "processed"
    output = processed / "benchmark-results.csv"

    rows = []
    for metadata_path in sorted(raw_root.glob("*/*/*/*/run*/metadata.json")):
        rows.append(build_row(metadata_path.parent))

    processed.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
