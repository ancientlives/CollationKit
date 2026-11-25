# Contributing to CollationKit

Thank you for your interest. CollationKit is a research project: contributions of code, evaluation data,
documentation, bug reports, and research questions are all welcome. This guide explains how to propose a
change and what the project expects of one.

If you are new, read [`docs/RESEARCH_INTRO.md`](docs/RESEARCH_INTRO.md) and
[`docs/ONBOARDING.md`](docs/ONBOARDING.md) first. They explain what the engine does, why it is not `diff`, and
how the code is organised.

## Ways to contribute

- **Report a bug.** Open an issue with the *Bug report* template. The most useful bug reports include the
  witness texts (or a minimal excerpt), the exact command, and what you expected versus what you got.
- **Report a collation that looks wrong.** A false move, a missed move or a mis-cited variant on a real text is
  valuable evaluation data. Use the *Collation result looks wrong* template.
- **Propose a feature or research direction.** Open an issue first so the approach can be discussed before
  you invest time. Check [`docs/development/BACKLOG.md`](docs/development/BACKLOG.md) and the ranked
  candidate list in [`docs/reference/ALGORITHM_SURVEY.md`](docs/reference/ALGORITHM_SURVEY.md) Part II:
  your idea may already be analysed there.
- **Improve the documentation.** Fixes for unclear or stale docs are always welcome, and can go straight to a
  pull request.
- **Add evaluation material.** New public-domain witness sets for `corpus/` or new conformance cases.

## Workflow

All changes to `main` go through a pull request. Direct pushes to `main` are blocked.

1. **Fork** the repository (or, if you are a collaborator, create a branch in it).
2. **Create a branch** from `main` with a descriptive name: `fix/inverted-range-in-region`,
   `feature/cjk-tokeniser`, `docs/onboarding-typos`, `research/sentence-anchors`.
3. **Make your change** in small, focused commits. Write commit messages in the imperative mood, with a
   short summary line (for example, `Clamp region spans so overlapping anchors yield an empty gap`) and a body
   explaining *why* when it isn't obvious.
4. **Run the checks locally** (see below).
5. **Open a pull request** against `main` and fill in the template. Link the issue it addresses.
6. **CI must pass.** GitHub Actions builds the package, runs the full test suite on macOS, and validates the
   conformance goldens against the JSON Schema.
7. **Review.** A maintainer will review the change. Expect questions, especially about behaviour changes and
   evidence. Address feedback with new commits (don't force-push during review, so the conversation stays
   readable). The maintainer squash-merges when it is ready.

Draft pull requests are welcome for early feedback on work in progress.

## Local checks

```sh
swift build
swift test                               # must report 0 failures
python3 -m pip install -r docs/conformance/requirements.txt
python3 docs/conformance/validate.py     # goldens conform to the JSON Schema
```

For anything touching performance or the full-novel behaviour, also run a release build on the Verne corpus:

```sh
swift build -c release
.build/release/collate run corpus/verne/mysterious-island/full/{kingston,white}.txt --out /tmp/ck-out
swift run -c release collate-bench       # the benchmark sweep (see docs/development/BENCHMARKS.md)
```

## The engine's invariants

These are the rules that keep the engine trustworthy as a scholarly instrument. A pull request that breaks
one will not be merged without a very good argument.

1. **Purity.** `Sources/CollationKit/` does no I/O, has no UI code and no global mutable state. It is a pure
   function from witnesses and options to results. File handling, terminals and HTML live in `CollateCLI`.
2. **Determinism.** The same input must give byte-identical output, on every run and every machine. No
   dependence on hash iteration order, dates, randomness or locale. See the determinism rules in
   [`docs/reference/ALGORITHMS.md`](docs/reference/ALGORITHMS.md) §9.
3. **The dependency direction is one-way.** `collate` → `CollateCLI` → `CollationKit`. The engine never
   imports the CLI. The package has no third-party dependencies; please discuss before adding one.
4. **Never hand-edit a golden.** Files in `docs/conformance/golden/` are produced by the engine. If your change
   alters them, that is a behaviour change. Regenerate them deliberately:
   ```sh
   COLLATION_RECORD=1 swift test --filter Conformance
   git diff docs/conformance/golden/
   ```
   Then explain in the pull request, case by case, why each golden changed and why the new output is more
   correct. Changes to goldens get the closest review of anything in this project.
5. **Words are reported, never rewritten.** Normalisation, lexicons and any future semantic layer may only
   influence *alignment*. The apparatus always shows each witness's own words.
6. **Evidence over intuition.** A change to alignment or move detection should show its effect on the
   conformance corpus and, where relevant, the real-edition cases
   ([`docs/development/CASE_STUDY.md`](docs/development/CASE_STUDY.md)) and the Verne full novels. Negative
   results are worth recording too.
7. **Machine learning is gated.** Read the project's position in [`docs/RESEARCH_INTRO.md`](docs/RESEARCH_INTRO.md)
   §4.1 and [`docs/reference/PAPER_NOTES.md`](docs/reference/PAPER_NOTES.md) Appendix A before proposing any
   learned component. In short, it may only ever add anchoring information or confidence, and must stay
   deterministic, auditable and optional.

## Tests

- Every behaviour change or bug fix comes with a test that fails before the change and passes after.
- Put the test in the suite that matches the area (see [`docs/development/TESTING.md`](docs/development/TESTING.md)).
- If you add a test suite (a new `XCTestCase` class), add a row for it to the suite table in
  `docs/development/TESTING.md`. The docs deliberately don't quote an exact test count, so adding tests needs no
  other doc changes.

## Code style

- Match the surrounding code. Swift API Design Guidelines naming; value types by default; `enum` namespaces
  for pure functions.
- Doc-comment public API with `///`. Explain *why* a non-obvious choice was made, especially any threshold or
  tuning constant. Many constants in `Transposition.swift` carry a comment recording the evidence behind
  them; keep that practice.
- Keep lines to about 120 characters.
- No new warnings.

## Documentation conventions

The docs are part of the research record, so they are kept current alongside the code:

- A **new feature or behaviour change** gets a dated entry in
  [`docs/development/DEVELOPMENT_LOG.md`](docs/development/DEVELOPMENT_LOG.md), and updates to the specification
  in [`docs/reference/ALGORITHMS.md`](docs/reference/ALGORITHMS.md) and
  [`docs/reference/PAPER_NOTES.md`](docs/reference/PAPER_NOTES.md).
- A **new document** is filed in the right `docs/` subdirectory and added to [`docs/INDEX.md`](docs/INDEX.md).
- **Backlog items** are referenced by their IDs (B6, B12, …) from
  [`docs/development/BACKLOG.md`](docs/development/BACKLOG.md). When you finish one, move it to the done ledger.
- `ALGORITHMS.md` is the portability contract: if you change an algorithm's behaviour, update its pseudocode.

## Adding corpus material

Only public-domain or openly licensed texts can be added. Check each text's copyright status on its source page: not every
Project Gutenberg text is public domain (the F. P. Walter translation, PG2488, is in copyright and is therefore
rebuilt locally rather than committed; see `corpus/verne/README.md`). Record provenance (source, edition, translator,
retrieval date, licence) in the case's `meta.json`, and strip any distributor licence headers the way
`corpus/verne/scripts/clean_gutenberg.py` does. Keep witness files to the text alone: no title or provenance
lines, since those would be tokenised as words.

## Licensing of contributions

By submitting a pull request you agree that your contribution is licensed under the project's licences: code
under [MIT](LICENSE), documentation under [CC BY 4.0](LICENSE-docs.md).

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
