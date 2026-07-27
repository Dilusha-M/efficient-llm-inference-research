#!/usr/bin/env python3
"""Score the numbered answers in a world_knowledge result file."""

from __future__ import annotations

import argparse
import json
import re
import string
from pathlib import Path

ANSWER_LINE = re.compile(r"^\s*(\d{1,2})\s*[.)-]\s*(.*?)\s*$")


def normalize(value: str) -> str:
    value = value.casefold().replace("²", "2")
    value = value.replace("m/s2", "m/s^2")
    value = value.translate(str.maketrans("", "", string.punctuation.replace("^", "")))
    value = re.sub(r"\b(the|a|an)\b", " ", value)
    return " ".join(value.split())


def score(result_path: Path, key_path: Path) -> dict:
    key = json.loads(key_path.read_text(encoding="utf-8"))
    expected = {item["id"]: item for item in key["questions"]}
    observed = {}
    for line in result_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = ANSWER_LINE.match(line)
        if match:
            observed[match.group(1).zfill(2)] = normalize(match.group(2))

    rows = []
    for question_id, item in expected.items():
        accepted = {normalize(answer) for answer in item["answers"]}
        answer = observed.get(question_id, "")
        rows.append({"id": question_id, "tier": item["tier"], "correct": answer in accepted, "answer": answer})

    by_tier = {}
    for tier in ("easy", "medium", "hard"):
        tier_rows = [row for row in rows if row["tier"] == tier]
        by_tier[tier] = {"correct": sum(row["correct"] for row in tier_rows), "total": len(tier_rows)}
    correct = sum(row["correct"] for row in rows)
    return {
        "correct": correct,
        "total": len(rows),
        "accuracy": round(correct / len(rows), 4),
        "by_tier": by_tier,
        "missing_or_unparseable": [row["id"] for row in rows if not row["answer"]],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("result", type=Path)
    parser.add_argument("--key", type=Path, default=Path(__file__).parents[1] / "world_knowledge" / "answer_key.json")
    args = parser.parse_args()
    print(json.dumps(score(args.result, args.key), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
