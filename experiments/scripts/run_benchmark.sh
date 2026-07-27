#!/usr/bin/env bash

set -u

# Reproducible llama.cpp benchmark runner.
# Each run writes raw output, metadata, system information, and monitor samples.

BASE="${LLM_RESEARCH_BASE:-$HOME/llm-research}"
MODELS_CONF="$BASE/experiments/configs/models.conf"
PROMPT_DIR="$BASE/experiments/prompts"
RESULTS_RAW="$BASE/results/raw"
DEFAULT_CONTEXT=4096
DEFAULT_TOKENS=256
DEFAULT_TEMP=0.7
DEFAULT_RUNS=3
DEFAULT_GPU_LAYERS=999
DEFAULT_INTERVAL=1

BACKEND=""
HARDWARE=""
MODEL_ALIAS=""
WORKLOAD=""
RUNS="$DEFAULT_RUNS"
CONTEXT="$DEFAULT_CONTEXT"
TOKENS="$DEFAULT_TOKENS"
TEMP="$DEFAULT_TEMP"
GPU_LAYERS="$DEFAULT_GPU_LAYERS"
INTERVAL="$DEFAULT_INTERVAL"

usage() {
    cat <<'USAGE'
Usage:
  ./run_benchmark.sh --backend <cpu|cuda|vulkan> --hardware <label> --model <MODEL_ALIAS> --workload <chat|coding|summarization|batch|agentic> [options]

Options:
  --runs N             Number of repeated runs. Default: 3
  --context N          llama.cpp context size. Default: 4096
  --tokens N           Maximum generated tokens. Default: 256
  --temp FLOAT         Sampling temperature. Default: 0.7
  --gpu-layers N       llama.cpp GPU layer offload count. Default: 999
  --interval SECONDS   Resource monitor sampling interval. Default: 1
  -h, --help           Show this help.

Example:
  ./run_benchmark.sh --backend cuda --hardware rtx2060-12gb --model QWEN35_9B --workload coding --runs 3
USAGE
}

die() {
    echo "Error: $*" >&2
    exit 1
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

safe_name() {
    echo "$1" | sed 's#[^A-Za-z0-9._+-]#_#g'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --backend)
            BACKEND="${2:-}"
            shift 2
            ;;
        --hardware)
            HARDWARE="${2:-}"
            shift 2
            ;;
        --model)
            MODEL_ALIAS="${2:-}"
            shift 2
            ;;
        --workload)
            WORKLOAD="${2:-}"
            shift 2
            ;;
        --runs)
            RUNS="${2:-}"
            shift 2
            ;;
        --context)
            CONTEXT="${2:-}"
            shift 2
            ;;
        --tokens)
            TOKENS="${2:-}"
            shift 2
            ;;
        --temp)
            TEMP="${2:-}"
            shift 2
            ;;
        --gpu-layers)
            GPU_LAYERS="${2:-}"
            shift 2
            ;;
        --interval)
            INTERVAL="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[ -n "$BACKEND" ] || die "--backend is required"
[ -n "$HARDWARE" ] || die "--hardware is required"
[ -n "$MODEL_ALIAS" ] || die "--model is required"
[ -n "$WORKLOAD" ] || die "--workload is required"
[ -f "$MODELS_CONF" ] || die "Missing models.conf: $MODELS_CONF"

case "$BACKEND" in
    cpu)
        LLAMA="$BASE/llama.cpp-builds/build-cpu/bin/llama-cli"
        CATEGORY="cpu"
        ;;
    cuda)
        LLAMA="$BASE/llama.cpp-builds/build-cuda/bin/llama-cli"
        CATEGORY="gpu"
        ;;
    vulkan)
        LLAMA="$BASE/llama.cpp-builds/build-vulkan/bin/llama-cli"
        CATEGORY="gpu"
        ;;
    *)
        die "Unsupported backend: $BACKEND"
        ;;
