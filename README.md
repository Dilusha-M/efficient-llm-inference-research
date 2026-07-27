# Efficient LLM Inference on Low-Resource Hardware

Research environment for MSc dissertation experiments.

## Hardware Platforms

CPU:
- Ryzen 5 5600
- Intel i7-4790K
- Intel Pentium G3250
- Intel i5-8265U

GPU:
- RTX 2060 12GB
- GTX 1660 Super 6GB
- GTX 1650 4GB

## Runtime

llama.cpp:
- CPU backend
- CUDA backend
- Vulkan backend

OS:
Ubuntu Server 24.04 LTS

## Benchmark Configuration

Benchmarks are run through `experiments/scripts/run_benchmark.sh` using fixed prompt files in `experiments/prompts/` and model aliases from `experiments/configs/models.conf`.

Supported llama.cpp backends:
- `cpu`: uses the CPU build and forces `-ngl 0`.
- `cuda`: uses the CUDA build and defaults to `-ngl 999`.
- `vulkan`: uses the Vulkan build and defaults to `-ngl 999`.

Common settings live in `experiments/configs/default.conf`, including context size, generation tokens, temperature, run count, CPU threads, and backend GPU layer defaults. Thread count is controlled with `threads` or `--threads`; it is not inferred from CPU model names.

Each benchmark uses one fixed workload prompt, requests one completion, passes `-no-cnv` to disable llama.cpp conversation mode, and exits automatically after generation.

Workload categories:
- `chat`
- `coding`
- `summarization`
- `batch`
- `agentic`

Each raw run directory contains:
- `result.txt`
- `metadata.json`
- `system-info.txt`
- `gpu-monitor.csv`
- `system-monitor.csv`

Manual quality notes are stored separately under `results/quality/<hardware>/<model>/<workload>/evaluation.md`. Scoring is intentionally manual and is not automated by the framework.

## Collected Metrics

Performance:
- prompt processing speed
- decode speed
- total generation time
- model load time

Memory:
- RAM usage
- VRAM usage

Hardware:
- GPU utilization
- power
- temperature

Stability:
- success/failure status
- error message in metadata when a run fails

`experiments/scripts/parse_results.py` converts raw run artifacts into the processed CSV format at `results/processed/benchmark-results.csv`. If the target CSV already exists, direct parser runs write a timestamped CSV unless `--overwrite` is supplied.
