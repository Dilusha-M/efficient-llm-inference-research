#!/usr/bin/env bash

set -u

# Sample NVIDIA GPU telemetry until the monitored process exits.
# Output columns are stable so parse_results.py can aggregate them later.

PID=""
OUT=""
INTERVAL="1"

usage() {
    echo "Usage: $0 --pid <process_id> --out <gpu-monitor.csv> [--interval seconds]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pid)
            PID="${2:-}"
            shift 2
            ;;
        --out)
            OUT="${2:-}"
            shift 2
            ;;
        --interval)
            INTERVAL="${2:-1}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$PID" ] || [ -z "$OUT" ]; then
    usage >&2
    exit 2
fi

mkdir -p "$(dirname "$OUT")"
echo "timestamp,power_w,temperature_c,memory_used_mb,memory_total_mb,utilization_gpu_percent" > "$OUT"

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "$(date -Iseconds),,,,,nvidia-smi-not-found" >> "$OUT"
    exit 0
fi

while kill -0 "$PID" >/dev/null 2>&1; do
    nvidia-smi \
        --query-gpu=timestamp,power.draw,temperature.gpu,memory.used,memory.total,utilization.gpu \
        --format=csv,noheader,nounits >> "$OUT" 2>/dev/null || true
    sleep "$INTERVAL"
done
