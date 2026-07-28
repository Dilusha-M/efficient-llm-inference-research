#!/usr/bin/env bash

set -u

# Reproducible llama.cpp benchmark runner.
# Each run writes raw output, metadata, system information, and monitor samples.

BASE="${LLM_RESEARCH_BASE:-$HOME/llm-research}"
DEFAULT_CONF="$BASE/experiments/configs/default.conf"
MODELS_CONF="$BASE/experiments/configs/models.conf"
PROMPT_DIR="$BASE/experiments/prompts"
RESULTS_RAW="$BASE/results/raw"
DEFAULT_CONTEXT=8192
DEFAULT_TOKENS=-1
DEFAULT_TEMP=0.7
DEFAULT_RUNS=3
DEFAULT_CPU_GPU_LAYERS=0
DEFAULT_CUDA_GPU_LAYERS=999
DEFAULT_VULKAN_GPU_LAYERS=999
DEFAULT_THREADS=1
DEFAULT_INTERVAL=1

if [ -f "$DEFAULT_CONF" ]; then
    # shellcheck disable=SC1090
    source "$DEFAULT_CONF"
fi

DEFAULT_CONTEXT="${context_size:-$DEFAULT_CONTEXT}"
DEFAULT_TOKENS="${generation_tokens:-$DEFAULT_TOKENS}"
DEFAULT_TEMP="${temperature:-$DEFAULT_TEMP}"
DEFAULT_RUNS="${runs:-$DEFAULT_RUNS}"
DEFAULT_CPU_GPU_LAYERS="${cpu_gpu_layers:-$DEFAULT_CPU_GPU_LAYERS}"
DEFAULT_CUDA_GPU_LAYERS="${cuda_gpu_layers:-$DEFAULT_CUDA_GPU_LAYERS}"
DEFAULT_VULKAN_GPU_LAYERS="${vulkan_gpu_layers:-$DEFAULT_VULKAN_GPU_LAYERS}"
DEFAULT_THREADS="${threads:-$DEFAULT_THREADS}"

BACKEND=""
HARDWARE=""
MODEL_ALIAS=""
WORKLOAD=""
RUNS="$DEFAULT_RUNS"
CONTEXT="$DEFAULT_CONTEXT"
CONTEXT_EXPLICIT=0
TOKENS="$DEFAULT_TOKENS"
TEMP="$DEFAULT_TEMP"
GPU_LAYERS=""
N_CPU_MOE=""
THREADS="$DEFAULT_THREADS"
INTERVAL="$DEFAULT_INTERVAL"
DRY_RUN=0

usage() {
    cat <<'USAGE'
Usage:
  ./run_benchmark.sh --backend <cpu|cuda|vulkan> --hardware <label> --model <MODEL_ALIAS> --workload <chat|coding|summarization|batch|agentic|world_knowledge> [options]

Options:
  --runs N             Number of repeated runs. Default: 3
  --context N          llama.cpp context size. Default: 4096
  --tokens N           Maximum generated tokens; -1 means until EOS or context limit. Default: -1
  --temp FLOAT         Sampling temperature. Default: 0.7
  --threads N          llama.cpp worker threads. Default: configured threads
  --gpu-layers N       Override backend GPU layer offload count.
                       Defaults: cpu=0, cuda=999, vulkan=999
  --n-cpu-moe N        CUDA only: keep MoE weights from the first N layers on CPU.
                       Omit to leave llama.cpp's default unchanged.
  --interval SECONDS   Resource monitor sampling interval. Default: 1
  --dry-run            Print the final llama.cpp command and exit without running.
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
            CONTEXT_EXPLICIT=1
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
        --threads)
            THREADS="${2:-}"
            shift 2
            ;;
        --gpu-layers)
            GPU_LAYERS="${2:-}"
            shift 2
            ;;
        --n-cpu-moe)
            N_CPU_MOE="${2:-}"
            shift 2
            ;;
        --interval)
            INTERVAL="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
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
        BACKEND_GPU_LAYERS="$DEFAULT_CPU_GPU_LAYERS"
        ;;
    cuda)
        LLAMA="$BASE/llama.cpp-builds/build-cuda/bin/llama-cli"
        CATEGORY="gpu"
        BACKEND_GPU_LAYERS="$DEFAULT_CUDA_GPU_LAYERS"
        ;;
    vulkan)
        LLAMA="$BASE/llama.cpp-builds/build-vulkan/bin/llama-cli"
        CATEGORY="gpu"
        BACKEND_GPU_LAYERS="$DEFAULT_VULKAN_GPU_LAYERS"
        ;;
    *)
        die "Unsupported backend: $BACKEND"
        ;;
