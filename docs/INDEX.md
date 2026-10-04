# CollationKit documentation — index

The map of the project's documentation. Each entry says what the document is *for* and when to read it. The
top-level [`README.md`](../README.md) is the quick start, and [`CONTRIBUTING.md`](../CONTRIBUTING.md) is the
pull-request workflow.

```
README.md                     ← root: what it is, how to run, pipeline at a glance
CONTRIBUTING.md               ← root: how to propose a change; the engine's invariants; doc conventions
CHANGELOG.md                  ← root: what changed in each version
SECURITY.md                   ← root: how to report a vulnerability privately
docs/
  INDEX.md                    ← you are here
  RESEARCH_INTRO.md           ← PROSPECTIVE RESEARCH STUDENT, START HERE: what the project is and has
                                 achieved, core concepts, and where ML/AI and UI/UX research is heading
                                 (overview only, no build steps; ONBOARDING.md is the next document)
  ONBOARDING.md               ← NEW CONTRIBUTOR, START HERE: running it, the code map, the working culture,
                                 a first week, and where ML/AI and UI/UX research fits
  guides/
    INPUT_FORMAT.md           ← preparing witness files: ids, page breaks, no_collate regions, lexicons
  reference/                  ← the engine, precisely (for implementers and for methods sections)
    ALGORITHMS.md             ← LANGUAGE-NEUTRAL algorithm spec: port to any language
    PAPER_NOTES.md            ← Swift-grounded algorithm reference (complexity, parameters, bibliography)
    ALGORITHM_SURVEY.md       ← every algorithm surveyed (role, cost, weaknesses) + a ranked catalogue of
                                 candidate improvements and algorithms not yet used
    COMPARISON.md             ← vs CollateX / Juxta: shared legacy vs genuine departures
  development/                ← how it was built, how it is tested, and what's next
    DEVELOPMENT_LOG.md        ← dated concept → design → proof → test narrative, including dead ends
    BACKLOG.md                ← ranked open items and proposed future work
    TESTING.md                ← running the tests; what each suite covers
    CASE_STUDY.md             ← the engine on 9 real cases: Shelley, Whitman, Verne, Pushkin
    BENCHMARKS.md             ← measured cost: length × diversity × witness count
    CLI_PLAN.md               ← design of the `collate` command-line tool
    TOKEN_GRAPH_PLAN.md       ← design + migration plan for the token-graph merge
    VIEWER_UX_PLAN.md         ← the `collation.html` viewer: its eight views and their iterations
    CORPUS_PLAN.md            ← proposal: a separate `collate-corpus` wrapper for many works
    benchmarks/results.csv    ← the committed raw benchmark CSV
  porting/
    RUST_STANDALONE_PLAN.md   ← plan for a standalone, fastest-possible engine + WASM/web
  conformance/                ← the portability contract, executable
    README.md                 ← what the corpus is, the case format, how a port "passes"
    collation.schema.json     ← JSON Schema (draft 2020-12) for the `{ graph, pairs }` interchange
    validate.py               ← validate goldens against the schema (language-neutral)
    cases/ · golden/          ← input witness sets + their expected `--json` output
corpus/verne/                 ← public-domain Verne translation pairs (excerpts + full novels), build scripts,
                                 bibliography, and the engine issues this corpus surfaced
site/                         ← the project website (deployed to GitHub Pages)
```

## By document

### Start here
| doc | purpose | read when |
|-----|---------|-----------|
| [`RESEARCH_INTRO.md`](RESEARCH_INTRO.md) | **A research introduction**: the intellectual problem, what has been achieved, the core vocabulary, and the open questions in ML/AI and UI/UX. | You are a prospective research student or collaborator. Read it first. |
| [`ONBOARDING.md`](ONBOARDING.md) | **Guide for a new contributor or research student**: why this isn't `diff`, how to build and run it (including the debug-versus-release trap), the source map and pipeline stage by stage, the working culture and invariants, a suggested first week, the vocabulary, and where **ML/AI** (the gated semantic layer, B16/B17, the irreducible-residual question; read `PAPER_NOTES` Appendix A first) and **UI/UX** (the unevaluated viewer, the trust argument, B13 Step 2) research fits. | You are new to the project. Read after the research introduction. |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | **How to contribute**: branches and pull requests, local checks, the engine's invariants, golden-file discipline, test and documentation conventions. | Before your first pull request. |

