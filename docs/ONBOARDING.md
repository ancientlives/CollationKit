# CollationKit — a guide for a new contributor or research student

**Who this is for:** a new contributor or research student — especially one interested in **machine learning /
AI** or **UI/UX design**.

It answers, in order: *what is this?* → *how do I run it?* → *how is it built?* → *how do I change it safely?* →
*where does my research fit?* You should be able to go from a cold clone to a running collation of a real novel
in about fifteen minutes, and to a first merged contribution in a week.

> **Read this first, then [`INDEX.md`](INDEX.md).** This document orients you; `INDEX.md` is the map of the
> other documents and tells you which to open for any given task. The root
> [`README.md`](../README.md) is the quick-start and the authoritative feature list.

---

## 1. What the project is

CollationKit is a **pure-Swift engine for scholarly textual collation**: given several versions (*witnesses*) of
the same work — a manuscript, a typescript, corrected proofs, a first edition, a later revised edition, or two
rival translations — it computes exactly how they differ and produces a scholar's *apparatus criticus*, a
located record of every variant.

It is deliberately **not a `diff`**. That distinction is the whole intellectual content of the project, so it is
worth being precise about:

| `diff` assumes | Literary prose actually does |
|---|---|
| the **line** is the unit of change | revision happens at word and phrase level; prose reflows, so line boundaries are meaningless |
| changes are **local and contiguous** | a paragraph can *move* — sometimes across a page boundary — and be revised *while* it moves |
| every difference is **equally interesting** | "colour"/"color" is noise; "cold wind" → "bitter wind" is the finding |
| output is a **patch** | scholarship needs a *citation*: page 12, line 4, words 3–5 |

So the engine aligns *tokens* with **Needleman–Wunsch** (which scores substitutions, so a reworded clause is one
substitution rather than a delete-block plus an insert-block), detects **transpositions** via unique-common
anchors, separates **substantives** from **accidentals** (Greg's distinction — real wording changes vs.
spelling/case/punctuation), and attaches a **page · line · word** citation to every variant.

### Where it sits

CollationKit was originally prototyped as the collation engine for a native macOS markdown editor. It is kept
standalone on purpose: no AppKit, no I/O in the engine, value-type in and value-type out, so the hard
algorithmic core can be developed and tested in isolation. This is also why it is a genuinely good research vehicle — the engine is a **pure
function** you can test, benchmark, port, and reason about without a GUI in the way.

There are two academic papers in progress out of it (the drafts are not in this repository; they are shared
separately with collaborators on request):
- an **engine paper** — the algorithms and their evaluation;
- a **data-visualisation paper** — on making a collation *legible and trustworthy*. **This one is where a
  UI/UX-minded student has the clearest runway.**

### Current state (verified 2026-09-06)

- **200+ tests, all passing** (`swift test`, a few seconds); `development/TESTING.md` lists what each suite covers.
- 29 conformance cases with byte-exact golden JSON outputs.
- Two N-witness merge strategies shipped; cross-language collation shipped; an 8-view interactive HTML viewer
  shipped; validated on four full Verne novels in independent English translations.

---

## 2. Getting it running

**Prerequisites:** macOS 13+ and a Swift 5.9+ toolchain (Xcode 15 or later, or a swift.org toolchain). Python 3
is needed only for the optional conformance schema validator. Nothing else — the package has **zero external
dependencies**, which is a deliberate portability commitment.

```sh
git clone https://github.com/ancientlives/CollationKit.git && cd CollationKit
swift build            # ~seconds, cached after the first run
swift test             # the full suite, a few seconds — do this before and after every change
swift run collate-demo # the built-in six-edition example, end to end
```

`collate-demo` is the fastest way to see what the engine *produces*: full texts, a located variant report, an
apparatus criticus, and a synoptic table.

### The one gotcha that will waste your afternoon

> **Debug builds are many times slower than release builds.** On a full novel a debug binary takes *minutes*
> and looks frozen. Always use release for real texts:

```sh
swift build -c release
.build/release/collate                                    # interactive menu
.build/release/collate run a.txt b.txt --out ./results     # scriptable
```

The measured numbers behind this are in [`development/BENCHMARKS.md`](development/BENCHMARKS.md).