esac

if [ -n "$N_CPU_MOE" ]; then
    [ "$BACKEND" = "cuda" ] || die "--n-cpu-moe is supported only with the cuda backend"
    case "$N_CPU_MOE" in
        *[!0-9]*) die "n-cpu-moe must be a non-negative integer" ;;
    esac
    [ "$N_CPU_MOE" -gt 0 ] || die "n-cpu-moe must be greater than zero when supplied"
fi

if [ -z "$GPU_LAYERS" ]; then
    GPU_LAYERS="$BACKEND_GPU_LAYERS"
fi

case "$WORKLOAD" in
    chat|coding|summarization|batch|agentic|world_knowledge)
        PROMPT_FILE="$PROMPT_DIR/$WORKLOAD.txt"
        ;;
    *)
        die "Unsupported workload: $WORKLOAD"
        ;;
esac

if [ "$CONTEXT_EXPLICIT" -eq 0 ]; then
    case "$WORKLOAD" in
        coding|summarization|batch|agentic|world_knowledge) CONTEXT=$((DEFAULT_CONTEXT * 2)) ;;
    esac
fi

[ -x "$LLAMA" ] || die "llama-cli not found or not executable: $LLAMA"
[ -f "$PROMPT_FILE" ] || die "Missing prompt file: $PROMPT_FILE"
[ -n "$THREADS" ] || die "threads must not be empty"

# shellcheck disable=SC1090
source "$MODELS_CONF"
MODEL_PATH="${!MODEL_ALIAS:-}"
[ -n "$MODEL_PATH" ] || die "Unknown model alias in models.conf: $MODEL_ALIAS"
[ -f "$MODEL_PATH" ] || die "Model file not found: $MODEL_PATH"

PROMPT_TEXT=$(cat "$PROMPT_FILE")
MODEL_FILE=$(basename "$MODEL_PATH")
MODEL_DIR=$(basename "$(dirname "$MODEL_PATH")")
MODEL_LABEL=$(safe_name "${MODEL_DIR%-GGUF}")
QUANTIZATION=$(echo "$MODEL_FILE" | sed -n 's/.*-\(UD-Q[0-9A-Za-z_]*\|Q[0-9A-Za-z_]*\)\.gguf$/\1/p')
PARAMETER_SIZE=$(echo "$MODEL_DIR" | sed -n 's/.*-\([0-9][0-9.]*B\|[0-9][0-9.]*-[0-9][0-9.]*B\).*/\1/p')

OUT_BASE="$RESULTS_RAW/$CATEGORY/$HARDWARE/$MODEL_LABEL/$WORKLOAD"

LLAMA_CMD=(
    "$LLAMA"
    -m "$MODEL_PATH"
    -c "$CONTEXT"
    -n "$TOKENS"
    -ngl "$GPU_LAYERS"
    --threads "$THREADS"
    --temp "$TEMP"
    --perf
    --reasoning off
    --reasoning-budget 0
    -no-cnv
    -st
    --simple-io
    --no-display-prompt
    -p "$PROMPT_TEXT"
)

if [ -n "$N_CPU_MOE" ]; then
    LLAMA_CMD+=(--n-cpu-moe "$N_CPU_MOE")
fi

