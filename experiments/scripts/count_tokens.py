#!/usr/bin/env python3

"""Count prompt and generated tokens for a completed llama-cli run."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


TOTAL_RE = re.compile(r"Total number of tokens:\s*(\d+)")
GENERATED_RE = re.compile(r"(?:\[Start thinking\]|Final model response\s*)(.*?)(?=\[\s*Prompt:\s*|\Z)", re.IGNORECASE | re.DOTALL)


def token_count(tokenizer: Path, model: Path, text: str) -> int | None:
    result = subprocess.run(
        [str(tokenizer), "-m", str(model), "--stdin", "--show-count"],
        input=text,
        text=True,
        capture_output=True,
        check=False,
    )
    match = TOTAL_RE.search(result.stdout + result.stderr)
    return int(match.group(1)) if match else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokenizer", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--result", type=Path, required=True)
    args = parser.parse_args()

    prompt = args.prompt_file.read_text(encoding="utf-8", errors="replace").rstrip("\n")
    result = args.result.read_text(encoding="utf-8", errors="replace")
    generated_match = GENERATED_RE.search(result)
    generated = generated_match.group(1) if generated_match else ""

    print(json.dumps({
        "prompt_tokens": token_count(args.tokenizer, args.model, prompt),
        "generated_tokens": token_count(args.tokenizer, args.model, generated) if generated else None,
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
