#!/usr/bin/env python3

"""Create a human-readable result.txt from llama-cli's combined runtime log."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TIMING_RE = re.compile(r"\[\s*Prompt:.*?\|\s*Generation:.*?\]", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--runtime-log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    prompt = args.prompt_file.read_text(encoding="utf-8", errors="replace").rstrip("\n")
    raw = args.runtime_log.read_text(encoding="utf-8", errors="replace")
    raw = ANSI_RE.sub("", raw).replace("\b", "")

    marker = re.search(r"\[Start thinking\]", raw, re.IGNORECASE)
    if marker:
        remainder = raw[marker.end():]
        end_marker = re.search(r"(?:\[End thinking\]|</think>|<\/think>)", remainder, re.IGNORECASE)
        response = remainder[end_marker.end():] if end_marker else ""
    else:
        prompt_position = raw.find(prompt)
        response = raw[prompt_position + len(prompt):] if prompt_position >= 0 else raw
    response = TIMING_RE.sub("", response)
    response = re.sub(r"\n\s*Exiting\.\.\.\s*$", "", response, flags=re.IGNORECASE)
    response = response.strip()

    args.output.write_text(
        f"Input prompt\n\n{prompt}\n\nFinal model response\n\n{response}\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