echo "Benchmark configuration"
echo "  backend:   $BACKEND"
echo "  hardware:  $HARDWARE"
echo "  model:     $MODEL_ALIAS ($MODEL_FILE)"
echo "  workload:  $WORKLOAD"
echo "  runs:      $RUNS"
echo "  threads:   $THREADS"
echo "  gpu layers:$GPU_LAYERS"
echo "  n-cpu-moe: ${N_CPU_MOE:-none}"
echo "  output:    $OUT_BASE"

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'llama command:'
    printf ' %q' "${LLAMA_CMD[@]}"
    printf '
'
    exit 0
fi

mkdir -p "$OUT_BASE"
QUALITY_DIR="$BASE/results/quality/$HARDWARE/$MODEL_LABEL/$WORKLOAD"
mkdir -p "$QUALITY_DIR"
if [ ! -f "$QUALITY_DIR/evaluation.md" ]; then
    printf '# Manual Quality Evaluation
' > "$QUALITY_DIR/evaluation.md"
fi

RUN_INDEX=1
while [ "$RUN_INDEX" -le "$RUNS" ]; do
    RUN_NO=1
    while [ -e "$OUT_BASE/run$RUN_NO" ]; do
        RUN_NO=$((RUN_NO + 1))
    done

    RUN_DIR="$OUT_BASE/run$RUN_NO"
    mkdir -p "$RUN_DIR"

    RESULT="$RUN_DIR/result.txt"
    RUNTIME_LOG="$RUN_DIR/runtime.log"
    METADATA="$RUN_DIR/metadata.json"
    SYSTEM_INFO="$RUN_DIR/system-info.txt"
    GPU_MONITOR="$RUN_DIR/gpu-monitor.csv"
    SYSTEM_MONITOR="$RUN_DIR/system-monitor.csv"
    CPU_MONITOR="$RUN_DIR/cpu-monitor.csv"
    TTFT_FILE="$RUN_DIR/time-to-first-token.txt"
    PID_FILE="$RUN_DIR/llama.pid"
    STATUS="success"
    ERROR_MESSAGE=""

    EXPERIMENT_ID="${CATEGORY}_${HARDWARE}_${MODEL_LABEL}_${WORKLOAD}_run${RUN_NO}_$(date -u +%Y%m%dT%H%M%SZ)"
    START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    START_NS=$(date +%s%N)
    GIT_COMMIT=$(git -C "$BASE" rev-parse HEAD 2>/dev/null || true)

    echo "Starting run $RUN_NO..."

    python3 "$BASE/experiments/scripts/run_llama_timed.py" --ttft-file "$TTFT_FILE" --pid-file "$PID_FILE" -- "${LLAMA_CMD[@]}" > "$RUNTIME_LOG" 2>&1 &

    WRAPPER_PID=$!
    for _ in $(seq 1 100); do
        [ -s "$PID_FILE" ] && break
        kill -0 "$WRAPPER_PID" 2>/dev/null || break
        sleep 0.01
    done
    LLAMA_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    [ -n "$LLAMA_PID" ] || LLAMA_PID="$WRAPPER_PID"

    "$BASE/experiments/scripts/collect_gpu_stats.sh" --pid "$LLAMA_PID" --out "$GPU_MONITOR" --interval "$INTERVAL" &
    GPU_MONITOR_PID=$!

    "$BASE/experiments/scripts/collect_system_stats.sh" --pid "$LLAMA_PID" --out "$SYSTEM_INFO" --samples "$SYSTEM_MONITOR" --interval "$INTERVAL" &
    SYS_MONITOR_PID=$!

    "$BASE/experiments/scripts/collect_cpu_stats.sh" --pid "$LLAMA_PID" --out "$CPU_MONITOR" --interval "$INTERVAL" &
    CPU_MONITOR_PID=$!

    if ! wait "$WRAPPER_PID"; then
        STATUS="failure"
        ERROR_MESSAGE=$(python3 -c 'import sys; from pathlib import Path; p=Path(sys.argv[1]); lines=p.read_text(errors="replace").splitlines() if p.exists() else []; print(" ".join(lines[-20:]))' "$RUNTIME_LOG")
    fi

    wait "$GPU_MONITOR_PID" 2>/dev/null || true
    wait "$SYS_MONITOR_PID" 2>/dev/null || true
    wait "$CPU_MONITOR_PID" 2>/dev/null || true

    python3 "$BASE/experiments/scripts/clean_result.py" \
        --prompt-file "$PROMPT_FILE" --runtime-log "$RUNTIME_LOG" --output "$RESULT"

    END_NS=$(date +%s%N)
    TOTAL_TIME=$(awk -v start="$START_NS" -v end="$END_NS" 'BEGIN { printf "%.3f", (end-start)/1000000000 }')
    TTFT=$(awk 'NF { print $1; exit }' "$TTFT_FILE" 2>/dev/null || true)
    [ -n "$TTFT" ] || TTFT="null"
    TOKEN_COUNTS=$(python3 "$BASE/experiments/scripts/count_tokens.py" \
        --tokenizer "$(dirname "$LLAMA")/llama-tokenize" --model "$MODEL_PATH" \
        --prompt-file "$PROMPT_FILE" --result "$RESULT" 2>/dev/null || echo "{}")
    PROMPT_TOKENS=$(python3 -c 'import json,sys; value=json.loads(sys.argv[1]).get("prompt_tokens"); print(value if value is not None else "null")' "$TOKEN_COUNTS")
    GENERATED_TOKENS=$(python3 -c 'import json,sys; value=json.loads(sys.argv[1]).get("generated_tokens"); print(value if value is not None else "null")' "$TOKEN_COUNTS")
    MODEL_LOAD_TIME=$(python3 -c 'import re,sys; from pathlib import Path; text=Path(sys.argv[1]).read_text(errors="replace") if Path(sys.argv[1]).exists() else ""; m=re.search(r"load time\s*=\s*([0-9.]+)\s*ms", text, re.I); print(f"{float(m.group(1))/1000:.3f}" if m else "null")' "$RUNTIME_LOG")

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
        echo "  \"timestamp\": $(printf '%s' "$START_ISO" | json_escape),"
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
        echo "  \"llama_command\": $(printf '%q ' "${LLAMA_CMD[@]}" | json_escape),"
        echo "  \"git_commit\": $(printf '%s' "$GIT_COMMIT" | json_escape),"
        echo "  \"context_length\": $CONTEXT,"
        echo "  \"context_size\": $CONTEXT,"
        echo "  \"generation_tokens_requested\": $TOKENS,"
        echo "  \"generation_tokens\": $TOKENS,"
        echo "  \"prompt_tokens\": $PROMPT_TOKENS,"
        echo "  \"generated_tokens\": $GENERATED_TOKENS,"
        echo "  \"threads\": $THREADS,"
        echo "  \"gpu_layers\": $GPU_LAYERS,"
        if [ -n "$N_CPU_MOE" ]; then
            echo "  \"n_cpu_moe\": $N_CPU_MOE,"
        else
            echo '  "n_cpu_moe": null,'
        fi
        echo "  \"temperature\": $TEMP,"
        echo "  \"model_load_time\": $MODEL_LOAD_TIME,"
        echo "  \"total_time\": $TOTAL_TIME,"
        echo "  \"time_to_first_token\": $TTFT,"
        echo "  \"cpu\": $(printf '%s' "$CPU_MODEL" | json_escape),"
        echo "  \"ram\": $(printf '%s' "$RAM_TOTAL" | json_escape),"
        echo "  \"gpu\": $(printf '%s' "$GPU_NAME" | json_escape),"
        echo "  \"vram\": $(printf '%s' "$VRAM_TOTAL" | json_escape)"
        echo "}"
    } > "$METADATA"

    echo "Completed run $RUN_NO with status: $STATUS"
    RUN_INDEX=$((RUN_INDEX + 1))
done

python3 "$BASE/experiments/scripts/parse_results.py" --base "$BASE" --overwrite
