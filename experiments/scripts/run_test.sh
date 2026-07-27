#!/bin/bash

set -e

# Arguments
BACKEND=$1
HARDWARE=$2
MODEL_NAME=$3

if [ -z "$BACKEND" ] || [ -z "$HARDWARE" ] || [ -z "$MODEL_NAME" ]; then
    echo "Usage:"
    echo "./run_test.sh <cpu|cuda|vulkan> <hardware> <MODEL_VARIABLE>"
    exit 1
fi


BASE="$HOME/llm-research"

source "$BASE/experiments/configs/models.conf"


# Select model
MODEL=${!MODEL_NAME}

if [ -z "$MODEL" ]; then
    echo "Unknown model: $MODEL_NAME"
    exit 1
fi


# Select backend binary

case $BACKEND in

cpu)
    LLAMA="$BASE/llama.cpp-builds/build-cpu/bin/llama-cli"
    ;;

cuda)
    LLAMA="$BASE/llama.cpp-builds/build-cuda/bin/llama-cli"
    ;;

vulkan)
    LLAMA="$BASE/llama.cpp-builds/build-vulkan/bin/llama-cli"
    ;;

*)
    echo "Unknown backend"
    exit 1
    ;;

esac


# Output directory

SAFE_MODEL=$(basename "$MODEL" .gguf)

OUTDIR="$BASE/results/raw/$BACKEND/$HARDWARE/$SAFE_MODEL"

mkdir -p "$OUTDIR"


# Find next run number

RUN=1

while [ -f "$OUTDIR/run$RUN.txt" ]
do
    RUN=$((RUN+1))
done


OUTPUT="$OUTDIR/run$RUN.txt"


echo "================================="
echo "Backend : $BACKEND"
echo "Hardware: $HARDWARE"
echo "Model   : $MODEL"
echo "Output  : $OUTPUT"
echo "================================="


PROMPT="Explain the transformer architecture used in modern large language models. Describe attention mechanisms, token embeddings, and the key-value cache."


$LLAMA \
-m "$MODEL" \
-c 4096 \
-n 256 \
-ngl 999 \
-p "$PROMPT" \
--temp 0.7 \
> "$OUTPUT" 2>&1


echo "Completed:"
echo "$OUTPUT"
