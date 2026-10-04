# Release 1 review (October 2026)

A review of the whole project (code, tests, documentation, notes and research direction) to define the core of a
first tagged release, what is not ready yet, and what belongs to later releases.

**Status:** complete, for the maintainer's review, 3 October 2026. Nothing here has been acted on yet.

## 1. Verdict

- **The architecture is sound and the project is unusually well documented and tested.** The engine builds with
  no warnings, 222 tests pass, line coverage is 92.6%, the conformance corpus is byte-stable, and everything
  builds and passes on Linux too (Swift 5.9 and 6.1), apart from one test file.
- **But the engine has correctness bugs that silently produce a wrong apparatus.** Fuzzing found no crashes;
  the failures are quiet. Some differences between witnesses are never reported, and some reported readings are
  wrong. For a tool whose purpose is a citable record of every variant, these are release blockers (section 3).
- **The scripted CLI is in good shape; the HTML viewer is not yet shippable.** Three small viewer defects break,
  compromise or freeze it, one of them a script-injection route through witness filenames.
- **Recommendation:** make the first tagged release a **research preview, v0.3.0**, once the blockers are fixed
  and the documentation is reorganised. Reserve **1.0** for when the Swift API, the JSON schema and the
  conformance contract are deliberately frozen (section 5).

## 2. Release 1 (v0.3.0, research preview): the core

| Area | In release 1 | Condition |
| --- | --- | --- |
| Pairwise collation: tokeniser, normaliser, pagination and citations, alignment, move detection with `certain` / `likely` confidence, classification | Yes, the heart of the release | Fix blockers B1, B4, B5, B6, B8 |
| N-witness merge, base-anchored (default) | Yes | Fix B2 |
| N-witness merge, peer (`--strategy peer-msa`) | Yes, documented as an approximation of full graph alignment | None |
| Apparatus, synopsis, located report | Yes | Fix B3 (apparatus omits moves) |
| JSON interchange (schema v3), JSON Schema, conformance corpus (29 cases), `validate.py` | Yes, the portability contract | Tighten the schema; add the missing cases (section 7) |
| `collate` CLI: `run`, `list`, interactive menu; text, JSON, CSV and HTML output | Yes | Fix B13, B14 |
| Interactive HTML viewer (eight views) | Yes, with documented limits for full novels and accessibility | Fix B11, B12, B15 |
| Verne corpus (four works; excerpts and full novels) and its build script | Yes | Refresh the stale figures |
| Documentation: README, RESEARCH_INTRO, ONBOARDING, CONTRIBUTING, TESTING, ALGORITHMS, PAPER_NOTES, ALGORITHM_SURVEY, COMPARISON, CASE_STUDY, BENCHMARKS, conformance and corpus READMEs | Yes | Updates and reorganisation in section 6 |
| macOS 13+; Linux | macOS supported; Linux "builds and passes tests, not yet in CI" | Linux CI is a 0.4 item |

## 3. Release blockers (fix before tagging)

All of these were reproduced with minimal inputs during the review; the most serious (B1–B5, B9–B12) were re-verified
independently. Details and reproductions are in the linked files.

