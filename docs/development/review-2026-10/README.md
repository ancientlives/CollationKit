# Release 1 review (October 2026)

A review of the whole project (code, tests, documentation, notes and research direction) to decide what
forms the core of a first release, what is not ready yet, and what belongs to later releases.

**Status:** in progress.

## Files

| File | Contents |
| --- | --- |
| [`baseline.md`](baseline.md) | The measured state of the repository at review time |
| `engine.md` | Engine code review (bugs, dead code, spec mismatches, API for 1.0) |
| `cli-viewer.md` | CLI and HTML viewer review |
| `tests.md` | Test suite, conformance corpus and CI review |
| `docs-audit.md` | Documentation audit (keep, update, archive, remove) |
| `research.md` | Research topics for the next phase, with references |

The summary and recommendations will be added to this file once the individual reviews are complete.

## Method

1. The baseline was measured directly: clean build, warnings, tests, schema validation and sizes.
2. Five independent reviews ran in parallel, each read-only, each reproducing suspected bugs where possible.
3. Their findings were checked, and the important ones re-verified before inclusion here.
