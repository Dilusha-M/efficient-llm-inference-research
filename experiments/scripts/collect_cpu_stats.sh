#!/usr/bin/env bash

set -u

PID=""
OUT=""
INTERVAL="1"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pid) PID="${2:-}"; shift 2 ;;
        --out) OUT="${2:-}"; shift 2 ;;
        --interval) INTERVAL="${2:-1}"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$PID" ] && [ -n "$OUT" ] || exit 2
mkdir -p "$(dirname "$OUT")"
echo "timestamp,cpu_temperature_c,cpu_power_w" > "$OUT"

ENERGY_FILE=$(find /sys/class/powercap -type f -name energy_uj 2>/dev/null | head -n 1)
PREV_ENERGY=""
PREV_TIME=""

while kill -0 "$PID" >/dev/null 2>&1; do
    TEMP=""
    for HWMON in /sys/class/hwmon/hwmon*; do
        [ -r "$HWMON/name" ] || continue
        NAME=$(cat "$HWMON/name" 2>/dev/null || true)
        case "$NAME" in
            k10temp|coretemp)
                for INPUT in "$HWMON"/temp*_input; do
                    [ -r "$INPUT" ] || continue
                    LABEL=$(cat "${INPUT%_input}_label" 2>/dev/null || true)
                    case "$LABEL" in
                        Tctl|"Package id 0"|Package|CPU|Tdie|"")
                            TEMP=$(awk '{ printf "%.3f", $1/1000 }' "$INPUT")
                            [ "$LABEL" = "Tctl" ] && break 2
                            ;;
                    esac
                done
                ;;
        esac
    done

    POWER=""
    if [ -n "$ENERGY_FILE" ] && [ -r "$ENERGY_FILE" ]; then
        NOW=$(date +%s%N)
        ENERGY=$(cat "$ENERGY_FILE" 2>/dev/null || true)
        if [ -n "$ENERGY" ] && [ -n "$PREV_ENERGY" ] && [ -n "$PREV_TIME" ]; then
            POWER=$(awk -v now="$ENERGY" -v prev="$PREV_ENERGY" -v t="$NOW" -v pt="$PREV_TIME" \
                'BEGIN { if (now >= prev && t > pt) printf "%.3f", (now-prev)/((t-pt)/1000000000)/1000000 }')
        fi
        PREV_ENERGY="$ENERGY"
        PREV_TIME="$NOW"
    fi

    echo "$(date -Iseconds),$TEMP,$POWER" >> "$OUT"
    sleep "$INTERVAL"
done
