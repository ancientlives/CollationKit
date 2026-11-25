# Testing

```sh
swift test                                   # the whole suite (200+ tests, a few seconds)
swift test --filter MoveRecoveryTests        # one suite
swift test --filter ConformanceTests/testGoldensMatchOrRecord   # one test
python3 -m pip install -r docs/conformance/requirements.txt && python3 docs/conformance/validate.py
```

The suite is the project's specification in executable form. Three kinds of test matter most:

- **Behavioural suites** pin what the engine reports for a given input (typed variants, citations, moves).
- **The conformance corpus** ([`docs/conformance/`](../conformance/)) pins the exact `--json` output,
  byte for byte, for 29 language-neutral cases. Goldens are never edited by hand. If a change alters a golden,
  that is a behaviour change: it must be justified, regenerated deliberately, and called out in the pull
  request (see [`CONTRIBUTING.md`](../../CONTRIBUTING.md)).
- **Property tests** run seeded fuzzing over invariants such as determinism and self-collation being empty.

The docs deliberately don't quote an exact test count, so adding a test needs no doc change. If you add a new
suite (an `XCTestCase` class), add a row for it to the table below.

During development the viewer's JavaScript was also checked in a headless browser (Playwright + WebKit); that
harness is not part of the repository.

## Suites

The suites:

| suite | covers |
|-------|--------|
| `TokenizerTests` | word/punctuation segmentation, normalisation (substantive vs accidental), GB/US folding, page/line/word coordinates |
| `AlignmentTests` | Needleman–Wunsch operations; anchor detection, LIS, transposition segmentation |
| `CollationTests` | pairwise classification: typed insertion/deletion/substitution, a reworded clause as one substitution, accidental suppression |
| `PunctuationTests` | the diplomatic punctuation overlay (`recordPunctuation`): comma drops and `:`→`;` reported as accidentals; the substantive apparatus byte-identical with it off; a real *Frankenstein* passage |
| `LiteraryEditionsTests` | the six-edition scenario (manuscript → typescript → proofs → GB 1st → US 1st → Uniform): a cross-page move, spelling-only GB/US differences, a genuine substantive revision, an N-witness graph |
| `RecursiveAnchoringTests` | move with internal edit; bounded-gap bridging; `resync` helpers |
| `MoveRecoveryTests` | single-word and short-phrase move recovery; block coalescing; `certain` vs `likely` confidence; no false moves; the rarity/locality gate; the anchor-path distinctiveness gate (a short phrase unique in both witnesses by coincidence is not a move, while a long relocated passage survives, as in the Whitman *Calamus* case), recalibrated across four full-novel translation pairs; scale-relative move confidence for the irreducible near-diagonal residual |
| `LocationTests` | `TextLocation` page/line/word span; single word vs range; character-range highlight |
| `PaginationTests` | the three page models × two line-numbering policies; citations follow the model |
| `LexicalDiversityTests` | adaptive anchoring; banded NW equals full NW within the band; auto-widening; bounded cost |
| `RenderingTests` | apparatus, synopsis, located report; sigla grouping |
| `NarrativeTests` | the `CollationNarrative` prose summary: extent, dominant kind, clustering, moves, alignment verdict |
| `GraphInsertionTests` | pure insertions anchored into the N-witness graph as inserted nodes (B6c) |
| `CollateCLITests` | the `collate` core: flag parsing and validation, witness discovery and ordering, text/JSON/CSV exporters (JSON export equals the conformance golden), dispatch and exit codes, determinism |
| `MenuTests` | the interactive menu driven by a scripted console (no TTY): defaults, subsets, base, export, quit/EOF, re-asking when fewer than two witnesses |
| `DirectoryBrowserTests` | the menu's directory picker: listing, navigation, the "use this folder" guard, typed paths, cancel |
| `TokenGraphTests` | the base-anchored token-graph merge (B11): moves as edges, off-spine insertions, determinism, projection parity |
| `CollationStrategyTests` | the selectable merge-strategy seam: availability, context-aware default, `--strategy` parsing |
| `PeerMSATests` | the peer merge (B14): recurring-word moves `certain` from structure, shared insertions grouped across non-base witnesses, stability under witness reordering, parity with the base-anchored merge on simple sets |
| `HTMLExportTests` | the `collation.html` viewer: payload embedding and escaping, determinism, always exported, `--format html`, progress output |
| `LexiconTests` | translation-aware anchoring (B10): lexicon file format, empty lexicon is byte-identical, French↔English anchoring, the trilingual Verne graph |
| `ScoringPresetTests` | the verse/prose scoring presets (B7): `.prose` equals the historical default, `.verse` aligns a reworded line as delete+insert |
| `CollationJSONTests` | the JSON interchange: shape, round-trip, byte-stable output |
| `ConformanceTests` | the golden corpus: every golden reproduces, output is deterministic, goldens match the JSON Schema |
| `PropertyTests` | seeded fuzzing over invariants, including the regression guards for two inverted-`Range` crashes found on full novels |
| `PerformanceTests` | scale and determinism on 2k–4k-token inputs |
