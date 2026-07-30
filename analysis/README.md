# Reproducible analysis pipeline

This directory contains the dissertation analysis notebooks for the local LLM inference research project.

## Input

All notebooks read only:

`results/processed/final-analysis-dataset.csv`

The benchmark and quality-generation scripts are outside this pipeline. The notebooks do not modify that input or any other project dataset.

## Running the notebooks

Install the notebook dependencies in the environment used for analysis:

```bash
python3 -m pip install pandas matplotlib jupyter
```

From the repository root, execute one notebook:

```bash
jupyter nbconvert --to notebook --execute analysis/notebooks/01_dataset_overview.ipynb   --output 01_dataset_overview.executed.ipynb --ExecutePreprocessor.cwd=.
```

Or launch Jupyter and open `analysis/notebooks/`:

```bash
jupyter lab
```

Run notebooks in numerical order. Each notebook imports `analysis/utils.py`, reads the final dataset, and writes its figures to `analysis/figures/` and tables to `analysis/tables/`. Existing generated outputs may be overwritten when a notebook is rerun.

## Notebook outputs

- `01_dataset_overview.ipynb`: dataset coverage and distribution tables.
- `02_cpu_analysis.ipynb`: CPU throughput, latency, memory, and model-scaling figures.
- `03_gpu_analysis.ipynb`: GPU offload, throughput, memory, power, and performance-per-watt figures.
- `04_model_scaling_analysis.ipynb`: architecture, parameter-count, active-parameter, and quantization analyses.
- `05_quality_performance_analysis.ipynb`: quality, speed, memory, and trade-off analyses.
- `06_suitability_framework.ipynb`: configurable suitability classifications and recommendation matrices.

Figures are saved as 300-DPI PNG files. Tables are saved as CSV files with descriptive names.