| # | Problem | Severity | Where | Evidence |
| --- | --- | --- | --- | --- |
| B1 | **Real differences are silently lost.** Shared anchor phrases are de-duplicated on the base side only, so a compared word can be matched twice. `alpha beta gamma delta epsilon beta gamma zeta` vs `alpha beta gamma zeta` reports only "delta epsilon" deleted. | High | `Transposition.swift` | engine A1 |
| B2 | **The default N-witness apparatus drops or invents readings.** `red green` → `blue, yellow` gives `green] ,`; `red` → `very bright blue` loses "bright blue". The peer merge gets both right. | High | `TokenGraph.swift` | engine A2 |
| B3 | **The critical apparatus omits transpositions entirely.** A move-only collation prints "(no points of variance)"; the six-edition case leaves out its cross-page move. | High | `Apparatus.swift` | docs-audit, incidental |
| B4 | **Characters outside the Basic Multilingual Plane are silently dropped** (rare CJK, mathematical letters, emoji): `𠀀` → `𠀁` reports no variants. | High for a scholarly tool | `Tokenizer.swift` | engine A5, tests |
| B5 | **Quote and apostrophe styles count as changes of wording** (`'yes'` vs `"yes"`, `don't` vs `don’t`, `--`). | High | `Tokenizer.swift` | engine A4 |
| B6 | **`no_collate` regions leak excluded text** in three ways (the two-comment form, an inner page-break comment, a `---` inside). | Medium | `Tokenizer.swift` | engine A8 |
| B7 | **The translation lexicon never matches accented forms** under the default normaliser, so the documented `année, year` example does nothing; CRLF lexicon files fail silently. | High for cross-language use | `TranslationLexicon.swift` | engine A3, A10 |
| B8 | **`--diplomatic` reports every punctuation change twice**; a recovered single-word move is reported twice; moved blocks can overlap. | Medium | `Variation.swift`, `Transposition.swift` | engine A6, A7, A9 |
| B9 | **Two tests assert nothing** (one loops over an empty list and takes 68% of the suite's time; one compares identical texts). | Medium (false confidence) | `MoveRecoveryTests:302`, `PerformanceTests:73` | tests B |
| B10 | **Version and licence inconsistencies.** `collate --version` says 0.2.0, `CITATION.cff` says 0.1.0, and there are no tags. The Walter licence notice does not cover the published `verne-trilingual` demo, which contains the same 87-word paragraph. | Release hygiene | `CollateCLI.swift`, `CITATION.cff`, `LICENSE-docs.md` | docs-audit A |
| B11 | **Script injection in the viewer.** Witness ids come from filenames and are inserted into `innerHTML` unescaped, so a file named `<img onerror=…>.txt` runs script when the page opens. A file named `%%DATA%%.txt` pastes the data payload into the page. | High (security) | `HTMLExport.swift:1231`, `:2035`, `:2118` | cli-viewer D |
| B12 | **A witness containing `<!--<script` blanks the whole viewer** with no error, because the embedded data escapes only `</`. Escaping `<`, `>` and `&` fixes it. | High | `HTMLExport.swift:266` | cli-viewer D |
| B13 | **Duplicate witness ids are accepted silently.** `e1818/text.txt` and `e1831/text.txt` both become `text`, corrupting the reports and viewer tabs (the engine accepts duplicate sigla too). | High | `WitnessLoader.swift`, engine | cli-viewer A, tests |
| B14 | **The menu runs the collation when you answer "no"** (or stdin ends) at the confirm prompt; a mistyped base is caught only after confirming. An unwritable `--out` is detected only after the whole run. | Medium | `Menu.swift`, `CollateCLI.swift` | cli-viewer A |
| B15 | **The Changes tab freezes Safari for about a minute on a full novel** (0.7 s in Chromium), caused by `opacity` on about 26,000 spans. | Medium | `HTMLExport.swift:541` | cli-viewer D |

## 4. Not ready for release 1

Ship these as **experimental** (clearly labelled in `--help`, README and docs), or leave them out:

| Item | Why | Recommendation |
| --- | --- | --- |
| Cross-language collation (`--lexicon`) | Broken for accented forms (B7). Even when fixed, it is a small hand-made lexicon validated on one paragraph. | Fix B7, then label **experimental** |
| Prose narrative (`summary.txt`, the viewer's Story view) | Numbers depend on the machine's locale; it claims accidentals were "checked" when they were off; one wording bug. | Fix the false claim; label **experimental** |
| `--scoring verse` | Works, but validated only on synthetic cases and one Whitman pair. | Keep; document its limits |
| `--lines-per-page` / `--through-numbered` | Page-break markers become text under these models (engine A11). | Fix, or label **experimental** |
| `collate-demo` executable | Superseded by `collate`; silently falls back to the built-in sample when given one file; its JSON differs from `collate`'s despite comments saying otherwise. | **Deprecate** in release 1 (point to a `collate` sample command); remove in 0.4 |
| Viewer on full novels | Usable but slow: a 70 MB page; the text tab takes 3–6 s and the parallel tab 6–9 s; a span click takes about 1 s. The full run takes 19 s and 1.3 GB of memory. | Ship with a documented limit; speed work in 0.4 |
| Viewer accessibility | Only tab buttons and checkboxes take keyboard focus; no ARIA; variation type shown by colour alone; two greys fail contrast. | Document as a known limitation; keyboard, ARIA and contrast pass in 0.4 |
| `collate --no-input run …`, `collate run --help` | Documented but fail. | Fix, or remove from the docs |
| CJK and other unsegmented scripts (B6) | Whole sentences become one token. | Document as **not supported** |

## 5. Future releases

| Release | Theme | Main content |
| --- | --- | --- |
| **0.4** | Robustness, platform and viewer | Viewer keyboard/ARIA/contrast pass and full-novel speed (quadratic text slicing, list rebuilt on each tab switch, a smaller payload); Linux in CI (Swift 5.9 and 6.x); remove `TestCountGuardTests`; schema tightening and the missing conformance cases; `.gitattributes`; performance hot spots (`projectedVariantGraph` O(N²) → linear; O(P²) spine selection → O(P log P); the NW bound); remove `collate-demo` and the dead code |
| **0.5** | Library API | One `CollationOptions` value; validation that `throws`; a smaller public surface (238 public declarations today); `Sendable`; an enum for omitted readings instead of the `"∅"` sentinel; a `diagnostics` field reporting fallbacks and gated moves; original-text readings rather than space-joined tokens; a library guide |
| **0.6** | Interoperability | TEI P5 apparatus export that keeps located transpositions and confidence (backlog B12; research I1); a CLI guide and viewer guide |
| **1.0** | Stability | A frozen public API, schema and conformance contract; a written versioning policy |
| **After 1.0** | Research-led features | Sentence-aligned cross-language anchors (B17), witness profiles (B15), corpus-wide move confidence (B16), partial-order alignment as a third merge strategy, CJK segmentation (B6), a corpus-publishing tool, a standalone or WASM engine |

## 6. Remove, deprecate or archive

**Code**

- Remove `Collation.legacyVariantGraph` (about 110 unreachable lines that share bug B2) and its duplicated
  substitution-fold logic.
- Remove `Normalizer.foldWhitespace` (never read), the unused `spine` and `side` parameters, and the dead
  `CollationStrategy.isAvailable` fallback.
- Decide on `pairByExpandingWindow`: production only ever uses it as two thresholds; either simplify it, or make the
  spec (ALGORITHMS §5.6, §9.8) describe what actually runs.
- Deprecate `collate-demo`.

**Tests**

- Fix or remove the two empty tests (B9).
- Remove `TestCountGuardTests`. It blocks Linux, cannot see Swift Testing tests, and two green pull requests
  that each add a test leave `main` red. Stop quoting exact test counts in the docs, or regenerate them at
  release time.

**Documentation** (from the docs audit)

- **Archive** (move to `docs/archive/` with a "historical, shipped" banner): `CLI_PLAN.md`,
  `TOKEN_GRAPH_PLAN.md`, `VIEWER_UX_PLAN.md`. Keep their still-normative parts by moving CLI_PLAN §0 (layering)
  and the viewer constraints into the new guides, and the change-landing discipline into CONTRIBUTING.
- **Move to `docs/proposals/`**: `CORPUS_PLAN.md`, `porting/RUST_STANDALONE_PLAN.md` (whose reuse list is also
  stale).
- **De-duplicate**: RESEARCH_INTRO §4 and ONBOARDING §6 are near-copies; the vocabulary appears three times and the
  document map four. Keep one of each, in a new `GLOSSARY.md` and in INDEX.
- **Fix stale facts**: BENCHMARKS (tables predate the token-graph and peer merges; "six export files" should be
  seven); corpus README alignment figures; CASE_STUDY and COMPARISON still describing resolved items as open; the
  test-count-guard claim in INDEX and ONBOARDING; the ONBOARDING `contextualDefault` claim.
- **DEVELOPMENT_LOG**: keep it as the historical record, but add a table of contents and an "eras" summary, and
  record the public release.
- **Add for release 1**: CHANGELOG, a short versioning and release policy, SECURITY (the viewer embeds witness
  text in HTML), an input-format guide (including the warning that a stand-alone `---` becomes a page break).
  A library guide, CLI guide and viewer guide follow in 0.5 and 0.6.

## 7. General improvements (not blockers)

- **Conformance contract:** add cases for the diplomatic normaliser, `no_collate`, form-feed and `---` page breaks,
  NFC vs NFD, non-BMP text, empty and single witnesses; write down the JSON byte format and sort order a port must
  reproduce; tighten the schema (it accepted 14 of 17 deliberately invalid goldens); make `validate.py` open files as
  UTF-8 and accept a port's own output directory.
- **CI:** add Linux (5.9 and 6.x), pin the Xcode version, run tests in release mode too, check the CLI against
  every golden it can express, and syntax-check the viewer's JavaScript.
- **Tests:** replace force unwraps that crash the whole test process; drop wall-clock limits; guard against
  `COLLATION_RECORD=1` being left set; add tests for `list`, `--lexicon` loading, `--lines-per-page` and every
  `WitnessLoader` error.
- **Engine transparency:** variations are returned with all transpositions first rather than in text order; sort
  them, or document the order.

## 8. Research topics for the next phase

Full detail, first experiments and a verified bibliography are in [`research.md`](research.md). In brief, with
the principle **measurement before mechanism**:

1. **Instruments first:** a labelled gold standard of moves with a leave-one-pair-out calibration protocol (V1), and
   a synthetic benchmark that maps where move detection is reliable (V2).
2. **TEI export** that keeps located transpositions (I1). This is the adoption win, and it is independent of the
   rest.
3. **A principled move criterion** from genome alignment (collinear blocks over maximal unique matches) to replace
   three hand-tuned gates (E1).
4. **Additive ML as declared sidecar files:** sentence alignment for French↔English (M1); then whether the
   containing sentences correspond, as a new signal for the irreducible near-diagonal cases (M2). Models run
   offline; the engine reads their output like a lexicon and stays deterministic.
5. **Human studies:** a task-based evaluation of the eight views with an accessibility audit (H2), then how to show
   `likely` moves to an expert who can overrule them (H1).

If only three are done: V1, I1 and H1.

## 9. Suggested order of work

Each step is roughly one pull request:

1. Fix B1 (anchor de-duplication) with a regression test, and re-record any affected goldens with case-by-case
   justification.
2. Fix B2 by retiring the base-anchored substitution fold in favour of the peer merge's handling, or by porting
   it; remove `legacyVariantGraph`.
3. Fix B3 (moves in the apparatus).
4. Fix B4 and B5 in the tokeniser and normaliser, with new conformance cases.
5. Fix B6, B7 and B8.
6. Fix the tests (B9), remove `TestCountGuardTests`, and fix the test warnings.
7. Fix the viewer: escaping (B11, B12) with injection tests, and the Safari freeze (B15).
8. Fix the CLI: reject duplicate witness ids (B13); the menu confirm, base check and early `--out` check (B14).
9. Version and licence hygiene (B10); CHANGELOG; SECURITY; input-format guide.
10. Reorganise the documentation (section 6) and refresh the stale figures and benchmarks.
11. Regenerate the site demos, tag **v0.3.0**, and publish a GitHub release.

## Files

| File | Contents |
| --- | --- |
| [`baseline.md`](baseline.md) | The measured state of the repository at review time |
| [`engine.md`](engine.md) | Engine code review: 18 confirmed bugs, dead code, spec mismatches, API for 1.0, performance |
| [`cli-viewer.md`](cli-viewer.md) | CLI and HTML viewer review: defects, full-novel measurements, accessibility, release verdict |
| [`tests.md`](tests.md) | Test suite, conformance corpus and CI review |
| [`docs-audit.md`](docs-audit.md) | Documentation audit (keep, update, archive, remove), missing documents, backlog triage |
| [`research.md`](research.md) | Research agenda for the next phase, with a verified bibliography |

## Method

1. The baseline was measured directly: clean build, warnings, tests, schema validation and sizes.
2. Five independent reviews ran in parallel, each read-only, each reproducing suspected bugs with minimal inputs.
3. The most serious findings (B1–B5, B9–B12) were re-verified independently before inclusion here.
