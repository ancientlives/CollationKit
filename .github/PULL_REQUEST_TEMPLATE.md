## Summary

<!-- What does this change, and why? Link the issue it addresses, e.g. "Closes #12". -->

## Type of change

- [ ] Bug fix
- [ ] Engine behaviour change (alignment, move detection, classification, citation)
- [ ] New feature (CLI, viewer, export, interchange)
- [ ] Documentation
- [ ] Evaluation material (corpus, conformance case)
- [ ] Refactor, performance or tooling (no behaviour change)

## Evidence

<!-- For behaviour changes: what did you run, and what changed? For example, false moves on the Verne full
novels before and after, benchmark numbers, or a case-study excerpt. For a bug fix: the failing input. -->

## Conformance goldens

- [ ] No golden in `docs/conformance/golden/` changed.
- [ ] Goldens changed. Each change is regenerated with `COLLATION_RECORD=1` (never hand-edited) and
      explained case by case below.

## Checklist

- [ ] `swift test` passes locally with 0 failures.
- [ ] New or changed behaviour has a test that fails without this change.
- [ ] The engine stays pure and deterministic (no I/O, no randomness, no ordering from hashing).
- [ ] If the test count changed, `TestCountGuardTests`, `README.md`, `docs/development/TESTING.md` and the
      development log `State:` line are updated.
- [ ] Docs are updated where needed (`DEVELOPMENT_LOG.md` entry; `ALGORITHMS.md` / `PAPER_NOTES.md` for
      algorithm changes; `docs/INDEX.md` for a new doc).
