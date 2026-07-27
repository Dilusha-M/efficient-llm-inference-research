#!/usr/bin/env python3

"""Parse raw llama.cpp benchmark artifacts into results/processed/benchmark-results.csv."""

from __future__ import annotations

import argparse
import csv
import json
import re
from datetime import datetime, timezone
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
    "model_load_time",
    "total_time",
    "ram_usage",
    "vram_usage",
    "gpu_power",
    "gpu_temperature",
    "status",
]


NUMBER = r"[+-]?(?:\d[\d,]*\.?\d*|\.\d+)"

# Match field names rather than a specific llama.cpp summary prefix. This
# supports both llama_print_timings and llama_perf_context_print output.
PROMPT_TIME_RE = re.compile(rf"\bprompt eval time\s*=\s*({NUMBER})\s*ms", re.IGNORECASE | re.MULTILINE)
PROMPT_TOKENS_RE = re.compile(rf"\bprompt eval tokens\s*=\s*({NUMBER})\s*tokens?", re.IGNORECASE | re.MULTILINE)
PROMPT_RATE_RE = re.compile(rf"\bprompt eval rate\s*=\s*({NUMBER})", re.IGNORECASE | re.MULTILINE)
EVAL_TIME_RE = re.compile(rf"(?<!prompt )\beval time\s*=\s*({NUMBER})\s*ms", re.IGNORECASE | re.MULTILINE)
EVAL_TOKENS_RE = re.compile(rf"(?<!prompt )\beval tokens\s*=\s*({NUMBER})\s*tokens?", re.IGNORECASE | re.MULTILINE)
EVAL_RATE_RE = re.compile(rf"(?<!prompt )\beval rate\s*=\s*({NUMBER})", re.IGNORECASE | re.MULTILINE)
LOAD_RE = re.compile(rf"\bload time\s*=\s*({NUMBER})\s*ms", re.IGNORECASE | re.MULTILINE)
SIMPLE_TIMING_RE = re.compile(rf"\[\s*Prompt:\s*({NUMBER})\s*t/s\s*\|\s*Generation:\s*({NUMBER})\s*t/s\s*\]", re.IGNORECASE)

# Older llama.cpp versions put time, token count, and rate on one line.
PROMPT_COMBINED_RE = re.compile(
    rf"prompt eval time\s*=\s*({NUMBER})\s*ms\s*/\s*({NUMBER})\s*tokens?\s*\(\s*({NUMBER})",
    re.IGNORECASE,
)
EVAL_COMBINED_RE = re.compile(
    rf"^\s*eval time\s*=\s*({NUMBER})\s*ms\s*/\s*({NUMBER})\s*(?:tokens?|runs?)\s*\(\s*({NUMBER})",
    re.IGNORECASE | re.MULTILINE,
)

PERF_CONTEXT_RE = {
    "prompt_tokens": re.compile(rf"\bn_p_eval\s*=\s*({NUMBER})", re.IGNORECASE),
    "generated_tokens": re.compile(rf"\bn_d_eval\s*=\s*({NUMBER})", re.IGNORECASE),
    "prompt_time_ms": re.compile(rf"\bt_p_eval_ms\s*=\s*({NUMBER})", re.IGNORECASE),
    "decode_time_ms": re.compile(rf"\bt_d_eval_ms\s*=\s*({NUMBER})", re.IGNORECASE),
}


