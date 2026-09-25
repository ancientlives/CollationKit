#!/usr/bin/env python3
"""Validate the conformance goldens against collation.schema.json (BACKLOG B2).

A language-neutral check that every golden in `golden/` conforms to the JSON Schema for the CollationKit
interchange — usable on any system and by any port, independent of the Swift test suite. The Swift tests
already assert conformance structurally (ConformanceTests.testGoldensConformToInterchangeShape); this script
is the literal JSON-Schema validation and the cross-language reference check.

Setup (see requirements.txt):

    python3 -m venv .venv && . .venv/bin/activate
    pip install -r docs/conformance/requirements.txt

Run:

    python3 docs/conformance/validate.py        # validates every golden; exit 0 iff all pass
"""
import glob
import json
import os
import sys

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit("jsonschema not installed — run: pip install -r docs/conformance/requirements.txt")

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> int:
    schema = json.load(open(os.path.join(HERE, "collation.schema.json")))
    Draft202012Validator.check_schema(schema)               # the schema itself is well-formed
    validator = Draft202012Validator(schema)

    goldens = sorted(glob.glob(os.path.join(HERE, "golden", "*.json")))
    if not goldens:
        sys.exit("no goldens found — run: COLLATION_RECORD=1 swift test --filter Conformance")

    failures = 0
    for path in goldens:
        instance = json.load(open(path))
        errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.path))
        name = os.path.basename(path)
        if errors:
            failures += 1
            print(f"FAIL  {name}")
            for e in errors[:5]:
                print(f"        at {list(e.path)}: {e.message}")
        else:
            print(f"ok    {name}")

    print(f"\n{len(goldens)} goldens validated, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
