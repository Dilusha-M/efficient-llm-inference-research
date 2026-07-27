#!/bin/bash

OUT=$1

mkdir -p hardware/$OUT

lscpu > hardware/$OUT/cpu.txt
free -h > hardware/$OUT/memory.txt
uname -a > hardware/$OUT/system.txt

if command -v nvidia-smi >/dev/null
then
    nvidia-smi > hardware/$OUT/nvidia-smi.txt
fi

