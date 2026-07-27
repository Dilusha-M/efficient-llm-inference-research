#!/usr/bin/env bash

set -euo pipefail

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/models/Qwen/Test-GGUF" "$TMP_ROOT/experiments/configs"
touch "$TMP_ROOT/models/Qwen/Test-GGUF/Test-Q4_K_M.gguf"
cat > "$TMP_ROOT/experiments/configs/models.conf" <<CONF
TEST_ALIAS="$TMP_ROOT/models/Qwen/Test-GGUF/Test-Q4_K_M.gguf"
CONF

# shellcheck disable=SC1090
source "$TMP_ROOT/experiments/configs/models.conf"

if [[ "${TEST_ALIAS:-}" != "$TMP_ROOT/models/Qwen/Test-GGUF/Test-Q4_K_M.gguf" ]]; then
    echo "Model alias did not load from models.conf" >&2
    exit 1
fi

if [[ ! -f "$TEST_ALIAS" ]]; then
    echo "Loaded model path does not point to a file" >&2
    exit 1
fi
