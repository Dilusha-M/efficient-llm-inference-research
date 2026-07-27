#!/usr/bin/env bash

set -u

# Capture a one-time system snapshot and optionally sample CPU/RAM while a run is active.

PID=""
OUT=""
SAMPLES=""
INTERVAL="1"

usage() {
    echo "Usage: $0 --out <system-info.txt> [--pid <process_id> --samples <system-monitor.csv>] [--interval seconds]"
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
        --samples)
            SAMPLES="${2:-}"
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

if [ -z "$OUT" ]; then
    usage >&2
    exit 2
fi

mkdir -p "$(dirname "$OUT")"

{
    echo "=== date ==="
    date -Iseconds
    echo
    echo "=== uname ==="
    uname -a
    echo
    echo "=== cpu ==="
    lscpu 2>/dev/null || true
    echo
    echo "=== memory ==="
    free -h 2>/dev/null || true
    echo
    echo "=== gpu ==="
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
    else
        echo "nvidia-smi not found"
    fi
    echo
    echo "=== sensors ==="
    if command -v sensors >/dev/null 2>&1; then
        sensors
    else
        echo "sensors not found"
    fi
} > "$OUT"

if [ -n "$PID" ] && [ -n "$SAMPLES" ]; then
    mkdir -p "$(dirname "$SAMPLES")"
    echo "timestamp,cpu_usage_percent,ram_used_mb,ram_total_mb,cpu_temperature_c" > "$SAMPLES"

    PREV_TOTAL=0
    PREV_IDLE=0

    while kill -0 "$PID" >/dev/null 2>&1; do
        CPU_LINE=$(grep '^cpu ' /proc/stat 2>/dev/null || true)
        CPU_USAGE=""

        if [ -n "$CPU_LINE" ]; then
            read -r _ USER NICE SYSTEM IDLE IOWAIT IRQ SOFTIRQ STEAL _ _ <<EOF
$CPU_LINE
EOF
            IDLE_ALL=$((IDLE + IOWAIT))
            NON_IDLE=$((USER + NICE + SYSTEM + IRQ + SOFTIRQ + STEAL))
            TOTAL=$((IDLE_ALL + NON_IDLE))

            if [ "$PREV_TOTAL" -gt 0 ]; then
                TOTAL_DIFF=$((TOTAL - PREV_TOTAL))
                IDLE_DIFF=$((IDLE_ALL - PREV_IDLE))
                if [ "$TOTAL_DIFF" -gt 0 ]; then
                    CPU_USAGE=$(awk -v total="$TOTAL_DIFF" -v idle="$IDLE_DIFF" 'BEGIN { printf "%.2f", (total-idle)*100/total }')
                fi
            fi

            PREV_TOTAL=$TOTAL
            PREV_IDLE=$IDLE_ALL
        fi

        MEM_TOTAL=$(awk '/MemTotal:/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)
        MEM_AVAIL=$(awk '/MemAvailable:/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)
        MEM_USED=""
        if [ -n "$MEM_TOTAL" ] && [ -n "$MEM_AVAIL" ]; then
            MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
        fi

        TEMP=""
        if command -v sensors >/dev/null 2>&1; then
            TEMP=$(sensors 2>/dev/null | awk '/Tctl:|Package id 0:|CPU:/ { gsub(/[+°C]/, "", $2); print $2; exit }')
        fi

        echo "$(date -Iseconds),$CPU_USAGE,$MEM_USED,$MEM_TOTAL,$TEMP" >> "$SAMPLES"
        sleep "$INTERVAL"
    done
fi
