# Changelog

All notable changes to CollationKit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Until 1.0 the Swift API may change between minor versions; the JSON
interchange has its own `schemaVersion` (currently 3). The design history behind each change is in
[`docs/development/DEVELOPMENT_LOG.md`](docs/development/DEVELOPMENT_LOG.md).

## [0.3.0] — Unreleased (research preview)

The first tagged release. It fixes the release blockers found by the October 2026 review
([`docs/development/review-2026-10/`](docs/development/review-2026-10/README.md)).

### Fixed

- **Real differences were silently missing from the apparatus.** Anchors could share tokens in the compared
  witness, so text was matched twice and the base text it displaced was never reported. No token of either witness
  is now used twice. (B1)
- **The default multi-witness apparatus invented and dropped readings**, pairing words with punctuation
  (`green] ,`) and discarding compared words past the base's length. (B2)
- **Moved passages were missing from the critical apparatus.** They now appear as `(moved)` or `(possible move)`
  entries. (B3)
- **Characters above U+FFFF were dropped** (rare CJK, historic scripts, mathematical letters, emoji), so changes to
  them were not reported. (B4)
- **Quotation marks, apostrophes and dashes were treated as parts of words**, so GB vs US quotation, `don't` vs
  `don’t`, and `--` vs `—` were substantive variants. (B5)
- **`no_collate` regions leaked excluded text** (the two-comment form, nested page-break comments, page breaks inside
  a region). (B6)
- **Translation lexicon entries with accents never matched**, and CRLF lexicon files were misread. (B7)
- **Some text was reported twice**: a word moved out of a deletion's middle, edits on both sides of a moved block, and
  diplomatic punctuation. (B8)
- **Two tests asserted nothing.** (B9)
- **Viewer:** witness file names could inject script (B11); a witness containing `<!--<script` blanked the page (B12);
  the Changes tab froze Safari for over a minute on a full novel (B15).
- **CLI:** duplicate witness ids were accepted (B13); the menu ran the collation when you answered "no"; a mistyped base
  was caught only after confirming; an unwritable `--out` was found only after collating; `collate --no-input run` and
  `collate run --help` failed. (B14)

### Changed

- The CLI version and `CITATION.cff` agree (0.3.0), and a test keeps them in step. (B10)
- `--lexicon`, `--lines-per-page` and `--through-numbered` are labelled experimental.
- The docs no longer quote an exact test count; `TestCountGuardTests` is retired (it blocked Linux).

### Deprecated

- `collate-demo`: use `collate run …` or the `collate` menu. It will be removed in 0.4.

### Added

- `CHANGELOG.md`, `SECURITY.md` and an input-format guide (`docs/guides/INPUT_FORMAT.md`).
- Regression suites for every fix above.

## [0.1.0] — 2026-09-25

First public release of the repository: the engine, the `collate` CLI, the interactive HTML viewer, the conformance
corpus and JSON Schema, the Verne evaluation corpus, the documentation and the project website.

[0.3.0]: https://github.com/ancientlives/CollationKit/compare/5da491c...main
[0.1.0]: https://github.com/ancientlives/CollationKit/commit/5da491c
