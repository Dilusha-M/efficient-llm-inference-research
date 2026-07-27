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
- `world_knowledge`

Each raw run directory contains:
- `result.txt`
- `metadata.json`
- `system-info.txt`
- `gpu-monitor.csv`
- `system-monitor.csv`

Manual quality notes are stored separately under `results/quality/<hardware>/<model>/<workload>/evaluation.md`. The `world_knowledge` workload is additionally machine-scoreable: its fixed questions, answer aliases, and scoring rules live under `experiments/world_knowledge/`.

The world-knowledge workload uses 30 stable, closed-form questions split into easy, medium, and hard tiers. The prompt requires one numbered answer per line, with no explanation. Score a completed raw result with:

```bash
bash experiments/scripts/run_benchmark.sh --backend cpu --hardware <hardware> --model <MODEL_ALIAS> --workload world_knowledge --temp 0.0
python3 experiments/scripts/score_world_knowledge.py results/raw/cpu/<hardware>/<model>/world_knowledge/run1/result.txt
```

Report overall accuracy and accuracy by tier. Keep the prompt, answer key, model, quantization, temperature, and generation settings fixed when comparing model sizes. The score measures answer accuracy on this small probe; it is not a general intelligence score.

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
