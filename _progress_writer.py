#!/usr/bin/env python3
"""Bounded progress-snapshot writer for the model-download scripts.

Reads a child process's (modelscope/tqdm) output on stdin and keeps only the
last N non-blank lines, rewriting the snapshot file in-place on each update.
This makes the progress log always show the *current* progress while staying
a fixed, tiny size — tqdm's carriage-return refreshes never accumulate.

Usage:
    modelscope download ... 2>&1 | python3 _progress_writer.py <snapshot_path>

tqdm refreshes a bar by emitting '\\r'; multi-bar output also uses ESC[A
(cursor-up). We normalise '\\r' to '\\n' so each refresh becomes a line, then
keep only the tail. We do NOT strip ANSI — a snapshot is for humans tailing it.
"""
import os
import sys
from collections import deque

KEEP_LINES = 40


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: _progress_writer.py <snapshot_path>\n")
        return 2
    path = sys.argv[1]
    keep: deque[str] = deque(maxlen=KEEP_LINES)
    buf = ""
    while True:
        chunk = os.read(0, 4096)  # unbuffered read straight from the pipe
        if not chunk:
            break
        buf += chunk.decode("utf-8", "replace").replace("\r", "\n")
        *complete, buf = buf.split("\n")
        changed = False
        for line in complete:
            if line.strip():
                keep.append(line)
                changed = True
        if changed:
            with open(path, "w") as f:
                f.write("\n".join(keep) + "\n")
    # flush any trailing partial line
    if buf.strip():
        keep.append(buf)
        with open(path, "w") as f:
            f.write("\n".join(keep) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