### The `collate` harness

`collate` with **no arguments** opens an **interactive menu** with a directory browser — start here. It shows
each folder's subfolders and the witness files inside them (with sizes), lets you pick witnesses, base, order,
mode, and format, then browse to an output folder.

`collate run …` is the **scriptable** path with no menu, for CI and pipes:

```sh
collate run a.txt b.txt                          # first file = base (copy-text)
collate run --dir corpus/verne/earth-to-moon --all --out ./out   # everything in a directory, exported
collate run --diplomatic a.txt b.txt             # also report spelling + punctuation accidentals
collate run --format json a.txt b.txt | jq .     # the interchange format
collate run --strategy peer-msa a.txt b.txt c.txt        # base-agnostic merge
collate run --lexicon fr-en.lex fr.txt en.txt            # cross-language
collate --help                                   # the full flag list
```

Any run with `--out` always writes `collation.json` **and** the interactive `collation.html` viewer. Open that
HTML file in a browser — it is self-contained, offline, and is the thing you will spend the most time looking at
if you work on the UX side.

### Real texts to work on

The repository includes a corpus of genuine public-domain witnesses: four Jules Verne novels in independent
rival English translations (the Whitman, Shelley, and Pushkin material lives in the conformance cases under
`docs/conformance/cases/`):

```
corpus/verne/
  20000-leagues/ · earth-to-moon/ · journey-centre-earth/ · mysterious-island/
                 each an excerpt pair, plus full/ — the whole-novel pair
  known-issues/  reduced reproductions of specific defects
  scripts/       build_corpus.sh + clean_gutenberg.py — rebuild the witnesses from Project Gutenberg
  README.md · BIBLIOGRAPHY.md · bibliography.json
```

The raw Project Gutenberg downloads are not committed; `scripts/build_corpus.sh` fetches them into
`corpus/verne/raw/` when you rebuild.

**One witness needs a build step.** The F. P. Walter translation of *Twenty Thousand Leagues* is in copyright,
so it is not in the repository. Much of the project's history (the full-novel crash, the phantom-move
calibration) was measured on the Mercier/Walter pair, so run this once after cloning to reproduce that work:

```sh
bash corpus/verne/scripts/build_corpus.sh    # downloads from Project Gutenberg; rebuilds walter byte-identically
```

These are *hard* inputs — two independent translations of the same French novel share meaning but almost no
sentence-level wording — and they are what surfaced most of the interesting bugs in the project's history.

---

## 3. How the code is organised

```
CollationKit/
├── Package.swift              # SwiftPM manifest: 1 library, 1 CLI core, 3 executables, 1 test target
├── Sources/
│   ├── CollationKit/          # THE ENGINE — pure, no I/O, no UI (~230 KB of Swift)
│   ├── CollateCLI/            # the testable CLI core: options, discovery, export, HTML viewer
│   ├── collate/               # thin shell: argv + stdout/stderr + exit codes
│   ├── collate-demo/          # the worked example
│   └── collate-bench/         # the cost-sweep benchmark harness
├── Tests/CollationKitTests/   # the XCTest suites (see development/TESTING.md)
├── docs/                      # research intro, onboarding, spec, history, evaluation — see INDEX.md
├── corpus/verne/              # the Verne translation corpus (excerpts + full novels)
└── site/                      # the project website (GitHub Pages)
```

**The dependency rule is one-way and load-bearing:** `collate → CollateCLI → CollationKit`. The engine never
depends on the CLI, and never does I/O. If you find yourself wanting to read a file or print inside
`Sources/CollationKit/`, that is a design smell — the answer is a value type returned to the caller.

### The pipeline, stage by stage

The engine follows the **Gothenburg model** (the field-standard pipeline: tokenise → normalise → align →
analyse → visualise). Each stage is one file:

| Stage | File | What it does |
|---|---|---|
| **model** | `Token.swift` | `Witness`, `Token` — surface form, normalised form, kind, char range, and **page / line / word-position** coordinates |
| **1. tokenise** | `Tokenizer.swift` | word & punctuation segmentation; citation coordinates; page detection; `<!-- no_collate -->` exclusion regions; the `Normalizer` (the substantive-vs-accidental lever, incl. GB↔US spelling folding) |
| **1. citation** | `Pagination.swift` | `PaginationModel` — makes the page/line convention an *explicit input* (`.markers` / `.linesPerPage(N)` / `.explicit(offsets)` × `.perPage` / `.continuous`) |
| **2. align** | `Alignment.swift` | Needleman–Wunsch over comparable tokens, plus a **banded**, auto-widening NW as a bounded fallback |
| **2. moves** | `Transposition.swift` | the hard part (~50 KB): unique-common anchors, a page-aware maximum-weight increasing subsequence to pick the stable spine, recursive anchoring for edits *inside* a move, and **three false-move gates** |
| **3. classify** | `Variation.swift` | coalesces alignment ops into typed, located `Variation`s with readings and a `TextLocation` per side |
| **merge** | `TokenGraph.swift` | the base-anchored **lift**: merges N−1 pairwise results into one DAG |
| **merge** | `PeerMSA.swift` | the **peer merge**: each witness aligns against a growing consensus spine, not the base |
| **anchoring** | `TranslationLexicon.swift` | bilingual equivalence groups as one alignment key, so cross-language sets anchor |
| **facade** | `Collation.swift` | `collate(base:compared:)` and `variantGraph(witnesses:strategy:)` — the public API |
| **render** | `Apparatus.swift`, `Synopsis.swift`, `Report.swift`, `CollationNarrative.swift` | apparatus criticus; parallel-segmentation table; located report; a plain-prose account |
| **interchange** | `CollationJSON.swift` | the stable, `schemaVersion`-tagged JSON contract |

Read them in that order. `Tokenizer` → `Alignment` → `Variation` → `Collation` gets you the spine of the system
in about two hours. Save `Transposition.swift` for after you understand the rest — it is where all the subtlety
lives, and it will not make sense cold.

### The two merge strategies (worth understanding early)

When you have **N** witnesses rather than two, you must merge pairwise results into one structure:

