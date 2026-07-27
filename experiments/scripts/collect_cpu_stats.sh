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
echo "timestamp,cpu_temperature_c,cpu_power_w,power_source" > "$OUT"

# Only Intel RAPL files are valid for the energy-based fallback. Looking for
# any energy_uj file can select an unrelated powercap device.
ENERGY_FILE=$(find /sys/class/powercap -type f -path '*/intel-rapl*/energy_uj' 2>/dev/null | head -n 1)
PREV_ENERGY=""
PREV_TIME=""

read_turbostat_power() {
    command -v turbostat >/dev/null 2>&1 || return 1
    turbostat --quiet --interval 0.1 --num_iterations 1 --show PkgWatt 2>/dev/null |
        awk '
            /(^|[[:space:]])PkgWatt([[:space:]]|$)/ {
                for (i = 1; i <= NF; i++) if ($i == "PkgWatt") column = i
                next
            }
            column && $column ~ /^[0-9]+(\.[0-9]+)?$/ { print $column; exit }
        '
}

read_amd_hwmon_power() {
    local hwmon name input label value
    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        name=$(cat "$hwmon/name" 2>/dev/null || true)
        for input in "$hwmon"/power*_input "$hwmon"/power*_average; do
            [ -r "$input" ] || continue
            label=$(cat "${input%_*}_label" 2>/dev/null || true)
            case "$label:$name" in
                PPT:*|*:[zZ]enpower|*:[aA][Mm][Dd]*)
                    value=$(cat "$input" 2>/dev/null || true)
                    case "$value" in
                        ''|*[!0-9]*) continue ;;
                        *) awk -v value="$value" 'BEGIN { printf "%.3f", value / 1000000 }'; return 0 ;;
                    esac
                    ;;
            esac
        done
    done
    return 1
}

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
    POWER_SOURCE=""
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

    TURBOSTAT_POWER=$(read_turbostat_power || true)
    if [ -n "$TURBOSTAT_POWER" ]; then
        POWER="$TURBOSTAT_POWER"
        POWER_SOURCE="turbostat"
    elif [ -n "$POWER" ]; then
        POWER_SOURCE="intel_rapl"
    fi

    if [ -z "$POWER_SOURCE" ]; then
        AMD_POWER=$(read_amd_hwmon_power || true)
        if [ -n "$AMD_POWER" ]; then
            POWER="$AMD_POWER"
            POWER_SOURCE="amd_hwmon"
        fi
    fi

    echo "$(date -Iseconds),$TEMP,$POWER,$POWER_SOURCE" >> "$OUT"
    sleep "$INTERVAL"
done
