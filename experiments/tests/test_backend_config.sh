#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/experiments/configs" "$TMP_ROOT/experiments/prompts" "$TMP_ROOT/models/TestModel-GGUF"
mkdir -p "$TMP_ROOT/llama.cpp-builds/build-cpu/bin" "$TMP_ROOT/llama.cpp-builds/build-cuda/bin" "$TMP_ROOT/llama.cpp-builds/build-vulkan/bin"

touch "$TMP_ROOT/models/TestModel-GGUF/TestModel-Q4_K_M.gguf"
printf 'prompt
' > "$TMP_ROOT/experiments/prompts/chat.txt"
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
TEST_MODEL="$TMP_ROOT/models/TestModel-GGUF/TestModel-Q4_K_M.gguf"
CONF

for backend in cpu cuda vulkan; do
    cat > "$TMP_ROOT/llama.cpp-builds/build-$backend/bin/llama-cli" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$TMP_ROOT/llama.cpp-builds/build-$backend/bin/llama-cli"
done

assert_ngl() {
    local backend="$1"
    local expected="$2"
    local output
    output=$(LLM_RESEARCH_BASE="$TMP_ROOT" bash "$REPO_ROOT/experiments/scripts/run_benchmark.sh"         --backend "$backend" --hardware test-hw --model TEST_MODEL --workload chat --dry-run)
    if [[ "$output" != *" -ngl $expected "* ]]; then
        echo "Expected $backend to use -ngl $expected" >&2
        echo "$output" >&2
        exit 1
    fi
    if [[ "$output" != *" -no-cnv "* ]]; then
        echo "Expected $backend command to include -no-cnv" >&2
        echo "$output" >&2
        exit 1
    fi
}

assert_ngl cpu 0
assert_ngl cuda 999
assert_ngl vulkan 999