- **`.baseAnchored`** (default) — align every witness against the *copy-text*, then lift the N−1 pairwise results
  onto one graph. Predictable cost; apparatus naturally keyed to the copy-text. This is right when there *is* a
  privileged base (an author's final edition).
- **`.peerMSA`** — each witness aligns against the *growing consensus spine*. Variance shared between non-base
  witnesses groups properly; moves are `certain` from structure. This is right when there is **no** privileged
  base — competing translations, base-free traditions, cross-language sets.

`CollationStrategy.contextualDefault(hasCopyText:)` picks between them. The trade-off is analysed honestly
against CollateX in [`reference/COMPARISON.md`](reference/COMPARISON.md).

---

## 4. How the project is developed (the working culture)

This project has an unusually disciplined process, and matching it is the fastest way to have your work accepted.

### The invariants — do not break these

1. **The engine is a pure function of (witnesses + declared configuration).** Same inputs → byte-identical
   output, today and in ten years. No hidden state, no ambient config, no I/O, no clock, no randomness (fuzz
   tests are *seeded*).
2. **Determinism is enforced, not aspirational.** [`reference/ALGORITHMS.md §9`](reference/ALGORITHMS.md) lists
   the determinism rules a port must follow (stable sort orders, tie-break rules). The conformance goldens are
   compared byte-for-byte.
3. **Never change a golden to make a test pass.** If your change alters `docs/conformance/golden/*.json`, you
   have changed the engine's observable behaviour. That is sometimes correct — but it is a deliberate decision
   with a documented rationale, never a way to get green.
4. **Nothing is learned or adaptive.** Tunables are fixed, documented constants. Section 6 below explains why,
   because if your interest is ML this is the constraint you most need to internalise.

### The workflow

```sh
swift test                     # baseline: confirm all green before you start
# … make your change …
swift test                     # confirm still green; investigate every diff
swift run collate-demo         # eyeball the human-readable output
.build/release/collate run --dir corpus/verne/journey-centre-earth/full \
    --all --out ./results      # then open ./results/collation.html
```

For any change touching alignment or move detection, the last step is **not optional**. Multiple defects in this
project's history were invisible in unit tests and obvious within thirty seconds of looking at the viewer on a
real novel.

The pull-request workflow is described in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

### Documentation is part of the deliverable

The maintenance convention (stated at the end of [`INDEX.md`](INDEX.md)):

- a new feature → a **dated entry** in [`development/DEVELOPMENT_LOG.md`](development/DEVELOPMENT_LOG.md), plus
  updates to the spec in **both** [`reference/ALGORITHMS.md`](reference/ALGORITHMS.md) (language-neutral) and
  [`reference/PAPER_NOTES.md`](reference/PAPER_NOTES.md) (Swift-grounded);
- a landed backlog item → a one-line tick in [`development/BACKLOG.md`](development/BACKLOG.md) pointing at the
  log entry;
- **a new test suite gets a row in `development/TESTING.md`.** The docs don't quote an exact test count, so
  adding tests needs no other doc change.

`DEVELOPMENT_LOG.md` is the single best thing to read to understand *how* the project thinks. It records dead
ends and rejected approaches, not just successes — including approaches that were analytically demolished before
being built. Read the 2026-07-08, 2026-07-15, 2026-07-16 and 2026-07-24 entries as a set: they are one
investigation, lasting about two and a half weeks, into a single class of bug, and they are a model of how to do empirical algorithm work.

### Landing a change safely — the established pattern

[`development/TOKEN_GRAPH_PLAN.md`](development/TOKEN_GRAPH_PLAN.md) documents the migration discipline that
carried three major features in without breaking anything: **build the new thing behind the existing types**, so
the old path stays byte-identical while the new one is proved against acceptance tests, then flip the default
only when the evidence is in. Follow it.

---

## 5. Where to start — a first week

1. **Run everything** in §2. Open a `collation.html` from a real novel and click every tab.
2. **Read** [`reference/ALGORITHMS.md`](reference/ALGORITHMS.md) end to end (it is language-neutral, so it reads
   as a spec rather than as Swift), then skim `PAPER_NOTES.md` for the rationale. For the analytical view — what
   each algorithm costs, where it is weak, and what could replace it — read
   [`reference/ALGORITHM_SURVEY.md`](reference/ALGORITHM_SURVEY.md); its Part II is a ranked list of candidate
   improvements, and its Part III maps them to interests.
3. **Read the four false-move log entries** described above. This is the project's most instructive story.
4. **Pick a small backlog item.** [`development/BACKLOG.md`](development/BACKLOG.md) is written so that each
   item can be used directly as a task brief. Good first items:
   - **Fenwick-tree weighted LIS** (`ALGORITHM_SURVEY.md` Part II, item 1) — replace the spine's `O(k²)` DP
     with the `O(k log k)` form. Textbook algorithm, one function, and every existing test must still pass byte-identically,
     so it teaches you the project's determinism discipline in a single change.
   - **B19 — adversarial cost benchmark point.** Small, self-contained, touches `collate-bench` only, and closes
     a real gap the benchmark notes call out. An excellent way to learn the codebase without risk.
   - **B15 — witness-profile artifact.** Compute each witness's word-frequency and unique-n-gram profile once,
     reuse it across pairings (a performance win), and **export it as an inspectable audit artifact**. Low risk,
     the data already exists, and it unlocks B16. *Note the scope constraint:* this is an audit and performance
     feature, explicitly **not** a stop-word blocklist — see the item's scope note for why filtering common
     tokens would actively harm move detection.
5. **Write a conformance case.** Add a `cases/NN-name/` directory (witness `.txt` files plus a `meta.json`),
   generate its golden, and make `ConformanceTests` pass. This teaches you the whole contract in one exercise.

---

## 6. Your research interests — an honest map

This is the section to read twice, because the fit is real but it is **not** where a newcomer's instinct points.

### 6.1 Machine learning and AI — read the constraint first

The project has an explicit, carefully argued position on ML, in
[`reference/PAPER_NOTES.md` Appendix A](reference/PAPER_NOTES.md) ("Why not more memory, and why not learning
across documents?"). You must read it before proposing anything in this space. Its argument, compressed:

- **Determinism is disqualifying-if-lost.** An editor must be able to state that the apparatus is exactly
  reproducible by anyone from the witnesses alone, in ten years. "The result depends on the model's training
  history" cannot appear in a critical apparatus.
- **Auditability.** Every variant must be defensible line by line, traceable to an explicit rule. A cross-corpus
  learned bias is by construction not locally explainable.
- **The target is the individual work, not a population.** Each witness set is *sui generis*. A prior learned
  from a 19th-century novel is not safe for a medieval charter. Overfitting is not a bug to tune away here — it
  is the failure mode.
- **The data conditions for learning are absent** — witness sets are few, short, and deliberately heterogeneous.
- Empirically, **the bugs that actually occurred were decision errors, not capacity errors**, and each was cured
  by a better rule in a handful of lines with zero extra state.

This is not hostility to ML; it is a scoping claim about where a learned component can sit without destroying
the properties that make computational collation admissible as scholarship. Understanding *that* distinction is
itself a strong research contribution — and there is genuine, well-defined ML work that respects it:

**(a) The semantic / paraphrase layer — the flagship opportunity.**
This is **specced but unbuilt** (proposed; see `ALGORITHM_SURVEY.md` Part II, item 10), and it is
explicitly *gated* rather than rejected. The engine today is a *substantive* collator: it tells you `cold wind`
became `bitter wind`, but it cannot tell you whether a substitution is a **paraphrase** (same meaning, reworded)
or a genuine change of sense. That is a sentence-embedding / lexical-semantics problem sitting on a clean seam:
the engine hands you typed, located, aligned substitution spans, and a semantic layer would *classify* them.

The design constraints make it a genuinely interesting research problem rather than a fine-tuning exercise:
- it must be an **additive layer** that never alters alignment, so the substantive apparatus stays byte-identical
  (this is exactly how the `TranslationLexicon` was landed — copy that pattern);
- it must be **deterministic and versioned** — a pinned model, a recorded version, reproducible output;
- it must be **inspectable** — a similarity score a scholar can see and overrule, not a hidden reclassification;
- it should probably be **opt-in and clearly labelled** in the output, so the apparatus distinguishes "the
  engine measured this" from "a model judged this".
Evaluation is the hard part and the paper-worthy part: what is ground truth for "paraphrase" in a critical
edition, and how do you validate against scholarly judgement?

**(b) B17 — sentence-aligned parallel-text anchors.** The `TranslationLexicon` anchors cross-language collation
on word pairs; its documented residual is noun–adjective inversion across the boundary (`phénomène inexpliqué`
vs `mysterious phenomenon`). Sentence-level alignment first, then within-sentence, is the richer approach — and
this is a well-studied area in MT and parallel-corpus research where modern multilingual sentence embeddings are
a natural fit. The Verne corpus (French originals plus rival English translations) is *already sitting there* as
your evaluation data. Same discipline applies: anchoring only, alignment-only, never touching the reported
readings.

**(c) B16 — corpus-wide commonness signals for move confidence.** Thread a corpus-scale commonness value into
the `certain`/`likely` confidence scoring, so the engine can distinguish "rare in this novel but a stock phrase
for this author" from "genuinely singular". Note the sharp constraint recorded in the backlog: this **sharpens
confidence**, it is **not** a coincidence-catcher. The 2026-07-16 analysis established that neither word- nor
phrase-rarity separates a coincidental match from a real move — the phantoms were the *rarest* phrases; only the
**geometric** signal (block length × off-diagonal distance) does. That finding is a good lesson in letting the
data kill an appealing hypothesis, and B16 is what survives it.

**(d) The honest meta-question, which may be the best paper of all.** The project's residual false-move class is
*provably irreducible on geometry alone*: a short block sitting almost on the diagonal is indistinguishable from
a genuine short local hop, and the corpus contains a legitimate one-token move, so no length floor is admissible.
The current answer is to report it as `likely` rather than suppress it. **Is there a learned signal that
separates these cases where geometry cannot — and can it be made deterministic, auditable, and inspectable
enough to be admissible?** That is a real open question with a clean baseline, a real corpus, an existing metric,
and a documented negative result to beat. If you want one project that engages the ML/scholarly-rigour tension
head-on, this is it.

### 6.2 UI/UX design — the most open ground in the project

This is, frankly, where a student can have the largest visible impact fastest, and there is already an academic
frame waiting for it.

A data-visualisation paper is in preparation; the views and their rationale are documented in
[`development/VIEWER_UX_PLAN.md`](development/VIEWER_UX_PLAN.md) and
[`reference/PAPER_NOTES.md`](reference/PAPER_NOTES.md) §8.1. **The research is not done** — and it has an
obvious gap you are qualified to fill.

The existing viewer (all in `Sources/CollateCLI/HTMLExport.swift` — self-contained, strict-CSP, no external
resources, no client-side recomputation) has:

| View | What it does |
|---|---|
| **Overview** | analytical dashboard: confidence verdict, change-intensity histogram, type breakdown, witness cards |
| **Text** | each witness with variants highlighted in situ, colour-coded by type |
| **Variant graph** | a horizontal agreement spine with readings branching below; SVG arcs for moves |
| **Apparatus** | the traditional `lemma ] reading SIGLA` list, interactive and cross-linked |
| **Parallel ⇄** | two columns, anchored linked-scroll, hover-to-reveal the counterpart |
| **Changes ✎** | the base rendered as **track-changes** into a witness — the most intuitive view for non-experts |
| **Alignment ✓** | a **dot-plot** correspondence map answering *did the tool align these correctly?* |
| **Story ✍** | a prose narrative of the whole collation with clickable inline examples |

The design constraints they honour — every mark encodes a real datum, deterministic (same input → byte-identical
page), self-contained and archivable, windowed so a full novel stays responsive, cross-linked because all views
project one substrate — are good constraints and you should keep them.

**The gap: none of this has been evaluated with users.** Every design decision in the viewer is currently
justified by the author's own judgement and by principle (Shneiderman's overview-first/details-on-demand, the
analytical-vs-executive dashboard distinction, the dot-plot borrowed from bioinformatics). There has been **no
user study, no task-based evaluation, no comparison against CollateX's or Juxta's outputs with real readers**.
For a data-visualisation paper, that is the missing piece, and it is exactly the
contribution a UI/UX-focused student is trained to make. Concretely:

- **A task-based evaluation.** Give scholars and non-specialists defined tasks ("find the largest revision",
  "is this alignment sound?", "what changed in chapter 3?") across the eight views, and measure. Which views
  actually get used? Does the Changes/redline view really help non-experts more than the apparatus, as claimed?
- **Evaluating the trust argument specifically.** The alignment map is intended to let a reviewer *confirm*
  an alignment rather than merely consume it. **Does it?** Can users actually distinguish honest divergence from mis-alignment using it? That is
  a testable claim and nobody has tested it.
- **Accessibility.** Colour currently encodes variation type throughout. Colour-blind-safe palettes, redundant
  encoding, keyboard navigation, and screen-reader semantics for a variant graph are unexplored and genuinely
  hard given the density.
- **Scale legibility.** The viewer windows for performance, but the *design* question — how do you present
  20,000 variants without either overwhelming or hiding? — is open.
- **B13 Step 2 — the merge-strategy affordance.** An open backlog item and a lovely, contained UX problem: how
  do you expose a *choice between two alignment algorithms* to a humanities scholar? The policy already recorded
  is a smart context-aware default with plain-language framing, explicitly **never a bare toggle**. Designing
  that — the wording, the disclosure, the defaults, the explanation of consequences — is real work.
- **A native viewer** (for example in SwiftUI) is future work, outside this backlog. If you want native UI
  work rather than web, that is the track.

### 6.3 Where the two interests meet

The most distinctive project available here sits at the intersection, and it is squarely a modern
human-centred-AI question: **how do you present algorithmic uncertainty to an expert who must be able to
overrule it?** The engine already emits `certain`/`likely` confidence on moves, and deliberately reports its
irreducible residual as `likely` rather than hiding it. The viewer currently renders this as a dashed arc.

That is a thin channel for a rich and consequential distinction. How *should* a tool communicate "I think this
passage moved, but on this evidence I could be wrong" to a scholar who will publish an edition based on the
answer? What does calibration mean when the user is an expert with better priors than the tool? If you then add
a semantic layer (§6.1a), the question compounds: how do you show a *model-judged* paraphrase differently from a
*rule-derived* substitution, so a reader always knows which they are looking at?

That question — uncertainty communication for expert users, grounded in a real system with a real corpus, a
documented negative result, and a stated auditability requirement — is a coherent research project
with both an ML and a UI/UX half, and it would strengthen both papers.

---

## 7. Reference — the document map

Full annotated map in [`INDEX.md`](INDEX.md). The short version:

| Document | Read it when |
|---|---|
| [`README.md`](../README.md) | quick-start, current feature list |
| [`development/TESTING.md`](development/TESTING.md) | running the tests; the test-suite table |
| [`reference/ALGORITHMS.md`](reference/ALGORITHMS.md) | you want the algorithms as a language-neutral spec, or are porting |
| [`reference/PAPER_NOTES.md`](reference/PAPER_NOTES.md) | you want complexity, parameters, rationale, limitations, **Appendix A** |
| [`reference/ALGORITHM_SURVEY.md`](reference/ALGORITHM_SURVEY.md) | **you are choosing what to build** — all 20 algorithms surveyed (role, cost, weaknesses) + a ranked catalogue of candidate improvements |
| [`development/DEVELOPMENT_LOG.md`](development/DEVELOPMENT_LOG.md) | you want the story and the reasoning — **start here for culture** |
| [`development/BACKLOG.md`](development/BACKLOG.md) | you want something to build; each item is a task brief |
| [`development/CASE_STUDY.md`](development/CASE_STUDY.md) | you want evidence on nine real editions across three authors and three scripts |
| [`development/BENCHMARKS.md`](development/BENCHMARKS.md) | you need measured cost, or are about to claim a performance win |
| [`development/VIEWER_UX_PLAN.md`](development/VIEWER_UX_PLAN.md) | you are working on the viewer — build history + constraints |
| [`development/CLI_PLAN.md`](development/CLI_PLAN.md) | you are working on `collate` |
| [`development/TOKEN_GRAPH_PLAN.md`](development/TOKEN_GRAPH_PLAN.md) | **the template for landing an engine change safely** |
| [`development/CORPUS_PLAN.md`](development/CORPUS_PLAN.md) | multi-work / whole-author collation (proposed, unbuilt) |
| [`reference/COMPARISON.md`](reference/COMPARISON.md) | "isn't this just CollateX?" — the honest answer |
| [`porting/RUST_STANDALONE_PLAN.md`](porting/RUST_STANDALONE_PLAN.md) | a standalone/WASM/web build |
| [`conformance/README.md`](conformance/README.md) | the portability contract and how a port passes |

### Vocabulary you will need on day one

| Term | Meaning |
|---|---|
| **witness** | one version of the work (manuscript, proof, edition, translation) |
| **siglum** (pl. *sigla*) | the short id for a witness (`MS`, `TS`, `GB1`) — here, the filename stem |
| **copy-text / base** | the privileged witness the apparatus is keyed to |
| **apparatus criticus** | the scholarly record of variants: `lemma ] reading sigla` |
| **lemma** | the base's reading at a point of variance |
| **substantive** | a real change of wording |
| **accidental** | spelling, case, punctuation — noise unless you are doing a diplomatic edition |
| **transposition** | a passage that *moved* |
| **collation** | the whole comparison, and its result |
| **variant graph** | the DAG merging all witnesses: agreement on the spine, disagreement branching off |
| **Gothenburg model** | the field-standard pipeline: tokenise → normalise → align → analyse → visualise |
| **parallel segmentation** | the synoptic table form: one row per position, one column per witness |
| **TEI** | Text Encoding Initiative — the XML standard for scholarly texts (backlog B12) |

---

## 8. A closing note on what makes this project unusual

Most student-facing codebases are either research code with no engineering discipline, or engineering code with
no research content. This one is both, and the discipline is the point: a pure deterministic core, a
byte-exact conformance corpus, build-enforced documentation, benchmarks with recorded numbers, honest
recording of limitations and rejected approaches, and an explicit argued position on where learning does and
does not belong.

That last item is the one worth carrying into your own research regardless of what you build here. The project
does not avoid ML because it is unfashionable; it avoids it *in specific places*, for stated reasons, having
tested the appealing alternatives and written down why they failed. Finding the places where a learned component
*can* live inside those constraints — and proving it with the same rigour — is the most valuable thing you could
contribute.