### guides/
| doc | purpose | read when |
|-----|---------|-----------|
| [`guides/INPUT_FORMAT.md`](guides/INPUT_FORMAT.md) | **Preparing texts**: witness files and ids, what counts as a word, page-break markers (including the Markdown `---` caveat), `no_collate` regions, the translation-lexicon format. | Before you collate your own texts. |

### reference/
| doc | purpose | read when |
|-----|---------|-----------|
| [`reference/ALGORITHMS.md`](reference/ALGORITHMS.md) | **Language-neutral specification**: data structures, pseudocode, invariants, determinism rules, parameters, and a porting checklist. Decoupled from Swift. | You want to re-implement the engine in another language, or read the algorithms without Swift specifics. |
| [`reference/PAPER_NOTES.md`](reference/PAPER_NOTES.md) | **Swift-grounded algorithm reference**: the same algorithms as implemented, with complexity analysis, the parameter table, evaluation method, and the bibliography. | You want the authoritative account of what the engine is now, or are writing a methods section. |
| [`reference/ALGORITHM_SURVEY.md`](reference/ALGORITHM_SURVEY.md) | **Analytical survey of all 20 algorithms**: each one's role, cost, why it was chosen, and its honest weaknesses; then **Part II**, a ranked catalogue of candidate improvements and unused algorithms (Fenwick LIS, affine gaps, suffix-automaton anchors, guide-tree MSA, sentence alignment, TEI, the semantic layer, performance), each with effort, risk to the goldens, and the invariants it must respect. | You are choosing what to build next, or need the comparative rationale behind an algorithm choice. |
| [`reference/COMPARISON.md`](reference/COMPARISON.md) | **Prior-art positioning**: what is inherited from CollateX and Juxta (the Gothenburg model, the token-graph structure) versus the genuine departures (located, page-aware transposition; the citation model), and the N-witness merge architectures compared. | You need the honest "is this just CollateX?" answer, or are writing related work. |

### development/
| doc | purpose | read when |
|-----|---------|-----------|
| [`development/DEVELOPMENT_LOG.md`](development/DEVELOPMENT_LOG.md) | **Chronological narrative**: every stage, dated and tagged (`concept`/`design`/`proof`/`test`/`implementation`/`usage`/`abstraction`), including dead ends, negative results and limitations recorded as open and later resolved. | You want the story of how and why it evolved, or the rationale behind a specific decision. |
| [`development/BACKLOG.md`](development/BACKLOG.md) | **Ranked next steps**: open items (B6 CJK, B12 TEI I/O, B13/B9 UI polish), proposed future ideas (B15 witness-profile audit, B16 corpus-wide confidence, B17 sentence-aligned anchors, …), and a one-line done ledger. Each item is written as a self-contained task description. | You want to pick the next thing to build. |
| [`development/TESTING.md`](development/TESTING.md) | **The test suite**: how to run it, golden-file discipline, the test-count guard, and what each suite covers. | You are adding or changing tests. |
| [`development/CASE_STUDY.md`](development/CASE_STUDY.md) | **Real-edition case studies**: the engine on nine public-domain cases across three authors and three scripts (Shelley; Whitman, including a found poem-cluster transposition; Verne translation, French and trilingual; Pushkin in Cyrillic), reporting what it caught, what it missed, and the consequences. | You want evidence that the engine works on real text, or material for an evaluation section. |
| [`development/BENCHMARKS.md`](development/BENCHMARKS.md) | **Measured cost**: the `collate-bench` method and recorded numbers. Pairwise time is near-linear in length; graph time is roughly linear in witness count. | You want the engine's measured performance. |
| [`development/CLI_PLAN.md`](development/CLI_PLAN.md) | **Design of the `collate` tool (B9)**: a testable `CollateCLI` core with a thin shell, the interactive menu, scriptable flag mode, and export formats. | You are working on the command-line tool. |
| [`development/TOKEN_GRAPH_PLAN.md`](development/TOKEN_GRAPH_PLAN.md) | **Design + migration plan for the token-graph merge (B11)**: data model, merge algorithm, how it landed behind existing types without breaking the suite. The same discipline carried in the peer merge (B14) and the translation lexicon (B10). | You want the merge's design rationale, or a template for landing a large engine change safely. |
| [`development/VIEWER_UX_PLAN.md`](development/VIEWER_UX_PLAN.md) | **The interactive viewer**: its eight views (overview, text, variant graph, apparatus, parallel, changes, story, alignment map) and the iterations behind them. | You are working on the viewer or its UX. |
| [`development/CORPUS_PLAN.md`](development/CORPUS_PLAN.md) | **Proposal (not built): a `collate-corpus` wrapper** to collate and publish many works of an author as a static site. Argues the engine stays single-work and the corpus tool is built on top. | You want to collate a whole author's works. |

