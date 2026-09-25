#!/usr/bin/env python3
"""Insert editorial marker lines (e.g. `<!-- no_collate` / `-->`) into a cleaned witness.

Used for witnesses whose text cannot be redistributed in this repository (see corpus/verne/README.md): the
repository keeps only the marker positions, and this script re-applies them to the text the user downloads.

    python3 scripts/apply_marks.py <cleaned.txt> <marks.json> <out.txt>
"""
import json
import sys


def main() -> int:
    src, marks_path, out = sys.argv[1:4]
    lines = open(src, encoding="utf-8").read().split("\n")
    marks = json.load(open(marks_path, encoding="utf-8"))["insert"]
    # Apply from the end so earlier indices stay valid; stable for several inserts at one index.
    for index, text in sorted(enumerate(marks), key=lambda m: (m[1][0], m[0]), reverse=True):
        lines.insert(text[0], text[1])
    open(out, "w", encoding="utf-8").write("\n".join(lines))
    print(f"marked {src} -> {out}  ({len(marks)} marker lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