esac

case "$WORKLOAD" in
    chat|coding|summarization|batch|agentic)
        PROMPT_FILE="$PROMPT_DIR/$WORKLOAD.txt"
        ;;
    *)
        die "Unsupported workload: $WORKLOAD"
        ;;
esac

[ -x "$LLAMA" ] || die "llama-cli not found or not executable: $LLAMA"
[ -f "$PROMPT_FILE" ] || die "Missing prompt file: $PROMPT_FILE"

# shellcheck disable=SC1090
source "$MODELS_CONF"
MODEL_PATH="${!MODEL_ALIAS:-}"
[ -n "$MODEL_PATH" ] || die "Unknown model alias in models.conf: $MODEL_ALIAS"
[ -f "$MODEL_PATH" ] || die "Model file not found: $MODEL_PATH"

MODEL_FILE=$(basename "$MODEL_PATH")
MODEL_DIR=$(basename "$(dirname "$MODEL_PATH")")
MODEL_LABEL=$(safe_name "${MODEL_DIR%-GGUF}")
QUANTIZATION=$(echo "$MODEL_FILE" | sed -n 's/.*-\(UD-Q[0-9A-Za-z_]*\|Q[0-9A-Za-z_]*\)\.gguf$/\1/p')
PARAMETER_SIZE=$(echo "$MODEL_DIR" | sed -n 's/.*-\([0-9][0-9.]*B\|[0-9][0-9.]*-[0-9][0-9.]*B\).*/\1/p')

OUT_BASE="$RESULTS_RAW/$CATEGORY/$HARDWARE/$MODEL_LABEL/$WORKLOAD"
mkdir -p "$OUT_BASE"

echo "Benchmark configuration"
echo "  backend:   $BACKEND"
echo "  hardware:  $HARDWARE"
echo "  model:     $MODEL_ALIAS ($MODEL_FILE)"
echo "  workload:  $WORKLOAD"
echo "  runs:      $RUNS"
echo "  output:    $OUT_BASE"

