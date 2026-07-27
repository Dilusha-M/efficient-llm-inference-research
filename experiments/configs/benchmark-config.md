# LLM Inference Benchmark Configuration

## Runtime
Framework:
llama.cpp

Backends:
- CPU
- CUDA
- Vulkan

OS:
Ubuntu Server 24.04 LTS


## Model Settings

Quantization:
Q4_K_M (primary)

Context length:
4096 tokens

Generation length:
256 tokens

Temperature:
0.7


## Performance Metrics

Measured:
- Prompt processing speed (tok/s)
- Generation speed (tok/s)
- RAM usage
- VRAM usage
- Power usage (where available)


## Repetition

Each benchmark:
3 runs

Reported value:
Average


## Hardware Variables

CPU:
- Ryzen 5 5600
- i7-4790K
- Pentium G3250
- i5-8265U

GPU:
- RTX2060 12GB
- GTX1660 Super 6GB
- GTX1650 4GB