### porting/
| doc | purpose | read when |
|-----|---------|-----------|
| [`porting/RUST_STANDALONE_PLAN.md`](porting/RUST_STANDALONE_PLAN.md) | **Standalone-engine plan**: language choice (Rust), crate layout, performance opportunities, milestones, WASM/web path. | You are considering a standalone or web build. |

### conformance/
| doc | purpose | read when |
|-----|---------|-----------|
| [`conformance/README.md`](conformance/README.md) | **Executable portability contract**: language-neutral input witness sets (`cases/`), their expected `--json` output (`golden/`), and a JSON Schema for the interchange. A port passes when it reproduces every golden byte for byte and validates against the schema. | You are porting the engine, or need the reproducibility artefact. |

### corpus/verne/
| doc | purpose | read when |
|-----|---------|-----------|
| [`../corpus/verne/README.md`](../corpus/verne/README.md) | **The Verne evaluation corpus**: four novels, each as two competing public-domain English translations (a chapter excerpt and the full novel), how to rebuild it, and how to add a new work. | You want real, demanding test material, or to extend the corpus. |
| [`../corpus/verne/BIBLIOGRAPHY.md`](../corpus/verne/BIBLIOGRAPHY.md) | **Bibliography** of Verne's novels and their English translations, with a strict verified-or-flagged rule. | You are choosing new witnesses or citing the corpus. |

## How the documents relate

- **Implementing in any language:** `reference/ALGORITHMS.md` is self-contained; `reference/PAPER_NOTES.md`
  adds complexity and rationale; `conformance/` is how you *verify* a port; `porting/RUST_STANDALONE_PLAN.md`
  if the target is a standalone or fast build.
- **Understanding the design history:** `development/DEVELOPMENT_LOG.md`.
- **Research and writing:** `RESEARCH_INTRO.md` for the questions; `reference/PAPER_NOTES.md` for methods,
  `reference/COMPARISON.md` for related work, `development/CASE_STUDY.md` and `development/BENCHMARKS.md` for
  evaluation. The two papers in preparation are shared separately with collaborators.

## Maintenance convention (keep this true as the project grows)

- A **new feature** → a dated entry in `development/DEVELOPMENT_LOG.md`, and updates to the *spec* in
  `reference/ALGORITHMS.md` **and** `reference/PAPER_NOTES.md`.
- A **new doc** → file it under the right `docs/` subdirectory and add a row here and in the tree above.
- **Test counts are not quoted exactly** in the living docs, so adding a test needs no doc change; a new suite
  gets a row in `development/TESTING.md`. The log's dated `State:` lines record the count at that date.
- `reference/ALGORITHMS.md` is the **portability contract**: changing an algorithm's behaviour means updating
  its pseudocode and re-checking the determinism rules (§9) so existing ports stay in agreement.