RUN_INDEX=1
while [ "$RUN_INDEX" -le "$RUNS" ]; do
    RUN_NO=1
    while [ -e "$OUT_BASE/run$RUN_NO" ]; do
        RUN_NO=$((RUN_NO + 1))
    done

    RUN_DIR="$OUT_BASE/run$RUN_NO"
    mkdir -p "$RUN_DIR"

    RESULT="$RUN_DIR/result.txt"
    METADATA="$RUN_DIR/metadata.json"
    SYSTEM_INFO="$RUN_DIR/system-info.txt"
    GPU_MONITOR="$RUN_DIR/gpu-monitor.csv"
    SYSTEM_MONITOR="$RUN_DIR/system-monitor.csv"
    STATUS="success"
    ERROR_MESSAGE=""

    EXPERIMENT_ID="${CATEGORY}_${HARDWARE}_${MODEL_LABEL}_${WORKLOAD}_run${RUN_NO}_$(date -u +%Y%m%dT%H%M%SZ)"
    START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    START_NS=$(date +%s%N)

    echo "Starting run $RUN_NO..."

    "$LLAMA" \
        -m "$MODEL_PATH" \
        -c "$CONTEXT" \
        -n "$TOKENS" \
        -ngl "$GPU_LAYERS" \
        --temp "$TEMP" \
        --perf \
        -f "$PROMPT_FILE" > "$RESULT" 2>&1 &

    LLAMA_PID=$!

    "$BASE/experiments/scripts/collect_gpu_stats.sh" --pid "$LLAMA_PID" --out "$GPU_MONITOR" --interval "$INTERVAL" &
    GPU_MONITOR_PID=$!

    "$BASE/experiments/scripts/collect_system_stats.sh" --pid "$LLAMA_PID" --out "$SYSTEM_INFO" --samples "$SYSTEM_MONITOR" --interval "$INTERVAL" &
    SYS_MONITOR_PID=$!

    if ! wait "$LLAMA_PID"; then
        STATUS="failure"
        ERROR_MESSAGE=$(python3 -c 'import sys; from pathlib import Path; p=Path(sys.argv[1]); lines=p.read_text(errors="replace").splitlines() if p.exists() else []; print(" ".join(lines[-20:]))' "$RESULT")
    fi

    wait "$GPU_MONITOR_PID" 2>/dev/null || true
    wait "$SYS_MONITOR_PID" 2>/dev/null || true

    END_NS=$(date +%s%N)
    TOTAL_TIME=$(awk -v start="$START_NS" -v end="$END_NS" 'BEGIN { printf "%.3f", (end-start)/1000000000 }')

    CPU_MODEL=$(lscpu 2>/dev/null | awk -F: '/Model name:/ { sub(/^[ \t]+/, "", $2); print $2; exit }')
    RAM_TOTAL=$(awk '/MemTotal:/ { printf "%.0f MB", $2/1024 }' /proc/meminfo 2>/dev/null)
    GPU_NAME=""
    VRAM_TOTAL=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | paste -sd ';' -)
        VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | paste -sd ';' -)
    fi

    {
        echo "{"
        echo "  \"experiment_id\": $(printf '%s' "$EXPERIMENT_ID" | json_escape),"
        echo "  \"date\": $(printf '%s' "$START_ISO" | json_escape),"
        echo "  \"run_number\": $RUN_NO,"
        echo "  \"status\": $(printf '%s' "$STATUS" | json_escape),"
        echo "  \"error_message\": $(printf '%s' "$ERROR_MESSAGE" | json_escape),"
        echo "  \"backend\": $(printf '%s' "$BACKEND" | json_escape),"
        echo "  \"hardware\": $(printf '%s' "$HARDWARE" | json_escape),"
        echo "  \"hardware_category\": $(printf '%s' "$CATEGORY" | json_escape),"
        echo "  \"model_alias\": $(printf '%s' "$MODEL_ALIAS" | json_escape),"
        echo "  \"model_label\": $(printf '%s' "$MODEL_LABEL" | json_escape),"
        echo "  \"model_filename\": $(printf '%s' "$MODEL_FILE" | json_escape),"
        echo "  \"model_path\": $(printf '%s' "$MODEL_PATH" | json_escape),"
        echo "  \"parameter_size\": $(printf '%s' "$PARAMETER_SIZE" | json_escape),"
        echo "  \"quantization_type\": $(printf '%s' "$QUANTIZATION" | json_escape),"
        echo "  \"workload\": $(printf '%s' "$WORKLOAD" | json_escape),"
        echo "  \"prompt_file\": $(printf '%s' "$PROMPT_FILE" | json_escape),"
        echo "  \"llama_binary\": $(printf '%s' "$LLAMA" | json_escape),"
        echo "  \"context_length\": $CONTEXT,"
        echo "  \"generation_tokens_requested\": $TOKENS,"
        echo "  \"gpu_layers\": $GPU_LAYERS,"
        echo "  \"temperature\": $TEMP,"
        echo "  \"total_time\": $TOTAL_TIME,"
        echo "  \"time_to_first_token\": null,"
        echo "  \"cpu\": $(printf '%s' "$CPU_MODEL" | json_escape),"
        echo "  \"ram\": $(printf '%s' "$RAM_TOTAL" | json_escape),"
        echo "  \"gpu\": $(printf '%s' "$GPU_NAME" | json_escape),"
        echo "  \"vram\": $(printf '%s' "$VRAM_TOTAL" | json_escape)"
        echo "}"
    } > "$METADATA"

    echo "Completed run $RUN_NO with status: $STATUS"
    RUN_INDEX=$((RUN_INDEX + 1))
done

python3 "$BASE/experiments/scripts/parse_results.py" --base "$BASE"
