#!/bin/bash

set -e

BASE="$HOME/llm-research"

# ==========================
# Experiment configuration
# ==========================

BACKEND="cpu"
HARDWARE="ryzen5600"
MODEL="QWEN35_2B"
RUNS=3


# ==========================
# Workloads
# ==========================

WORKLOADS=(
    "chat"
    "coding"
    "summarization"
    "batch"
    "agentic"
    "world_knowledge"
)


# ==========================
# Run benchmarks
# ==========================

for WORKLOAD in "${WORKLOADS[@]}"
do

    echo "======================================"
    echo "Running workload: $WORKLOAD"
    echo "Hardware: $HARDWARE"
    echo "Model: $MODEL"
    echo "======================================"


    "$BASE/experiments/scripts/run_benchmark.sh" \
        --backend "$BACKEND" \
        --hardware "$HARDWARE" \
        --model "$MODEL" \
        --workload "$WORKLOAD" \
        --runs "$RUNS"

done


echo "======================================"
echo "All workloads completed"
echo "======================================"
