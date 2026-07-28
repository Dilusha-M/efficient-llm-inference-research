#!/bin/bash

set -e

BASE="$HOME/llm-research"

# ==========================
# Experiment configuration
# ==========================

BACKEND="cuda"
HARDWARE="gtx1650-4gb"
MODEL="QWEN35_2B"
RUNS=3
GPU_LAYERS=999
# CUDA-only MoE CPU offload. Leave empty for ordinary layer offloading.
# Example: N_CPU_MOE=30 keeps MoE weights from the first 30 layers on CPU.
N_CPU_MOE=""

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


    BENCHMARK_ARGS=(
        --backend "$BACKEND"
        --hardware "$HARDWARE"
        --model "$MODEL"
        --workload "$WORKLOAD"
        --runs "$RUNS"
        --gpu-layers "$GPU_LAYERS"
    )
    if [ -n "$N_CPU_MOE" ]; then
        BENCHMARK_ARGS+=(--n-cpu-moe "$N_CPU_MOE")
    fi

    "$BASE/experiments/scripts/run_benchmark.sh" "${BENCHMARK_ARGS[@]}"

done


echo "======================================"
echo "All workloads completed"
echo "======================================"
