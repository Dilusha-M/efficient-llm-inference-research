#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/experiments/configs" "$TMP_ROOT/experiments/prompts" "$TMP_ROOT/experiments/scripts"
mkdir -p "$TMP_ROOT/llama.cpp-builds/build-cpu/bin" "$TMP_ROOT/models/Test Model-GGUF" "$TMP_ROOT/logs"

touch "$TMP_ROOT/models/Test Model-GGUF/Test Model-Q4_K_M.gguf"
cat > "$TMP_ROOT/experiments/prompts/chat.txt" <<'PROMPT'
Explain the transformer architecture
with spaces, quotes "like this", and a second line.
PROMPT

cat > "$TMP_ROOT/experiments/configs/default.conf" <<CONF
context_size=128
generation_tokens=16
temperature=0.0
runs=1
threads=2
cpu_gpu_layers=0
cuda_gpu_layers=999
vulkan_gpu_layers=999
CONF

cat > "$TMP_ROOT/experiments/configs/models.conf" <<CONF
TEST_MODEL="$TMP_ROOT/models/Test Model-GGUF/Test Model-Q4_K_M.gguf"
CONF

cat > "$TMP_ROOT/llama.cpp-builds/build-cpu/bin/llama-cli" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

: "${TEST_LLAMA_LOG_DIR:?}"
seen_prompt=0
seen_single_turn=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -st|--single-turn)
            seen_single_turn=1
            ;;
        -p)
            seen_prompt=$((seen_prompt + 1))
            shift
            printf '%s' "$1" > "$TEST_LLAMA_LOG_DIR/prompt.txt"
            ;;
        -f)
            touch "$TEST_LLAMA_LOG_DIR/seen_file_prompt"
            shift
            ;;
    esac
    shift || true
done

printf '%s' "$seen_prompt" > "$TEST_LLAMA_LOG_DIR/prompt_count"
printf '%s' "$seen_single_turn" > "$TEST_LLAMA_LOG_DIR/single_turn"
if [ "$seen_single_turn" != "1" ]; then
    exit 3
fi
if IFS= read -r -t 1 stdin_line; then
    printf '%s' "$stdin_line" > "$TEST_LLAMA_LOG_DIR/stdin_leaked"
    exit 2
fi
printf 'generated response\n'
exit 0
SH
chmod +x "$TMP_ROOT/llama.cpp-builds/build-cpu/bin/llama-cli"

cat > "$TMP_ROOT/experiments/scripts/collect_gpu_stats.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP_ROOT/experiments/scripts/collect_gpu_stats.sh"

cat > "$TMP_ROOT/experiments/scripts/collect_system_stats.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP_ROOT/experiments/scripts/collect_system_stats.sh"

cat > "$TMP_ROOT/experiments/scripts/parse_results.py" <<'PY'
#!/usr/bin/env python3
import sys
sys.exit(0)
PY
chmod +x "$TMP_ROOT/experiments/scripts/parse_results.py"

EXPECTED_PROMPT=$(cat "$TMP_ROOT/experiments/prompts/chat.txt")

if ! printf 'unexpected stdin\n' | TEST_LLAMA_LOG_DIR="$TMP_ROOT/logs" LLM_RESEARCH_BASE="$TMP_ROOT" timeout 10s bash "$REPO_ROOT/experiments/scripts/run_benchmark.sh" \
    --backend cpu --hardware test-hw --model TEST_MODEL --workload chat --runs 1 > "$TMP_ROOT/benchmark.out" 2>&1; then
    echo "Benchmark command did not terminate successfully" >&2
    cat "$TMP_ROOT/benchmark.out" >&2
    exit 1
fi

if [ -e "$TMP_ROOT/logs/seen_file_prompt" ]; then
    echo "llama-cli received file prompt mode (-f), expected -p" >&2
    exit 1
fi

if [ "$(cat "$TMP_ROOT/logs/prompt_count")" != "1" ]; then
    echo "llama-cli did not receive exactly one -p prompt argument" >&2
    exit 1
fi

if [ "$(cat "$TMP_ROOT/logs/single_turn")" != "1" ]; then
    echo "llama-cli did not receive single-turn mode (-st)" >&2
    exit 1
fi

if [ "$(cat "$TMP_ROOT/logs/prompt.txt")" != "$EXPECTED_PROMPT" ]; then
    echo "llama-cli prompt argument did not match prompt file contents" >&2
    exit 1
fi

if [ -e "$TMP_ROOT/logs/stdin_leaked" ]; then
    echo "llama-cli received benchmark stdin; expected stdin to be closed" >&2
    exit 1
fi

if [ ! -f "$TMP_ROOT/results/raw/cpu/test-hw/Test_Model/chat/run1/result.txt" ]; then
    echo "Benchmark did not write result.txt" >&2
    exit 1
fi
