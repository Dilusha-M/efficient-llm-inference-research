#!/usr/bin/env python3

"""Run llama-cli while recording time to the first generated output byte."""

from __future__ import annotations

import argparse
import subprocess
import sys
import re
import threading
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ttft-file", type=Path, required=True)
    parser.add_argument("--pid-file", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        print("run_llama_timed.py: missing command", file=sys.stderr)
        return 2
    args.ttft_file.parent.mkdir(parents=True, exist_ok=True)
    args.ttft_file.write_text("", encoding="utf-8")
    started = time.monotonic_ns()
    first_output_ns: int | None = None
    stdout_buffer = bytearray()
    lock = threading.Lock()
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, bufsize=0)
    args.pid_file.write_text(str(process.pid), encoding="utf-8")

    def forward(stream, mark_first_output: bool) -> None:
        nonlocal first_output_ns
        assert stream is not None
        while chunk := stream.read(4096):
            if mark_first_output:
                with lock:
                    if first_output_ns is None:
                        stdout_buffer.extend(chunk)
                        if re.search(rb"\[(?:Start|Begin)\s+(?:thinking|answer|response)\]", stdout_buffer, re.IGNORECASE):
                            first_output_ns = time.monotonic_ns()
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()

    threads = [threading.Thread(target=forward, args=(process.stdout, True)),
               threading.Thread(target=forward, args=(process.stderr, False))]
    for thread in threads:
        thread.start()
    return_code = process.wait()
    for thread in threads:
        thread.join()
    if first_output_ns is not None:
        args.ttft_file.write_text(f"{(first_output_ns - started) / 1_000_000_000:.6f}\n",
                                  encoding="utf-8")
    return return_code


if __name__ == "__main__":
    raise SystemExit(main())