def normalized_number(value: str) -> str:
    """Return a CSV-safe numeric string, including for values with commas."""
    return str(float(value.replace(",", "")))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=str(Path.home() / "llm-research"))
    parser.add_argument("--output", default=None, help="CSV output path. Defaults to results/processed/benchmark-results.csv.")
    parser.add_argument("--overwrite", action="store_true", help="Replace an existing output CSV.")
    parser.add_argument("--debug", action="store_true", help="Print raw timing lines and parser matches for each result.txt.")
    return parser.parse_args()


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def parse_perf(result_path: Path, debug: bool = False) -> dict:
    try:
        text = result_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""

    prompt_time_match = PROMPT_TIME_RE.search(text)
    prompt_tokens_match = PROMPT_TOKENS_RE.search(text)
    prompt_rate_match = PROMPT_RATE_RE.search(text)
    eval_time_match = EVAL_TIME_RE.search(text)
    eval_tokens_match = EVAL_TOKENS_RE.search(text)
    eval_rate_match = EVAL_RATE_RE.search(text)
    load_match = LOAD_RE.search(text)
    simple_timing_match = SIMPLE_TIMING_RE.search(text)

    prompt_combined = PROMPT_COMBINED_RE.search(text)
    eval_combined = EVAL_COMBINED_RE.search(text)
    context_matches = {key: pattern.search(text) for key, pattern in PERF_CONTEXT_RE.items()}

    prompt_time = prompt_time_match.group(1) if prompt_time_match else prompt_combined.group(1) if prompt_combined else ""
    prompt_tokens = prompt_tokens_match.group(1) if prompt_tokens_match else prompt_combined.group(2) if prompt_combined else ""
    prompt_rate = prompt_rate_match.group(1) if prompt_rate_match else prompt_combined.group(3) if prompt_combined else ""
    eval_time = eval_time_match.group(1) if eval_time_match else eval_combined.group(1) if eval_combined else ""
    eval_tokens = eval_tokens_match.group(1) if eval_tokens_match else eval_combined.group(2) if eval_combined else ""
    eval_rate = eval_rate_match.group(1) if eval_rate_match else eval_combined.group(3) if eval_combined else ""
    if simple_timing_match:
        prompt_rate = prompt_rate or simple_timing_match.group(1)
        eval_rate = eval_rate or simple_timing_match.group(2)

    context_prompt_tokens = context_matches["prompt_tokens"].group(1) if context_matches["prompt_tokens"] else ""
    context_generated_tokens = context_matches["generated_tokens"].group(1) if context_matches["generated_tokens"] else ""
    context_prompt_time = context_matches["prompt_time_ms"].group(1) if context_matches["prompt_time_ms"] else ""
    context_decode_time = context_matches["decode_time_ms"].group(1) if context_matches["decode_time_ms"] else ""
    prompt_tokens = prompt_tokens or context_prompt_tokens
    eval_tokens = eval_tokens or context_generated_tokens
    if not prompt_rate and context_prompt_tokens and context_prompt_time:
        prompt_rate = str(float(context_prompt_tokens.replace(",", "")) * 1000 / float(context_prompt_time.replace(",", "")))
    if not eval_rate and context_generated_tokens and context_decode_time:
        eval_rate = str(float(context_generated_tokens.replace(",", "")) * 1000 / float(context_decode_time.replace(",", "")))

    if debug:
        print(f"[parse-debug] {result_path}")
        for line in text.splitlines():
            if re.search(r"llama_print_timings|llama_perf_context_print|load time|prompt eval|eval time|tokens/sec|tok/s|n_p_eval|n_d_eval|t_p_eval_ms|t_d_eval_ms", line, re.IGNORECASE):
                print(f"[parse-debug] raw: {line}")
        print("[parse-debug] matched: "
              f"prompt_eval_tps={prompt_rate or '<empty>'}, "
              f"decode_tps={eval_rate or '<empty>'}, "
              f"prompt_tokens={prompt_tokens or '<empty>'}, "
              f"generated_tokens={eval_tokens or '<empty>'}")

    return {
        "prompt_eval_time_ms": normalized_number(prompt_time) if prompt_time else "",
        "prompt_tokens": normalized_number(prompt_tokens) if prompt_tokens else "",
        "prompt_eval_tps": normalized_number(prompt_rate) if prompt_rate else "",
        "eval_time_ms": normalized_number(eval_time) if eval_time else "",
        "generated_tokens": normalized_number(eval_tokens) if eval_tokens else "",
        "decode_tps": normalized_number(eval_rate) if eval_rate else "",
        "model_load_time": f"{float(load_match.group(1).replace(',', '')) / 1000:.3f}" if load_match else "",
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


def metadata_value(metadata: dict, key: str) -> str:
    value = metadata.get(key, "")
    if value is None:
        return ""
    return str(value)


def output_path(base: Path, requested: str | None, overwrite: bool) -> Path:
    default_output = base / "results" / "processed" / "benchmark-results.csv"
    output = Path(requested).expanduser() if requested else default_output
    if not output.is_absolute():
        output = base / output
    if output.exists() and not overwrite:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        return output.with_name(f"{output.stem}-{stamp}{output.suffix}")
    return output


def build_row(run_dir: Path, debug: bool = False) -> dict:
    metadata = read_json(run_dir / "metadata.json")
    perf = parse_perf(run_dir / "result.txt", debug=debug)

    # TTFT requires streaming token timestamps and is not available from llama.cpp perf summary.
    time_to_first_token = metadata_value(metadata, "time_to_first_token")

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
        "time_to_first_token": time_to_first_token,
        "model_load_time": metadata_value(metadata, "model_load_time") or perf["model_load_time"],
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
    output = output_path(base, args.output, args.overwrite)

    rows = []
    for metadata_path in sorted(raw_root.glob("*/*/*/*/run*/metadata.json")):
        rows.append(build_row(metadata_path.parent, debug=args.debug))

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
