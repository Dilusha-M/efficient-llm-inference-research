"""Shared utilities for the reproducible dissertation analysis notebooks."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATASET_PATH = PROJECT_ROOT / "results" / "processed" / "final-analysis-dataset.csv"
FIGURES_DIR = PROJECT_ROOT / "analysis" / "figures"
TABLES_DIR = PROJECT_ROOT / "analysis" / "tables"

NUMERIC_COLUMNS = [
    "gpu_layers", "cpu_threads", "n_cpu_moe", "context_length", "prompt_tokens",
    "generated_tokens", "prompt_eval_tps", "decode_tps", "time_to_first_token",
    "model_load_time", "total_time", "ram_usage", "vram_usage", "gpu_power",
    "gpu_temperature", "cpu_power", "cpu_temperature", "model_size_b",
    "active_parameters_b", "accuracy", "completeness", "correctness",
    "usefulness", "overall_score",
]


def load_dataset(path: Path = DATASET_PATH) -> pd.DataFrame:
    """Load the final analysis CSV and coerce known measures to numeric values."""
    data = pd.read_csv(path)
    for column in NUMERIC_COLUMNS:
        if column in data.columns:
            data[column] = pd.to_numeric(data[column], errors="coerce")
    if "date" in data.columns:
        data["date"] = pd.to_datetime(data["date"], errors="coerce", utc=True)
    return data


def successful(data: pd.DataFrame) -> pd.DataFrame:
    """Return successful benchmark executions without dropping quality NaNs."""
    return data.loc[data["status"].eq("success")].copy()


def save_figure(fig: plt.Figure, filename: str) -> Path:
    """Save a publication-quality figure under analysis/figures."""
    FIGURES_DIR.mkdir(parents=True, exist_ok=True)
    path = FIGURES_DIR / filename
    fig.savefig(path, dpi=300, bbox_inches="tight")
    return path


def save_table(table: pd.DataFrame, filename: str, index: bool = False) -> Path:
    """Save a tabular result under analysis/tables."""
    TABLES_DIR.mkdir(parents=True, exist_ok=True)
    path = TABLES_DIR / filename
    table.to_csv(path, index=index)
    return path


def display_hardware(value: str) -> str:
    labels = {
        "G3250": "Pentium G3250",
        "i7-4790k": "Intel i7-4790K",
        "i5-8265U": "Intel i5-8265U",
        "ryzen5600": "Ryzen 5 5600",
        "gtx1650-4gb": "GTX 1650 4GB",
        "gtx1660-super-6gb": "GTX 1660 Super 6GB",
        "rtx2060-12gb": "RTX 2060 12GB",
    }
    return labels.get(value, value)


def add_display_hardware(data: pd.DataFrame) -> pd.DataFrame:
    result = data.copy()
    result["hardware_label"] = result["hardware"].map(display_hardware)
    return result


def grouped_bar(
    data: pd.DataFrame,
    category: str,
    value: str,
    hue: str,
    title: str,
    ylabel: str,
    filename: str,
    rotate_labels: bool = False,
) -> None:
    """Plot means for a category/hue combination and save the figure."""
    summary = data.groupby([category, hue], dropna=False)[value].mean().unstack(hue)
    ax = summary.plot(kind="bar", figsize=(11, 6), width=0.82)
    ax.set_title(title)
    ax.set_xlabel(category.replace("_", " ").title())
    ax.set_ylabel(ylabel)
    ax.legend(title=hue.replace("_", " ").title(), bbox_to_anchor=(1.02, 1), loc="upper left")
    if rotate_labels:
        ax.tick_params(axis="x", rotation=35)
    else:
        ax.tick_params(axis="x", rotation=0)
    ax.grid(axis="y", alpha=0.25)
    save_figure(ax.get_figure(), filename)
    plt.show()
