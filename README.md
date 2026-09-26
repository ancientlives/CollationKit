<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="site/assets/logo/collationkit-logo-dark.svg">
    <img src="site/assets/logo/collationkit-logo-light.svg" alt="CollationKit" height="48">
  </picture>
</h1>

[![CI](https://github.com/ancientlives/CollationKit/actions/workflows/ci.yml/badge.svg)](https://github.com/ancientlives/CollationKit/actions/workflows/ci.yml)
[![Code licence: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Docs licence: CC BY 4.0](https://img.shields.io/badge/docs-CC%20BY%204.0-lightgrey.svg)](LICENSE-docs.md)

**A pure-Swift engine for scholarly textual collation.** Give it several versions (*witnesses*) of one work,
such as a manuscript, proofs, a first edition, a revised edition, or rival translations. It reports every
**insertion, deletion, substitution and transposition** (moved passage, including one that crosses a page
boundary), each with a scholarly citation (page, line, word). It is explicitly **not** a line-oriented `diff`.

- **Website and live viewer demos:** <https://ancientlives.github.io/CollationKit/>
- **New here? Start with** [`docs/RESEARCH_INTRO.md`](docs/RESEARCH_INTRO.md) (the research context), then
  [`docs/ONBOARDING.md`](docs/ONBOARDING.md) (build, run, code map, first week).
- **Want to contribute?** See [`CONTRIBUTING.md`](CONTRIBUTING.md).

The engine began as a standalone prototype of the collation component for a native macOS markdown editor. It
is deliberately isolated and pure: no UI code, no file I/O, value-type input and output, and a deterministic
function of its inputs. That makes it a research vehicle you can test, benchmark and reason about without an
application around it.

## Why this isn't `diff`

- It aligns **words and phrases**, not lines, because prose reflows and passages move across pages.
- **Needleman–Wunsch** alignment scores substitutions, so a reworded clause is one substitution, not a deleted
  block plus an inserted block.
- An **anchor and transposition** pass recognises a passage that *moved* (even across a page) as a single
  transposition and flags `crossesPage`. A line diff would report a deletion here and an insertion there.
- **Normalisation** separates *substantive* variants (real wording changes) from *accidentals* (spelling,
  punctuation, capitalisation), so GB/US spelling differences don't drown the apparatus.
- Every finding carries a **citation**: `p. 12, line 4, words 3–5`.

## Quick start

Requirements: macOS 13 or later and a Swift 5.9+ toolchain (Xcode 15 or later). Python 3 is needed only for
the optional JSON Schema validator.

```sh
git clone https://github.com/ancientlives/CollationKit.git
cd CollationKit
swift test              # 222 tests
swift run collate-demo  # the six-edition example: full texts, located report, apparatus, synopsis
```

Collate your own files, or the bundled Verne corpus:

```sh
swift run collate run a.txt b.txt [c.txt …]      # first file = base witness → console report
swift run collate run --dir corpus/verne/journey-centre-earth --all --out ./results
open ./results/collation.html                    # the interactive viewer
swift run collate                                # interactive menu: browse to a folder, pick options, run
```

> **Full-length texts: build in release mode.** Plain `swift run` / `swift build` produce a *debug* binary that
> is many times slower; a full novel takes minutes and looks frozen.
> ```sh
> swift build -c release
> .build/release/collate run corpus/verne/mysterious-island/full/{kingston,white}.txt --out ./results
> ```
> Measured numbers are in [`docs/development/BENCHMARKS.md`](docs/development/BENCHMARKS.md).

## The `collate` command-line tool

`collate` with no subcommand opens an **interactive menu**. It is a directory browser that lists subfolders and
witness files, then lets you pick witnesses, base, order, mode, format and an output folder. `collate run …` is
the **scriptable** form, for CI and pipes.

```sh
swift run collate run --dir ./ed --base MS --order MS,TS,PR       # choose base + order
swift run collate run --diplomatic a.txt b.txt                    # also report spelling + punctuation accidentals
swift run collate run --format csv a.txt b.txt                    # one row per variant (RFC 4180)
swift run collate run --format json a.txt b.txt | jq .            # the {graph, pairs} JSON interchange
swift run collate run --format html a.txt b.txt > collation.html  # the interactive viewer
swift run collate run --strategy peer-msa a.txt b.txt c.txt       # base-free merge: best for rival translations
swift run collate run --strategy peer-msa --lexicon fr-en.lex fr.txt en1.txt en2.txt  # cross-language
swift run collate run --scoring verse a.txt b.txt                 # verse scoring preset (default: prose)
swift run collate list --dir ./editions                           # list discovered witness files
swift run collate --help
```

Progress goes to **stderr** and results to **stdout**, so piped `json`/`csv`/`html` output stays clean. An
exported `collation.json` is **byte-identical** to the conformance goldens (same code path).

`collate-demo` (the original demo harness) and `collate-bench` (the benchmark sweep:
`swift run -c release collate-bench`) are also included.

### The interactive viewer

Every export writes a self-contained `collation.html` (no network access, no dependencies). It has eight views
over one collation: an analytical **overview** dashboard, the annotated **text** of each witness, a **variant
graph**, **parallel** linked columns, a **changes** (redline) rendering, a prose **story** of how each witness
differs from the base, an **alignment map** for judging whether an alignment is sound, and a traditional
**apparatus**. Try the
[live demos](https://ancientlives.github.io/CollationKit/#demos).

## Pipeline

All engine code is in [`Sources/CollationKit/`](Sources/CollationKit/).

| File | Stage | Responsibility |
|------|-------|----------------|
| `Token.swift` | model | `Witness` and `Token`: surface and normalised forms, kind, character range, and page, text-line and word position. |
| `Tokenizer.swift` | 1: tokenise / normalise | Word/punctuation segmentation; citation coordinates driven by a `PaginationModel`; page detection (`\f`, `<!-- page break -->`, a stand-alone `---`); `<!-- no_collate -->` regions for editorial exclusion; the `Normalizer` (the substantive/accidental lever: case, accents, punctuation, GB↔US spelling). |
| `Pagination.swift` | 1: citation model | Page boundaries (`.markers`, `.linesPerPage(N)`, `.explicit(offsets)`) × line numbering (`.perPage`, `.continuous`). |
| `Alignment.swift` | 2: pairwise | Needleman–Wunsch global alignment over comparable tokens, plus a banded, auto-widening fallback. |
| `Transposition.swift` | 2: moves | Unique-common-anchor detection and a page-aware maximum-weight increasing subsequence for the stable spine; moved blocks reported once; recursive anchoring for edits *inside* a move; adaptive anchoring; move-confidence gates. |
| `Variation.swift` | 3: classify | Coalesces alignment operations into typed `Variation`s (insertion, deletion, substitution, transposition, variant spelling), each with readings and a `TextLocation` per side. |
| `Collation.swift` | facade | `Collation.collate(base:compared:)` (pairwise) and `Collation.variantGraph(witnesses:strategy:)` (N witnesses). |
| `TokenGraph.swift` | merge | The base-anchored merge: N−1 pairwise results lifted into one token graph (DAG). |
| `PeerMSA.swift` | merge | The peer merge: each witness aligns against a growing consensus, with no privileged base. |
| `TranslationLexicon.swift` | anchoring | Bilingual equivalence groups ("année" ≈ "year") so cross-language witnesses anchor to one another. |
| `Apparatus.swift` · `Synopsis.swift` · `Report.swift` | render models | The *apparatus criticus*, parallel synoptic table and located variant report. |
| `CollationJSON.swift` | interchange | A stable, versioned JSON schema decoupled from the Swift types. |

The CLI is in [`Sources/CollateCLI/`](Sources/CollateCLI/): a testable core with a thin
[`Sources/collate/`](Sources/collate/) shell. The dependency direction is one-way: `collate` → `CollateCLI` →
`CollationKit`.

## Repository layout

```
Sources/            the engine (CollationKit), the CLI core and shells, demo and benchmark harnesses
Tests/              222 XCTest tests across 27 suites (see docs/development/TESTING.md)
docs/               research intro, onboarding, algorithm specification, design history, evaluation
docs/conformance/   language-neutral golden corpus + JSON Schema: the executable portability contract
corpus/verne/       public-domain Jules Verne translation pairs (chapter excerpts + full novels) + build scripts
site/               the project website (GitHub Pages)
```

## Documentation

The full map is [`docs/INDEX.md`](docs/INDEX.md). Highlights:

- [`docs/reference/ALGORITHMS.md`](docs/reference/ALGORITHMS.md): a **language-neutral specification**
  (pseudocode, invariants, determinism rules, porting checklist).
- [`docs/reference/PAPER_NOTES.md`](docs/reference/PAPER_NOTES.md): the Swift-grounded algorithm reference
  (complexity, parameters, bibliography).
- [`docs/reference/ALGORITHM_SURVEY.md`](docs/reference/ALGORITHM_SURVEY.md): every algorithm's role, cost and
  weaknesses, plus a ranked catalogue of candidate improvements.
- [`docs/reference/COMPARISON.md`](docs/reference/COMPARISON.md): how this relates to CollateX and Juxta.
- [`docs/development/CASE_STUDY.md`](docs/development/CASE_STUDY.md): the engine on real editions (Shelley,
  Whitman, Verne, Pushkin).
- [`docs/development/DEVELOPMENT_LOG.md`](docs/development/DEVELOPMENT_LOG.md): the dated design history,
  including dead ends and negative results.
- [`docs/development/BACKLOG.md`](docs/development/BACKLOG.md): open items and proposed future work.
- [`docs/conformance/README.md`](docs/conformance/README.md): how a port in another language "passes".

## Status and known limits

The deterministic, rule-based core is mature and evaluated on complete novels, verse, and non-Latin scripts.
The main open fronts are summarised in [`docs/RESEARCH_INTRO.md`](docs/RESEARCH_INTRO.md) §4 and
[`docs/development/BACKLOG.md`](docs/development/BACKLOG.md):

- **No semantic layer yet.** Paraphrase versus literal substitution is deliberately out of scope for the core;
  this is the lexical and structural collator.
- **Short near-diagonal moves are irreducible by geometry.** A short passage close to its original position
  cannot reliably be told apart from a coincidence, so such moves are reported as `likely`, not `certain`.
- **Nesting.** A move nested inside another move is recovered at a single level only.
- **Tokenisation.** Scripts without word spacing (CJK) are not yet segmented (B6).
- **TEI.** TEI XML import and export is not yet built (B12).
- The viewer's design has **not yet been evaluated with users**.

## Contributing

Contributions are welcome through pull requests. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) first: it
covers the workflow, the engine's invariants (purity, determinism, never hand-edit a golden), and the
documentation conventions. Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Citing

If you use CollationKit in research, please cite it using the metadata in [`CITATION.cff`](CITATION.cff)
(GitHub's "Cite this repository" button generates BibTeX and APA from it).

## Licence

- Source code: [MIT](LICENSE).
- Documentation (everything under `docs/` and `site/`, and the Markdown files at the root):
  [CC BY 4.0](LICENSE-docs.md).
- The texts in `corpus/verne/` and the literary excerpts in `docs/conformance/cases/` are in the **public domain**
  in the US (sourced from Project Gutenberg and the Internet Archive), with one exception: the copyrighted
  F. P. Walter translation of *Twenty Thousand Leagues*. It is not distributed here beyond an 87-word quotation
  in three test cases; `corpus/verne/scripts/build_corpus.sh` rebuilds it locally. See
  [`LICENSE-docs.md`](LICENSE-docs.md) and [`corpus/verne/README.md`](corpus/verne/README.md).
