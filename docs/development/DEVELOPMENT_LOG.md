# CollationKit — Development Log

A running record of how the **collation engine** was conceived, designed, proven, and tested — kept so the
work can later be written up as an article / academic paper. It logs *only the collation-specific* parts:
the algorithms, data structures, parsing/normalization choices, and the reasoning behind them. It does **not**
record the host application or generic Swift-package/test scaffolding.

Each entry is dated and tagged with a **stage**: `concept` · `design` · `proof` · `test` · `implementation`
· `usage` · `abstraction`. The intent is that the stages, read in order, narrate the development arc.

> **How to read this for the paper.** This file is the *chronological narrative* — the development arc,
> including dead ends, bugs found, and limitations that were recorded as open and *later resolved*. Where an
> early entry says something is "deferred" or "a known limitation," a **later** entry usually closes it; each
> entry's `State:` line and the running test count track progress. For the *synchronic* description of the
> finished engine — final algorithm with pseudocode, complexity, the full parameter table, and a
> bibliography — see the companion **[`PAPER_NOTES.md`](../reference/PAPER_NOTES.md)**, written to be lifted directly into
> a methods/algorithm section. The two are complementary: this log answers "how did it come to be and why,"
> `PAPER_NOTES` answers "what, precisely, is it now."
>
> **Resolved-vs-open at a glance (as of 2026-07-24):** cross-page attribution ✓ · move-with-internal-edit ✓ ·
> source-page citation model ✓ · lexical-diversity cost ✓ (banded fallback) · JSON interchange ✓ · conformance
> corpus + JSON Schema ✓ (B1/B2) · real-edition case studies ✓ (B4: 9 numbered cases, 3 authors, 3 scripts,
> pairwise + N-witness, incl. a *found* Calamus cluster move) · single-word move recovery + move confidence ✓
> (2026-06-30, fixes the delete+insert-instead-of-move defect) · diplomatic punctuation overlay ✓ (B6b) ·
> tokeniser hyphenation ✓ (B6 part 1) · pure-insertions in the graph ✓ (B6c, 2026-07-01, subsumed by B11) ·
> the anchor/token-graph merge ✓ (**B11, 2026-07-02**) · selectable merge strategy ✓ (B13 Step 1) · verse/prose
> scoring ✓ (B7) · peer-MSA merge ✓ (B14, 2026-07-06) · cross-language anchoring ✓ (**B10**, 2026-07-06 — the
> Verne-corpus enabler, on the token-graph substrate) · interactive HTML viewer ✓ (B8 + the viewer UX pass; eight views) ·
> `no_collate` editorial exclusion ✓ · the move-detection false-positive gates ✓ (displacement / rarity-locality /
> anchor-path distinctiveness, through 2026-07-16; the distinctiveness gate **recalibrated 2026-07-24** across four
> full-novel pairs, false moves 48 → 11). **Still open (engine/interoperability):** B6 CJK tokenisation
> (scriptio continua) · B12 TEI critical-apparatus I/O. **Still deferred:** the optional semantic/paraphrase layer;
> UI/CLI polish (B13 Step 2, B9 Stage B); and a native (non-HTML) viewer. See
> [`BACKLOG.md`](BACKLOG.md) for the full forward-looking list.

---

## Glossary (terms used throughout)

- **Witness** — one version of the work being collated (a draft, edition, manuscript). Borrowed from textual
  scholarship, where each surviving source of a text is a "witness" to it.
- **Substantive vs. accidental** — the editorial distinction (Greg, *The Rationale of Copy-Text*, 1950)
  between changes in *wording/meaning* (substantives) and changes in *spelling, punctuation, capitalization*
  (accidentals). A collator must be able to separate them.
- **Apparatus criticus** — the editorial record of variant readings, traditionally printed as footnotes
  keyed to a base ("copy-text"): a *lemma* (the base reading) followed by the variants and the witnesses
  (*sigla*) that carry them.
- **Transposition** — text that has *moved* to a different position between witnesses (as opposed to being
  deleted in one place and newly written in another).
- **Collation set / sigla** — the group of witnesses under comparison and their short identifiers (MS, TS,
  GB1, …).

---

## 2026-06-26 — `concept`: framing the problem

**Goal.** Reveal *how a literary text changed* across its versions (manuscript → typescript → proofs →
editions), in the way textual scholars need it — an *apparatus of variants* — and explicitly **not** as a
programmer's line `diff`.

**Why `diff` is the wrong tool (the founding observation).** Line-oriented diff (Myers, LCS-based) assumes:
(a) the unit of change is the line, (b) lines are stable, and (c) changes are local and contiguous. Prose
breaks all three: it reflows (so line boundaries are meaningless), it is revised at the word/phrase/sentence
level, and passages are *reordered* and *moved across pages*. A diff of two prose witnesses reports a storm
of line churn that obscures the actual editorial events. The scholarly need is the opposite: a small, typed
list of *variants* (insertion / deletion / substitution / transposition), each tied to its witnesses and its
location.

**Decision.** Build a *pure* engine (value-type in/out, deterministic, no UI, no I/O) so the algorithm can be
proven in isolation — a pure `enum` of static functions, value-type I/O, deterministic — which means the
engine is verifiable entirely by unit tests.

**Prior art surveyed (informally).** The **Gothenburg model** behind *CollateX* / *Juxta* — a five-step
pipeline: *tokenize → normalize → align → analyze → visualize*. We adopt this skeleton. Sequence alignment
itself comes from bioinformatics: **Needleman–Wunsch** (global alignment, 1970) and **Smith–Waterman** (local,
1981). For move detection we borrow the *anchor/patience* idea from *patience diff* (Bram Cohen) — unique
common elements as fixed points.

---

## 2026-06-26 — `design`: the pipeline & data structures

Adopted the Gothenburg skeleton, instantiated as a Swift pipeline where **each stage is independently
testable**:

```
Witness(text) → [Token] → comparable keys → AlignOp[] → SegmentAlignment → [Variation] → (apparatus | columns | graph)
                tokenize     normalize         NW         +transposition      classify         render
```

**Core data structures and the reasoning:**

- **`Token`** = `surface` (as written) + `normalized` (comparison key) + `kind` (word/punctuation) +
  `range` (char offsets back into the witness) + `paragraph` + **`page`**. Two design commitments live here:
  1. Keeping *both* `surface` and `normalized` is what lets normalization be aggressive (fold case,
     punctuation, GB/US spelling) for *alignment* while still showing the reader the true reading.
  2. Carrying `page` (and `paragraph`) on every token is what makes "across pages" a first-class, reportable
     fact rather than a byproduct of line math — directly answering the project's hardest requirement.

- **`Normalizer`** — a *configurable* fold, because the substantive/accidental line is an editorial choice,
  not a fixed rule. Two presets: `.diplomatic` (record everything) and `.substantive` (fold accidentals).
  Includes a GB↔US spelling table so two national editions don't read as wall-to-wall substitutions. This is
  the single most important lever distinguishing collation from diff: *what counts as the same reading?*

- **`AlignOp`** = `match | substitute | delete | insert` over token *indices*. Chosen so a substitution is a
  first-class outcome (not a delete+insert pair) — see the alignment decision below.

**Decision: Needleman–Wunsch over LCS/diff.** LCS (the basis of `diff`) only finds the longest common
*subsequence*; everything else is "added" or "removed", so a one-word change becomes delete+insert. NW
performs *global* alignment with a scoring scheme (match reward, mismatch/gap penalties) and so naturally
expresses a changed word as a **substitution** and a reworded clause as a *run* of substitutions — which is
exactly the apparatus unit a scholar wants. Cost is `O(n·m)` time/space; acceptable for documents, and
chunked by anchors (below) in practice.

---

## 2026-06-26 — `proof` + `implementation`: alignment & the transposition problem

Implemented NW (`Alignment.needlemanWunsch`) with deterministic traceback (diagonal > up > left) so output is
stable for tests. Verified on hand-built cases: identical → all match; pure insert/delete; a mid-sequence
substitution stays a substitution; an inserted word is a single gap.

**The hard part — transposition (the genuine departure from diff).** NW alone, being a *monotonic* alignment,
cannot represent a moved block: if a sentence moves from page 2 to page 1, NW reports it as a deletion (where
it was) and an insertion (where it went). That is precisely the diff artifact we set out to avoid.

**Approach (`Transposition.align`):**
1. **Anchors.** Find n-grams (default n=3) that occur **exactly once in each** witness — unique, unambiguous
   shared landmarks (the patience-diff idea). Repeated n-grams are excluded as ambiguous.
2. **Stable spine via LIS.** Sort anchors by their position in witness A; the **longest strictly-increasing
   subsequence by their position in B** is the set of anchors that keep the same relative order in both
   witnesses — the "stable spine". Anchors *off* the spine correspond to material that **moved**.
3. **Regions vs. moves.** Between consecutive spine anchors, align the gap with NW (ordinary edits). Off-spine
   anchors become `transposition` segments.

**Bug found in proof, and the fix (logged because it is the crux of the method).** The first implementation
double-counted moves: a transposed sentence was reported *both* as a transposition *and* as a delete (old
spot) + insert (new spot) in the surrounding regions — the very churn the layer exists to remove. Root cause:
the moved tokens still fell inside adjacent gap regions and were re-aligned. **Fix:** *mask out* every
transposed token span (in both witnesses) before region alignment, aligning regions over only the unconsumed
tokens (with an index map back to real positions). Then **coalesce** adjacent moved anchors into one block and
**grow** each block to absorb identical neighbouring tokens no anchor covered (e.g. a repeated final word like
"…one by one"). Result: a moved sentence is reported as exactly **one** transposition with a clean `crossesPage`
flag — no churn. This masking+coalescing step is the prototype's main original contribution over a textbook
anchor-diff.

---

## 2026-06-26 — `implementation`: classification & N-witness graph

- **`VariationClassifier`** coalesces the op stream into typed `Variation`s: runs of matches are skipped;
  adjacent delete+insert merge into a **substitution**; like-with-like into **insertion**/**deletion**;
  transposition segments pass through. Each `Variation` carries both readings, the token ranges in each
  witness, the pages, and a derived `crossesPage`. Coalescing is why a reworded five-word clause is *one*
  apparatus entry, not five.
- **N-witness `variantGraph`** — a first cut at the multi-witness apparatus via **progressive, base-anchored
  alignment**: every other witness is aligned to witness 0 and its readings folded onto the base positions.
  Each base position becomes a `GraphNode` mapping *reading → set of witnesses*; nodes with >1 reading are
  the points of variance (the apparatus). Untouched positions record agreement. (A full token-graph merge —
  true CollateX-style — is noted as later work.)

**Validated against the target scenario.** Built `LiteraryEditionsTests` over six witnesses
(manuscript, typescript, proofs, GB 1st, US 1st, Uniform edition), asserting: MS→TS single substitution;
proofs move a sentence **across a page** → one cross-page transposition, *zero* delete/insert churn; GB vs US
fold to no substantive variants (and *do* surface when folding is off); Uniform's `cold→bitter` substitution;
and a deterministic six-witness variant graph with agreement + variant nodes.

**State at end of day:** 27 tests green; pipeline complete from text to typed variants + N-witness graph.

---

## 2026-06-27 — `implementation`: accidentals as a first-class, optional variant

Added `variantSpelling` to the variant taxonomy and a `recordAccidentals` switch. The mechanism is subtle and
worth recording: accidentals are, by construction, *folded away during alignment* (colour and color share a
normalized key, so they `match`). To report them we therefore inspect the **matched** positions — where the
normalized keys are equal but the *surfaces* differ — rather than the substitution/insert/delete stream.

This cleanly realizes the Greg substantive/accidental distinction as two switchable layers over **one**
alignment: the default apparatus shows only substantives; `recordAccidentals: true` additionally surfaces
spelling/capitalization/punctuation variants (the diplomatic view). No re-alignment, no second pass — the
information was already in the matched pairs, just not previously read. Tested: GB/US `colour↔color`,
`harbour↔harbor`, and `End↔end` appear only when requested, and never inflate the substantive count.

## 2026-06-27 — `abstraction` + `usage`: separating the apparatus/synopsis MODEL from any rendering

Designed the output layer as **pure models** decoupled from any one display format — the abstraction that lets
a single collation drive footnotes, a side panel, an exported HTML page, or a CLI dump without re-computation:

- **`ApparatusEntry` / `Apparatus`** — the *apparatus criticus*: a `position`, a `lemma` (base/copy-text
  reading), and `variants` (reading → sigla). Built from either a pairwise `CollationResult` or the N-witness
  `VariantGraph`; the graph builder picks the base witness's reading as the lemma and groups the remaining
  readings by the witnesses (*sigla*) that share them. `plainText` renders the classic
  `"<pos> <lemma>] <reading> <sigla>; …"` line. Omission is the null sign `∅`.
- **`SynopticRow` / `SynopticTable` / `Synopsis`** — parallel-segmentation columns: each base position is a
  row, each witness a column, with `∅` where a witness omits the word and an `isVariant` flag where they
  disagree. `plainText` renders a fixed-width table; a UI can map the same model to a grid.

Both consume the existing `VariantGraph`, so the engine is unchanged. This is the point at which "how it
renders" becomes testable *before* any UI exists: assertions on the apparatus line format, the `∅` omission
sign, and the N-witness grouping (`dawn` shared by `[TS, US1]`) define the rendering contract any view
must honour.

## 2026-06-27 — `test` + `proof`: scale, and a finding about lexical diversity

Added scale tests (2k–4k words across 10–20 pages). They surfaced a genuine, paper-worthy property of the
method:

> **The anchor optimization's benefit is a function of the witness's lexical diversity.** The anchor pass
> chunks the `O(n·m)` Needleman–Wunsch matrix into small inter-anchor regions *only when unique n-grams
> exist*. A first scale test used a 20-word lexicon (so almost no n-gram was unique); with no anchors the
> whole 4000-word document fell back to a single 4000×4000 (~16M-cell) matrix and took ~4s — even
> collating the text against *itself*.

This is not a bug so much as a characterization: the algorithm's practical cost depends on the *information*
in the text, not just its length. Natural prose has high local uniqueness (distinctive content words), so the
chunking is effective and a lightly-edited 4000-word collation drops from ~4s to ~0.03s. The test generator
was corrected to produce distinctive prose (the honest representation of the target use case), and the
finding logged here as a known property: pathologically low-diversity input (or heavily repetitive verse with
refrains) degrades toward full-matrix cost.

**Implications recorded for later work / the write-up:**
- A robustness option is to make the anchor pass **recursive** (re-anchor within a still-large gap region) or
  to **adapt** the n-gram length downward when too few anchors are found — both keep worst-case input
  tractable. Deferred; noted as future work.
- The substantive/accidental fold also *increases* effective key collisions (more tokens share a normalized
  key), a second-order effect on anchor density worth measuring in the paper.

**State:** 37 tests green; full suite runs in <0.1s. Pipeline now spans *concept → text → typed variants →
N-witness graph → apparatus & synoptic rendering*, with scale + determinism guards.

## 2026-06-27 — `proof` (via a CLI demo): three bugs and an insight the worked example exposed

Built a tiny `collate-demo` executable that prints the pairwise variants, the N-witness apparatus, and the
synoptic columns for the six-edition scenario — a way to *see* the rendering before any UI exists. Running it
on real (not unit-sized) input immediately surfaced issues the targeted unit tests had not:

1. **Bug — transposition polluted the variant graph.** The N-witness graph projected a *transposition's*
   whole comparedReading onto every base position it covered, as if it were a substitution — producing
   garbage apparatus rows (one long string repeated down a dozen positions). **Fix:** a transposition is
   *agreement* at the base (the witness carries the same text; it merely sits elsewhere), so transposed
   positions are no longer marked "changed" — only deletions/substitutions change a base reading, and a
   multi-word substitution is now projected **per token** (word-by-word) instead of repeating the whole
   phrase in each cell.
2. **Bug — page-break markers leaked into the text.** `<!-- page break -->` tokenized into stray `page`/
   `break` "words" that then appeared as readings. **Fix:** the tokenizer now *skips the marker span
   entirely* (still bumping the page counter), so structural markup never becomes collatable content.
3. **Insight — repaginating is not a textual variant.** A test that "moved a sentence across the break" by
   relocating only the *break* produced zero variants — correctly: the words are in the same order, only the
   pagination changed. A cross-page *textual* move requires a sentence to change order **relative to another
   sentence**. Recorded because it sharpens what "change across pages" means: collation is over token order;
   pagination is metadata carried alongside, not the unit of comparison.

## 2026-06-27 — `test`: a documented limitation in cross-page *attribution*

A two-sentence swap is symmetric: A-before-B becomes B-before-A. The engine correctly detects **one**
transposition (no insert/delete churn), but it reports *one* of the two sentences as "the moved block" —
chosen by the anchor/LIS spine, **not** by which side crossed a page. Consequently `crossesPage` reflects
whichever block the spine picked and is **not guaranteed** to flag the editorially-moved sentence. Page and
token-range fields are always populated (so navigation works), but precise cross-page *attribution* is a
**known limitation**, captured by a test that asserts the reliable invariants (single detection, identical
readings, populated navigable fields) and documents the gap.

A second observed limitation: a block that **both moves and is edited inside** (e.g. "They were *tired*" →
moved *and* "*weary*") isn't recognized as a single move — the internal substitution breaks the anchor run,
so the changed words fall back to delete+insert around a smaller transposed core. Both limitations point at
the same future-work fix: a **recursive / page-aware anchor pass** (re-anchor within gaps; let pages break
ties when choosing the moved block). Logged for the write-up as the boundary of the current method.

**State:** 38 tests green; `swift run collate-demo` renders apparatus + synopsis for the six editions. The
prototype now demonstrably spans concept → engine → N-witness graph → apparatus/synopsis rendering, with the
method's boundaries (lexical-diversity cost, cross-page attribution, move-with-internal-edit) explicitly
characterized rather than hidden.

## 2026-06-27 — `implementation`: page-aware tie-break (resolving the cross-page attribution gap)

Closed the limitation logged earlier the same day: a symmetric two-block swap was *detected* as one
transposition, but the engine reported an arbitrary one of the two blocks as "moved", so `crossesPage` was
not reliably attributed to the block that actually changed page.

**Root cause.** Move detection chose the stable "spine" via a plain **longest-increasing-subsequence (LIS)**
over the anchors' B-positions — a *cardinality* criterion. When two blocks swap and are similar in size, the
LIS keeps one and marks the other as moved, with no principled reason to prefer either; the page that each
block sits on never entered the decision.

**Fix — a weighted spine with a page bonus.** Replaced LIS with a **maximum-WEIGHT increasing subsequence**
(O(n²) DP), weighting each anchor `1`, plus a `+1` bonus when the anchor is *page-stable* (same page in both
witnesses). A tie in length is therefore decided in favour of keeping page-stable anchors on the spine — so
the block left **off** the spine (the reported transposition) is the one that crossed a page. Page data is
threaded purely as metadata (`aPages`/`bPages` parallel to the comparable tokens); the alignment over keys is
unchanged, preserving the separation between *what aligns* (token identity) and *how ties resolve*
(page-awareness). Verified: the proofs case now reports the **"lamps were lit…"** sentence as the move, flagged
`crossesPage` p.1→p.0 — the editorially-correct block.

**Why this matters for the paper.** It is a clean illustration of injecting *domain* knowledge (pagination is
editorially salient) into a generic sequence-alignment step without contaminating the alignment model — a
weighting on the order-preservation objective, not a special case in the matcher. It also leaves a principled
knob: the page bonus could be generalized to any "stability prior" (chapter, section, sentence) the editor
cares about.

(Residual, still logged as future work: a block that **both moves and is edited inside** isn't unified — the
internal substitution breaks the anchor run. The recursive-anchor pass remains the planned fix.)

## 2026-06-27 — `implementation` + `usage`: locating a variant for the reader (page / line / word / char)

Added the **locating layer** that answers "where in the text is this change?" in every coordinate a reader or
UI might use:

- The tokenizer now records, per token, `line` and `wordIndex` alongside the existing `page`, `paragraph`,
  and character `range`. Newlines inside skipped page-break markers are counted so line numbers stay aligned
  with the source.
- Each `Variation` carries a `TextLocation` for each side (`baseLocation`/`comparedLocation`): `page`, `line`,
  `wordIndex`, and a `charRange` spanning the whole reading. `TextLocation.human` renders a 1-based citation
  ("p.2 · line 6 · word 18").
- Two complementary purposes, deliberately distinguished: the **apparatus** is keyed to a *lemma* (the
  critical-edition convention); the new **located report** (`Report`) is keyed to a *location* — what a reader
  scanning a document wants, and what a viewer uses to scroll/highlight (via `charRange`) and to
  show "jump to" by word/line/page.

This is the textual-scholarship counterpart to a code editor's "go to line": it makes a detected variant
*addressable*. For the write-up, it is worth noting the design choice that **location is a property of the
variant, derived from its tokens**, not a separate lookup — so any renderer (footnote, side panel, exported
HTML, CLI) gets navigation for free from one model.

## 2026-06-27 — `usage` + `abstraction`: full-text display and arbitrary-text harness

To validate the engine *from an abstracted perspective* (not only the static fixtures), the work now offers:

- **Shared fixtures** (`Samples.sixEditions`) lifted into the library so the demo and the tests collate the
  same canonical example (manuscript → typescript → proofs → GB/US first editions → Uniform).
- An enriched **`collate-demo`** that prints (1) the **full witness texts**, (2) the **located variant
  report** for each successive pair, (3) the N-witness **apparatus**, and (4) the **synoptic columns** — a
  complete picture of what a viewer would render.
- **Arbitrary-text collation**: `swift run collate-demo a.txt b.txt …` collates the user's own files (first =
  base), with `--accidentals` to include spelling/case. This is the abstraction test:
  the engine is exercised on inputs it has never seen, and behaves the same (e.g. it found a moved sentence
  and a "mat → warm mat" expansion in an ad-hoc pair, each with a page/line/word location).

The point for the paper: the engine's public surface is a *pure function of two (or N) `Witness` values* —
no fixtures, no app, no I/O baked in — so the same code path serves the unit tests, the CLI, and any
UI. The fixtures are *data*, not behaviour.

**State:** 45 tests green; demo renders full texts + located report + apparatus + synopsis; custom files
supported. Cross-page attribution is now correct for clean swaps; the two residual limitations
(move-with-internal-edit; lexical-diversity cost) remain logged with their planned fixes.

## 2026-06-27 — `design` + `implementation`: a *scholarly* citation model for locations

A review of the demo output exposed that the first locating layer used the wrong coordinate semantics — a
useful lesson for the paper about the gap between *implementation-convenient* offsets and *scholarly*
reference.

**The problem.** The initial `TextLocation` reported (a) a **line number that counted every physical
newline** — including blank lines and the page-break marker line — and (b) a **word number that was global
to the whole witness** (the Nth word of the document). Neither matches how a printed witness is cited: a
critical edition numbers only *text lines*, *per page*, and references a word by its place *on the line*, not
by a document-wide running count. The global word count was also unstable — the same word had a different
number in two witnesses purely because earlier content differed.

**The corrected model.**
- **Line = text line within the page.** Line numbering resets at each page break and advances only on lines
  that actually carry text; blank lines and the skipped page-break marker are never numbered. Implemented by
  deferring the line increment until the first token of a line is emitted (a `lineHasText` latch), so a
  trailing blank never consumes a number.
- **Word = position on its line**, not in the document. Resets per line. Stable under edits elsewhere.
- **Span, not point.** A `TextLocation` now records `firstWord…lastWord` (and `line…endLine`), so a
  **single-word** variant cites a *word position* ("p.1 · line 2 · word 3") and a **multi-word** variant a
  *word range* ("… · words 3–4"); a reading crossing a line cites a *line range* ("… · lines 1–2 · words
  4…2"). The exact `charRange` is retained for pixel-accurate highlighting.

**Why it matters for the write-up.** This is the principle that *locating a variant is a domain problem, not
a string-offset problem*: the unit of reference (page, text-line, word-on-line) is dictated by how scholars
read and cite witnesses, and choosing it correctly is what makes the apparatus usable. Result on the worked
example: the moved sentence now reads "TS p.2 · line 1 · words 1–10  →  PR p.1 · line 2 · words 1–10" — a
citation an editor could put in a footnote — instead of the earlier opaque, blank-line-inflated, document-
global numbers.

**Open limitation — the source-page model (logged 2026-06-27).** Line numbering currently resets per page
**only at explicit page-break markers** in the source (`<!-- page break -->`, a stand-alone `---`, or a form
feed). The consequence: a witness with **no markers is treated as a single page**, so its text lines number
continuously from 1 to the end. This is correct and useful for plain markdown/source (where "page" means a
deliberate break the author inserted), and it is the only page model the prototype can know from the text
alone — but it is **not** the *printed-page* model a scholar citing a physical edition expects, where a page
holds a fixed number of typeset lines (e.g. ~40) determined by the book's layout, not by markers in the copy.

So today the citation answers "where in the *source witness*", which can diverge from "where on the *printed
page*". Recorded now, before the next engine task (recursive anchoring), so it is not lost.

Possible fixes, in rough order of fidelity (deferred — noted for the design discussion / the paper):
1. **Lines-per-page setting** — a witness-level `linesPerPage` that synthesizes page boundaries every N text
   lines when no markers are present. Cheap; approximates a uniform printed page.
2. **Explicit pagination map** — let a witness carry a list of source offsets where printed pages begin
   (imported from the edition's actual page breaks), so citations match the physical book exactly. Most
   faithful; needs that data to exist.
3. **Line-numbering policy as a parameter** — make "reset per page" vs. "continuous through the witness" (the
   classic *through-numbered* edition, e.g. line 1–1247 of a poem) a choice, since both conventions are used
   in scholarship. The data model already supports continuous numbering (it is what an unmarked witness
   produces today); this would make it an explicit, intended mode rather than a side effect.

For the write-up this is the same lesson as the citation model itself, one level up: *what a "page" and a
"line" mean is an editorial convention the tool must be told, not infer* — the marker-driven reset is a
sensible default for born-digital source, but faithful citation of a printed witness needs its pagination
supplied.

**State:** 47 tests green; demo citations are page-relative, text-line-only, and word-span aware. The
source-page vs. printed-page distinction is now an explicitly recorded open item.

## 2026-06-27 — `implementation`: recursive anchoring (a move that is also edited inside)

Closed the longest-standing engine limitation: a passage that **both moves and is revised inside** — e.g.
"they were *tired* and the road had been long" transposed *and* "tired" → "weary". Previously the internal
word change broke the anchor n-gram run, so only the unchanged *tail* was recognized as the move and the
changed *head* leaked out as a spurious deletion ("they were tired") + insertion ("they were weary") — the
exact churn the transposition layer exists to remove.

**Why anchors alone failed.** Anchors are unique shared n-grams. An edit inside a passage destroys every
n-gram spanning the edited word, so the passage fragments into anchor islands separated by the edit. The
earlier block-builder only **coalesced adjacent islands** and **grew across *identical* neighbours** — it
could not cross the edited word, so the head island (which had no surviving anchor at all) was never joined
to the block.

**The fix — two cooperating mechanisms:**
1. **Bounded-gap bridging (block growth across a small mismatch).** When growing a moved block hits a
   mismatch, look up to `bridgeGap` (=4) tokens further out for an identical *resync* pair on both sides
   (`resync` / `resyncForward`); if found, absorb the mismatched run into the block. This is what pulls the
   edited head into the move. Bridging refuses to cross the stable spine and prefers *near, balanced*
   resyncs (penalty = stepsA + stepsB + |stepsA − stepsB|), so it bridges an *edit* rather than swallowing
   unrelated neighbouring text — guarded by `testUnrelatedTextIsNotSwallowedByBridging`.
2. **Recursive alignment of the move (`innerAlignment`).** Once the block spans the whole moved passage, it
   is collated *against itself* across the two witnesses (a Needleman–Wunsch over the two sub-spans, since a
   moved block is internally order-preserving). The resulting `innerOps` are carried on the
   `.transposition` segment and classified like any region, but tagged `withinTransposition` — so the edit
   surfaces as a substitution *inside the move*, located, rather than as churn outside it.

**Result on the worked case.** One transposition spanning the whole sentence + one `withinTransposition`
substitution ("tired"→"weary") with its own page·line·word location; zero insert/delete churn. The located
report prints it as "SUBSTITUTION (within a moved passage)".

**Design notes for the paper.**
- This is "recursive" in the precise sense that *collation is re-applied to a sub-problem it has already
  isolated* (the moved block), turning an intractable global ambiguity (is this delete+insert, or a moved
  edit?) into a clean local one. It mirrors how the top level already recurses NW between spine anchors —
  the move is just another region that earns its own alignment.
- The `bridgeGap` bound is the method's tunable: too small misses larger internal revisions; too large risks
  conflating a move with adjacent independent edits. 4 tokens handled the literary cases; the right value is
  an empirical question worth a sentence and a small experiment in the write-up.
- The mechanism composes with the page-aware spine and the location model already in place: an internal edit
  inside a cross-page move is both `crossesPage` (on the move) and `withinTransposition` (on the edit), each
  carrying its own citation.

**Residual / future work.** Bridging is bounded and single-level (the inner alignment is plain NW, not itself
transposition-aware), so a *nested* move (a passage that moved, inside another passage that also moved) is not
recovered — vanishingly rare in practice, recorded for completeness. The `bridgeGap` value is fixed, not
adaptive.

**State:** 53 tests green (6 new for recursive anchoring). Move-with-internal-edit is resolved; the
remaining open items are the source-page vs printed-page citation model and the lexical-diversity cost.

## 2026-06-27 — `implementation`: the pagination model (source-page vs. printed-page citation)

Closed the source-page citation limitation by making the page/line convention an **explicit input**, not a
property the engine infers from markers. A new `PaginationModel` carries two orthogonal axes, implementing
all three options recorded earlier:

- **Page boundaries** (`Pages`): `.markers` (source breaks — the prior default), `.linesPerPage(N)` (a uniform
  printed page of N text lines), `.explicit([offsets])` (the real edition's page starts, by source offset).
- **Line numbering** (`LineNumbering`): `.perPage` (reset each page — the critical-edition layout) or
  `.continuous` (through-numbered, e.g. a poem cited line 1–1247 regardless of page).

Threaded through `Tokenizer.tokenize` and the `Collation` facade (`collate` / `variantGraph`), defaulting to
`.default` so all prior behaviour and tests are unchanged. The tokenizer's existing text-line/word-on-line
machinery is reused; only *when a new page begins* and *whether the line counter resets* are now model-driven.
Demonstrable from the CLI: `--lines-per-page 40` moves a citation from "p.1 · line 4" (one source page) to
"p.2 · line 2" (the 2nd printed page) for the same word.

**Why it matters for the paper.** This is the citation-model lesson taken to its conclusion: *page and line
are editorial conventions the tool must be told.* The data model already produced continuous numbering for an
unmarked witness (it was a side effect); making it one explicit mode among several turns an accident into an
intended, documented choice, and lets the tool cite faithfully against a physical edition when its pagination
is supplied (`.explicit`) — the most faithful mode — or approximate it (`.linesPerPage`) when it isn't.

## 2026-06-27 — `implementation`: lexical-diversity cost — adaptive anchoring + bounded fallback

Turned the characterized lexical-diversity *cost* into a *mitigation*. Two mechanisms, matching the
"adapt the n-gram length / bound the worst case" notes recorded with the original finding:

1. **Adaptive anchoring (`adaptiveAnchors`).** The anchor pass now retries with progressively SHORTER n-grams
   (from the requested length down to a floor of 2) when the longer grams are too sparse to chunk the matrix
   usefully — "useful" scaled to the witness size (≈ one anchor per 50 tokens, capped). Shorter grams are
   likelier to be unique-in-common, so a moderately repetitive witness still gets *some* anchoring instead of
   collapsing to one matrix; distinctive prose keeps the longer, more reliable trigrams (the longest n that
   clears the bar wins).
2. **Bounded no-anchor fallback (`boundedNW`).** When even bigrams find no landmarks, the fallback is exact
   Needleman–Wunsch below a cell cap (~1M cells), and ABOVE it splits the pair into positional chunks
   (`chunkSize` = 400) and aligns each — capping cost at O(n·chunkSize) instead of O(n·m). It is a *degraded*
   alignment (it assumes the witnesses stay roughly positionally aligned, all that's knowable without
   landmarks), engaged only on adversarial low-diversity input. Effect: a pathological 4000-token,
   6-word-lexicon pair drops from a multi-second full matrix to well under a second, and still detects edits.

**Why it matters for the paper.** It makes the engine's cost a *graceful* function of lexical diversity
rather than a cliff: high-diversity prose runs in near-linear chunks (anchors plentiful); moderate diversity
is rescued by shorter anchors; only genuinely pathological input hits the bounded fallback, and even then the
tool stays responsive and correct-enough rather than hanging. The two tunables — the anchor-density target
and `chunkSize` — are the parameters a cost/quality analysis in the write-up would sweep.

**Residual.** The bounded fallback's positional chunking can misalign across a chunk boundary in adversarial
input (acceptable, since such input has no exploitable structure); the density target and chunk size are
fixed constants, not learned.

**State:** 64 tests green (6 pagination, 5 lexical-diversity, plus the prior 53). All four originally-recorded
open items — semantic layer aside — are now addressed: cross-page attribution, move-with-internal-edit,
source-page citation model, and lexical-diversity cost. The remaining deferred item is the optional semantic
(paraphrase) layer.

## 2026-06-28 — `design` + `implementation`: banded NW replaces the positional-chunk fallback

Reviewing the no-anchor fallback raised a fair objection: the positional chunker was a **degraded**
alignment. It advanced *both* cursors in lockstep (cut A and B at the same offset, NW each slice), so its cut
points were chosen by position alone with no guarantee the two slices corresponded. After an early
insertion, every later chunk was misframed by the drift, and a correspondence straddling a chunk boundary
could never be matched — spurious indels clustered at the seams. It was only *acceptable* because it fired
solely on pathological low-diversity input, where there is no "right" alignment to lose.

**Replaced with banded Needleman–Wunsch.** The standard remedy: compute only the DP cells within a `band` of
the (length-rescaled) diagonal — `O((n+m)·band)` instead of `O(n·m)` — which, unlike chunking, is **globally
optimal** whenever the true alignment stays within the band (no seams, so no boundary artifacts). The band
**auto-widens** (doubling) while the optimal traceback rides its interior edge, converging to full NW for
genuinely drifting input while staying cheap when drift is small. `boundedNW` now: exact NW below a cell cap;
banded above it.

**Two subtleties found and fixed in test:**
- *Corner false-positive.* The endpoints (0,0) and (n,m) sit on the band boundary by construction; flagging
  them as "edge contact" made every length-mismatched pair request widening. Fixed by detecting edge contact
  only for **interior** rows.
- *Adversarial widening.* On a tiny-lexicon text every path scores alike, so the optimum legitimately hugs
  the edge everywhere — auto-widening would chase to O(n·m) (a regression to ~9s). Resolved by **capping the
  band low** (`maxBand` = 256) and accepting an *approximate* alignment there; there is no meaningful optimal
  alignment of near-random tokens to forfeit. Pathological 4000-token case: ~9s (uncapped) → **~0.2s**.

**For the paper.** This is the cleaner statement of the cost/quality trade-off: banding makes the engine
*exact and cheap* on the realistic worst case (a long but loosely co-linear pair) and *cheap and approximate*
only on adversarial input that carries no alignable structure — a single mechanism with one honest knob
(`maxBand`) rather than a special-case chunker. **Hirschberg's algorithm** is recorded as the alternative if
exact alignment of a *fully arbitrary* large pair is ever required (full NW in O(n·m) time but O(min(n,m))
space — it cures the memory cliff, not the time one); banding is preferred because the realistic input is
co-linear, where a small band is both correct and far cheaper.

**Residual.** On capped-band adversarial input the alignment is approximate (by design); `maxBand` and the
anchor-density target remain fixed constants, not learned.

**State:** 66 tests green; full suite ~0.8s. The "degraded fallback" caveat is closed. Next: output/interchange work
before the optional semantic layer (decision 2026-06-28).

## 2026-06-28 — `abstraction`: JSON interchange (cross-language / web / WASM readiness)

Added `CollationJSON` — a stable JSON encoding **decoupled from the engine's internal Swift types**, so a
non-Swift consumer (a future WASM/web front end, an HTML apparatus export, or a harness comparing this engine
against another collator) can read the output. The design choice worth recording: rather than bolt `Codable`
onto the domain types — whose `Range<Int>` and `Set` shapes make awkward, order-unstable JSON — the wire
format is a **separate DTO layer** that reshapes the model for portability:

- token ranges → explicit half-open `{ from, to }` (not Swift's `Range` encoding);
- `VariationType` → a string-backed enum, so JSON carries `"substitution"` not an ordinal;
- locations carry **both** 0-based fields **and** the 1-based `cite` string (a JS client needn't re-derive it);
- variant-graph readings (a `Set`) → **sorted** arrays, and JSON is emitted with sorted keys, so output is
  **byte-stable** across runs and languages — important for snapshot tests and for diffing this engine's
  output against another tool's.

`schemaVersion` tags the contract for forward-compat. Keeping the wire format separate from the internal types
means the two can evolve independently — the right boundary for an external/interchange format. This does not
change the engine; it is an output adapter. `swift run collate-demo --json` emits the N-witness graph + each
successive pair.

**Why for the paper / the project.** It makes the engine's results *language-agnostic data*, which (a) keeps
the door open to a web demo or WASM build without rewriting the engine, and (b) gives a concrete artifact for
an **empirical comparison against CollateX or Juxta** in the write-up (collate the same witnesses, diff the
JSON). See [`COMPARISON.md`](../reference/COMPARISON.md) for where this engine already departs from CollateX.

**State:** 71 tests green (5 new for the JSON layer).

---

## 2026-06-29 — `abstraction`: conformance corpus + JSON Schema (the portability contract, executable)

Turned the portability claim into something *checkable*. Two backlog Tier-1 items (B1, B2) land together
under `docs/conformance/`:

- **B1 — golden corpus.** 16 language-neutral cases (`cases/<n>-<name>/`), each a `meta.json` (base,
  witness order, `recordAccidentals`, pagination model, normalizer) plus plain witness files, with the
  expected `{ graph, pairs }` interchange committed under `golden/`. The cases were chosen to span the
  engine's behaviour matrix — substitution / insertion / deletion, clean transposition and
  move-with-internal-edit, GB/US spelling folded vs. recorded as accidentals, a ≥3-witness graph,
  agreement-only, reworded-clause-as-one-substitution, page-aware citation and through-numbering,
  apostrophe/hyphen and non-Latin (Greek) tokenisation, mixed variants, and the six-edition fixture — so a
  port that reproduces them has exercised the spec.
- **B2 — JSON Schema.** `collation.schema.json` (draft 2020-12) is the formal wire contract for the
  interchange, with `$defs` mirroring the `CollationJSON` DTOs and a `schemaVersion` const.

The design choice worth recording: the goldens are produced through the **same code path as the CLI**.
The `--json` emit logic was extracted into `CollationJSON.output(...)` / `outputString(...)` and
`collate-demo` now calls it, so `golden/<case>.json` is the *actual* artifact a consumer receives, not a
test-only re-encoding. `ConformanceTests` verifies the engine reproduces every golden byte-for-byte,
checks the output is deterministic (guarding §9 rule 5), and strictly decodes each golden into the DTOs —
a dependency-free structural conformance check — while asserting the schema's `schemaVersion` const stays
in step with `CollationJSON.schemaVersion`. A `COLLATION_RECORD=1` env flag regenerates the goldens after
an *intentional* behaviour change. A language-neutral `validate.py` (+ `requirements.txt`) validates the
goldens against the schema literally, so any system or port can re-run the check.

**Why for the paper / the project.** This is the reproducibility artifact: "re-implement and hope" becomes
"re-implement and verify." It makes the determinism rules (§9) executable, gives web/WASM consumers a
machine-checkable contract, and is the concrete substrate for the empirical CollateX/Juxta comparison
(collate the same witnesses, diff against a golden). The `ALGORITHMS.md` porting checklist (§11.7) now
points a port at this corpus as the whole-port validation step.

**Resolved by this entry:** B1 ✓ · B2 ✓ (both Tier-1 portability items).

**State:** 75 tests green (4 new in `ConformanceTests`; one is skipped except under `COLLATION_RECORD=1`).

---

## 2026-06-29 — `usage`: first real-edition case study (Frankenstein 1818 vs 1831)

Ran the engine on **genuine prose it didn't grow up on** — the opening of the creation scene from Mary
Shelley's *Frankenstein*, Chapter 5, in the 1818 first edition versus the 1831 revision (verbatim from
Project Gutenberg #41445 / #84, public domain). Committed as conformance case
`17-frankenstein-creation-scene` (with source provenance in its `meta.json`) so it's reproducible and
locked as a golden; written up in [`CASE_STUDY.md`](CASE_STUDY.md). This begins backlog **B4**, the
paper's biggest credibility gap.

**What it showed.** Across ~203 words of real century-old prose, substantive collation correctly reported
the two paragraphs as **near-identical** — the right scholarly judgement, since every real 1818→1831
change in this passage is *accidental* (comma drops, `:`→`;`, `dun white`→`dun-white`,
`window-shutters`→`window shutters`, `—`→space). No false positives from that punctuation/hyphenation
churn; a line- or character-diff would have reported dozens. The single flagged variant —
`dun white` (two tokens) → `dun-white` (one token), a `substitution` — is *correct given the tokeniser*
but is really a **tokenisation** effect, and the other accidentals are invisible even under
`--accidentals` because `dropPunctuation` removes punctuation before alignment.

**Why it matters for the development arc.** Two things were confirmed empirically rather than asserted:
(1) the headline claim — separate real variation from accidental noise without churn — holds on
out-of-distribution prose; (2) **tokenisation is the next real frontier** (motivating **B6**): intra-word
hyphenation/apostrophes change token boundaries and therefore the collation, and treating hyphenation as
an accidental would be high-value. The study also surfaces a scope question worth recording — a
`recordPunctuation` (diplomatic) mode that keeps punctuation as a first-class accidental — explicitly out
of scope for the *substantive* prototype but now evidenced as a worthwhile extension.

**State:** 75 tests green (no new test; the case is exercised by the existing `ConformanceTests` golden
check — corpus is now 17 cases, one of them a real edition).

---

## 2026-06-29 — `usage`: second real-edition case — Whitman, *Song of Myself* (1855 vs 1891)

Added the **positive** counterpart to the Frankenstein case: Whitman's "Song of Myself" opening, 1855 first
edition vs the 1891–92 "deathbed" edition (conformance case `18-whitman-song-of-myself`, written up in
[`CASE_STUDY.md`](CASE_STUDY.md)). Where Frankenstein tested false-positive *resistance* on an
accidental-heavy passage, Whitman tests *recall* on genuine **substantive** revision. Sourcing note worth
recording: the only machine-readable 1855 first edition is an OCR scan with errors; it was **hand-corrected
against the canonical 1855 transcription** (so the collation reflects real revision, not OCR noise), with
the authentic four-dot ellipses retained — the provenance and the correction are recorded in the case's
`meta.json`.

**What it showed — the engine doing exactly the right thing on real revision.** Two insertions, correctly
typed and located: (1) the famous three-word `and sing myself` at line 1; and (2) the **eight-line,
two-stanza addition** (`My tongue…`, `Creeds and schools…`) reported as **one coherent insertion block**
spanning lines 6–13 — not shattered into per-word noise. The anchor-based alignment found the shared lines
on both sides of the gap and attributed the whole inserted passage as a single variant. No false positives,
right types throughout.

**A limitation this case made concrete.** The N-witness apparatus prints "(no points of variance)" for the
pair even though the *pairwise* report is correct: the variant **graph** is base-anchored and **pure
insertions are not yet anchored into it** (a previously-recorded deferred item). The pairwise engine sees
the insertions; the graph view doesn't yet surface them. This is now the motivating example for the fuller
token-graph merge a richer viewer will need.

**Together (Frankenstein + Whitman)** the two real cases bracket the engine's behaviour — accidental-only
near-identity *and* substantive insertion — which is the credibility bracket B4 wanted. Next real-text
targets: a passage with genuine **transposition**, and a third author, to widen the one-author/many-editions
matrix.

**State:** 75 tests green (no new test; corpus is now 18 cases, two of them real editions).

---

## 2026-06-29 — `usage`: real-text testing widened — transposition, translation, and a second language

Extended the real-edition study from two cases to **five, across three authors and two languages** (all in
[`CASE_STUDY.md`](CASE_STUDY.md); conformance cases 19–21), deliberately exercising *different variant types
and different kinds of variation*:

- **Transposition on real-derived text** (`19-whitman-transposition`). The engine's headline feature. A
  verbatim 1891 Whitman stanza-pair is witness A; witness B relocates one intact line. Result: **one
  `TRANSPOSITION`**, not delete+insert — contribution #1 demonstrated outside the crafted corpus. *Honest
  caveat recorded:* this is **semi-synthetic**. A survey of Whitman 1855/1891 (poet-of-the-body stanza, the
  "kosmos" lines, the catalogues) found substitutions and merges but **no clean line-level authorial move**;
  the textual scholarship explains why — Whitman's documented rearrangement is at **poem/cluster**
  granularity, not within a passage. Found line-level transposition is rare in the wild (a finding worth the
  paper). A poem-cluster real case (multi-poem witnesses) is future work.
- **Translation collation** (`20-verne-translation`). A genuinely *new axis*: two competing English
  translations of Verne's *20,000 Leagues* (Mercier 1872 vs the unabridged Walter; Gutenberg #164 / #2488).
  The engine anchored on shared words and reported **13 phrase-level substitutions, coalesced** (reworded
  clauses as single substitutions), all located. The substantive collator produces a clean apparatus for
  *translation* variants — a real application it wasn't designed around.
- **French tokenisation** (`21-verne-french-editions`). The same passage in two French Gutenberg editions
  (#5097 / #54873), differing only by a comma. Correct **no-variants** result (comma folded); a control edit
  (`personne`→`quiconque`) confirmed the French was genuinely tokenised through the elisions (`L'année`,
  `n'a`). First non-English text in the corpus; accents and elision apostrophes handled.

**Why this matters for the narrative.** The development arc now reads: build + tune on a crafted corpus →
run unseen on five real passages → the crafted-corpus claims (typed variants, reworded-clause coalescing,
located transposition) **held**, AND the engine **generalised** to translation and to French, AND the same
exercise **surfaced three concrete limitations** (B6 hyphenation, B6b punctuation, B6c pure-insertions-in-
graph). That "tested in the wild — here is what held and what broke" story is folded directly into the paper
(the engine paper, in preparation, and
[`../reference/PAPER_NOTES.md`](../reference/PAPER_NOTES.md) §10–11).

**State:** 75 tests green (no new test; corpus is now 21 cases, five of them real-text studies).

---

## 2026-06-29 — `usage`: N-witness, cross-language, and a third script — and a corpus-shaping finding

Pushed the real-text study to **eight cases** (conformance 22–24), targeting the gaps the previous entry
flagged: N-witness graphs on real text, a cross-language witness set, and a third script. Each produced a
clean result *or* an instructive limit; both kinds are written into the paper docs
([`../reference/PAPER_NOTES.md`](../reference/PAPER_NOTES.md) §10–11).

- **N-witness cross-language graph** (`22-verne-trilingual-graph`: Verne French + Mercier + Walter). The
  first ≥3-witness real case — and an **instructive negative**: with no shared lexicon across French↔English
  the base-anchored fold aligns the witnesses *positionally*, not by meaning. This is the **limit of
  base-anchored progressive alignment across a language boundary**, now logged as backlog **B10**
  (translation-aware anchoring). It is also the first concrete architectural lesson for the project's stated
  goal — a **collated Verne digital corpus** spanning all French editions and English translations:
  within-language collation (cases 20, 21) works as-is; the French↔English axis needs the B10 layer.
- **N-witness three real editions** (`23-whitman-three-editions`: *Song of Myself* 1855 / 1860 / 1891). The
  genuine "one author, many editions" graph the variant-graph design targets. Pairwise it tracks the
  evolution exactly (1860 adds section numbers `1./2./3.`, 1891 drops them and inserts `and sing myself`);
  the **apparatus under-reports** because pure insertions aren't graph-anchored — the **B6c** gap, now
  demonstrated on a real three-edition set rather than a single pair.
- **Cyrillic** (`24-pushkin-cyrillic`: Pushkin's *Я вас любил*, 1829). A third script family. A controlled
  one-word substitution (`искренно`→`сердечно`) is located at line 7, word 5 — proving Cyrillic
  tokenisation/citation. With Greek and French this **bounds** the tokeniser claim to *alphabetic* scripts;
  **scriptio continua (CJK)** stays an explicit B6 limitation, not claimed.

**On the "found transposition" search.** Following up the previous entry: a survey of Whitman 1855/1860/1891
(the poet-of-the-body stanza, the "kosmos" lines, the catalogues) again found substitutions and merges but
**no clean line-level authorial move**. The scholarship confirms why — Whitman's documented rearrangement is
at **poem/cluster** scale (the "Calamus" cluster moved toward the front between 1860 and 1867). So the
honest result stands: line-level moves are rare in the wild; the semi-synthetic case 19 remains the
line-level demonstrator, and a *found* poem-cluster transposition (multi-poem witnesses) is logged as the
next real transposition case.

**Sourcing note.** Clean public-domain non-English plaintext is uneven: Gutenberg's older Russian texts and
a 3rd public-domain English Verne translation were not retrievable as plaintext; the 1860 Whitman and 1855
texts are archive.org OCR (hand-corrected against canonical transcriptions, documented in each `meta.json`);
the Pushkin Cyrillic came verbatim from Russian Wikisource raw wikitext. All provenance + any OCR-correction
or semi-synthetic caveats live in the cases' `meta.json`.

**State:** 75 tests green (no new test; corpus is now 24 cases, eight of them real-text studies; goldens
validated against the schema). New backlog item **B10** (cross-language/translation-aware anchoring).

---

## 2026-06-30 — `test` + `usage`: benchmark harness — cost is now *measured*, not characterised (B3)

The evaluation had a hole: cost was *characterised* (it depends on lexical diversity, not just length —
2026-06-28 entry) but never **measured**. Closed it with a `collate-bench` executable target (backlog
**B3**) and recorded numbers in [`BENCHMARKS.md`](BENCHMARKS.md) (CSV at `benchmarks/results.csv`), feeding
the engine paper's evaluation.

**Design.** A deterministic SplitMix64-seeded generator produces witnesses parameterised on the three
cost-driving axes — **length**, **lexical diversity** (the fraction of distinctive tokens, which sets
**anchor density**), and **witness count** — and the harness times the public API (`collate`,
`variantGraph`) as the median of 5 release-build trials after a warm-up. It reports `anchorDensity` beside
each time because that is the variable that *explains* the time, and prints a self-describing header (host,
cores, build, trials) so a recorded run can't be misread. Output is both a readable table and a CSV.

**Measured findings (and why they matter for the paper).**
- **Pairwise is near-linear in length** for realistic prose: 500 → 8000 words (16×) ≈ 1.4 → 27.8 ms (≈ 19×).
  An 8k-word lightly-edited pair collates in **< 30 ms** — the anchor-chunking is empirically keeping NW off
  its `O(n·m)` worst case, exactly as the complexity analysis predicts.
- **Lexical diversity's effect is modest** at realistic anchor densities (~30 % across diversity 0.1–0.9 at
  fixed length): the adaptive anchor pass stays effective while *any* unique n-grams survive. The cliff is
  the *near-zero* anchor-density regime (capped by the banded fallback) — characterised, not re-measured
  here, since the generator floors density above zero (an adversarial all-repetition point is the noted
  extension).
- **The N-witness graph scales ~linearly in witness count**: 2 → 8 witnesses (4×) ≈ 10.6 → 59.3 ms (≈ 5.6×),
  consistent with the progressive base-anchored fold.

**Why this is the right shape.** The harness is deterministic and its CSV committed, so the *relationships*
reproduce (absolute times are host-specific and the header says so) — the same reproducibility ethos as the
conformance corpus. Together with the real-edition study (B4, *correctness* on real text) the benchmark
(B3, *cost* on controlled inputs) completes the two halves of the evaluation the paper needs.

**State:** 75 tests green (the benchmark is a separate executable, not a unit test — it is a measurement
tool, run on demand). New target `collate-bench`; corpus unchanged at 24 cases.

---

## 2026-06-30 — `implementation`: intra-word hyphenation folded as an accidental (B6, first part)

Fixed the tokenisation wart the Frankenstein case exposed (entry above / CASE_STUDY Case 1): `dun white`
(two tokens) vs `dun-white` (one token) read as a spurious **substitution** because the hyphen fused two
words into a single token. Scholarly practice treats hyphenation as an *accidental of word-division*, so the
fix is to **split**, not to special-case the comparison.

**Design.** A new `Normalizer.splitHyphenatedWords` flag (default **on**; **off** for `.diplomatic`, which
must stay exact). When on, the tokeniser breaks a word run containing an **interior** hyphen into its
component WORD tokens, emitting each hyphen run as a foldable PUNCT token: `mother-in-law` → `mother` `-`
`in` `-` `law`, and `dun-white` tokenises identically to `dun white`. A leading/trailing hyphen does *not*
split (it abuts the word edge); apostrophes never split. The split is done with explicit character ranges so
citations/navigation stay correct. This is a **port-visible** rule, so it is written into the portability
spec (`reference/ALGORITHMS.md §2`): a port must split the same way to reproduce the goldens.

**Effect.** Frankenstein case 17 now collates as **no variants** (was one spurious substitution) — the
correct result, since every real change in that passage is accidental. The apostrophe/hyphen case 13 now
reports only the genuine `couldn't`→`wouldn't` substitution (the `well-known`/`mother-in-law` compounds
align cleanly). Case 18's inserted-block reading now renders `thirty - seven` (same variant count). Three
goldens refreshed; two new `TokenizerTests` lock the behaviour (`mother-in-law` splits; `dun-white` collates
identically to `dun white`; leading `-dash` does not split; apostrophes preserved).

**Why this is the right scope.** It removes a real false-positive class on real prose without touching the
alignment core, and it keeps the diplomatic path exact. The *rest* of B6 — Unicode/ICU word segmentation for
scriptio-continua scripts (CJK) — remains open and is the next tokeniser frontier; this entry closes the
hyphenation half that the real-edition study actually surfaced.

**State:** 77 tests green (2 new tokeniser tests); 24 conformance cases (3 goldens refreshed), all schema-valid.

> **Follow-up (2026-06-30) — orthogonality clarified + pinned.** A natural follow-up: what about
> `the well-known author` → `the author is well known`? The split folds only the *orthographic* axis (hyphen
> vs. space); it is **independent of the substantive axis** (word reordering/rephrasing). Worked through:
> vs `the well known author` (same order) → **no variant**; vs `the author is well known` → a **real** variant
> — shared spine `the … well known`, with `author` relocated and `is` added, reported as insertion + deletion.
> The hyphen fold does not, and must not, hide a genuine rephrase; a change *inside* the compound
> (`well-known`→`widely-known`) stays a substitution. Pinned by `TokenizerTests`
> (`testHyphenationIsOrthogonalToWordReordering`).

---

## 2026-06-30 — `test`: property-based / fuzz tests — and a latent crash they caught (B5)

Added `PropertyTests` (backlog **B5**): six **invariants** asserted over sweeps of seeded pseudo-random
inputs (deterministic SplitMix64, so any failure reproduces with its seed) — self-collation is empty;
collation is deterministic; K non-adjacent substitutions yield ≤ K substitution variations; every reported
*word* reading round-trips to a real token in its witness; a middle insertion is typed as insertion and its
reverse as deletion; and citations are well-formed (no inverted/out-of-range locations) for arbitrary input.

**The payoff — a real bug, exactly as intended.** The location property immediately crashed the engine with
`Range requires lowerBound <= upperBound`. Root cause: `Variation.location()` built the highlight char range
as `first.range.lowerBound ..< last.range.upperBound` over a token span, which **inverts** when the span's
first and last tokens are not in source-offset order (an out-of-order span the classifier can assemble around
a reordered region — and now more reachable since the B6 hyphen split interleaves word/punct tokens). Fixed
defensively by spanning the extremes (`min(lo) ..< max(hi)`), so a degenerate range can never invert. Goldens
are unchanged — the fix only rescues a previously-crashing case — and the property now regression-guards it.

**Why properties beat more fixtures here.** A hand-written test exercises the inputs its author imagined; the
fuzz swept token orderings no fixture covered and surfaced a latent crash in minutes. This is the
strengthened-correctness claim the paper's evaluation wants, at near-zero engine cost (pure tests + a
two-line guard).

**State:** 83 tests green (6 new property tests); engine hardened (location char-range guard); 24 conformance
cases unchanged.

---

## 2026-06-30 — `design` + `implementation`: single-word move recovery + move confidence (a correctness fix)

**Defect.** On `the well-known author` → `the author is well known` the engine reported `author` as a deletion +
insertion — the diff artifact the engine exists to avoid; `author` moved.

**Root cause.** The transposition detector (§5) anchors on **unique n-grams with n ≥ 2**. A word that moves
*alone* forms no shared bigram, so it never reaches the spine; the monotonic NW in the surrounding region then
renders it as delete-here + insert-there. Single-word (and short) moves were therefore invisible *by design*.
Diagnosing it, the information was actually present: in the example `author` is unique in **both** witnesses
(A@3, B@1) — the engine simply had no mechanism to use a 1-gram as a move signal.

**Fix — a displaced-reading post-pass (§6.1).** After classification, a base word under a DELETION whose
normalised key matches a compared word under an INSERTION — unique among the unmatched words on each side — is
carved out of both and re-emitted as one TRANSPOSITION. Adjacent recovered words contiguous in both witnesses
coalesce into one block (so `at last` is one move, not two). It is **conservative by construction**: a genuine
lone delete/insert has no counterpart, so the pass cannot fabricate a move; ambiguous (recurring) keys are left
untouched. It also **fixed a pre-existing latent bug**: corpus cases 04/05 (`at last` to the front) were
*already* mis-reported as insert+delete by the anchor pass, and now read as a clean block transposition.

**Move confidence (`certain` | `likely`).** To surface tentative moves, a recovered
move is `certain` only when the word is globally unique in both witnesses (an unambiguous displacement); when
the word **recurs**, the deleted/inserted occurrences were paired by elimination — plausible but not proven —
so the move is `likely` and a report/visualisation shows it as a *possible* move, not an assertion. The field
is on every `Variation` (always `certain` for non-transpositions) and rides the JSON interchange; this is a
**breaking wire change**, so `schemaVersion` bumped **1 → 2** (the schema gained `confidence`/`MoveConfidence`)
and all goldens were regenerated. It is a hook for a future `likely` *near-match* layer (misspellings/synonyms).

**Why not just lower the anchor floor to single words?**
- *What lowering the floor would do.* Allow n = 1 unique-word anchors onto the spine, so a lone moved word
  becomes a first-class anchor handled by the existing transposition machinery (page-aware spine, growth,
  recursive inner alignment) rather than a bolt-on post-pass.
- *Why it is risky.* A single word is a **weak landmark**. Function words and common nouns recur, so unique
  single-word anchors are scarce and *brittle*: a word unique today becomes ambiguous after one edit. Putting
  weak anchors on the spine invites **spurious transpositions** (any coincidentally-unique word pulled out of
  place as a "move") and **churn** (the max-weight subsequence reshuffling around low-value anchors), and it
  perturbs the page-aware tie-break that the whole transposition story rests on. It would also shift many
  existing goldens, not just the two the post-pass improved — a large blast radius on the engine's core.
- *Does the post-pass fix the problem reliably?* For the **defect as stated** — yes: any lone or short
  contiguous move of words that are unmatched-unique is recovered, deterministically, with no false positives
  on genuine deletes/inserts (pinned by `MoveRecoveryTests`). What it does **not** do is rescue a move whose
  words *recur and were mis-aligned in the first place* (those it can only mark `likely`, or miss) — that
  genuinely needs the anchor/graph redesign.
- *So why is the redesign still worthwhile (later, not now)?* The principled long-term answer is the **full
  token-graph merge** (logged below as B11; B6c is its on-ramp): a graph where every token is a node and moves are
  edges handles single-word moves, recurring-word moves, and N-witness moves *uniformly*, without a special
  post-pass and without the brittleness of single-word spine anchors. The post-pass is the **correct, low-risk
  fix for the reported defect today**; the token-graph is the **architecturally clean fix for the whole class**
  tomorrow. Shipping the post-pass now buys correctness immediately; the redesign is logged (B11) with this
  rationale so it is done deliberately, not reactively.

Logged as backlog **B11** (the anchor/token-graph redesign for robust move detection), with the trade-off
above recorded so a future implementer knows *why* the post-pass exists and *when* to supersede it.

**State:** 92 tests green (8 new `MoveRecoveryTests`); 25 conformance cases (new `25-single-word-move`;
goldens regenerated at schemaVersion 2; cases 04/05 improved to clean transpositions), all schema-valid.

---

## 2026-06-30 — `implementation`: punctuation as a first-class accidental — diplomatic mode (B6b)

**Motivation (from B4).** The Frankenstein 1818→1831 creation-scene passage is *substantively identical* —
after the B6 hyphen fix it collates as **no variants** — yet the two editions differ in a dozen places, almost
all **punctuation** (comma drops, `:`→`;`, `—`→space). A *substantive* apparatus rightly hides these; but a
**diplomatic** transcription, where punctuation is editorially significant, needs them. The case study flagged
this gap: even `--accidentals` showed nothing, because punctuation is folded *before* alignment.

**Design — a pure overlay, not an alignment change.** Rather than make punctuation drive alignment (which
would risk perturbing the substantive result), `recordPunctuation` adds an **overlay** during classification:
at each matched word pair it compares the punctuation tokens sitting in the gap since the previous matched
word, on each side, and emits any difference as a `variantSpelling` accidental (ALGORITHMS §6.2). The folded
PUNCT tokens already retain their *surface*, so the data is there. Crucially the aligner and the substantive
apparatus are **byte-identical with the overlay off** — verified by `PunctuationTests` and by the fact that
*no existing golden changed*.

**A bug worth recording (and fixing).** The first implementation reset the "previous matched word" per region;
because anchors are themselves emitted as regions, a punctuation mark at an anchor boundary was compared in
*two* adjacent regions and reported **twice** (`vain: it` with the repeated words `it was` produced two colon
accidentals). Fix: carry `prevAFull`/`prevBFull` **across** regions for the whole pairwise classification,
resetting only across a transposition (a move breaks the linear punctuation flow). After the fix the colon and
comma cases report exactly one accidental each.

**Result.** On the real Frankenstein passage the diplomatic overlay surfaces the four punctuation changes the
substantive view hides — including, pleasingly, the `dun white`→`dun-white` hyphen now showing as an
accidental (complementing B6). Committed as conformance case `26-frankenstein-diplomatic` (same witnesses as
case 17, `recordPunctuation: true`), so the substantive (case 17 → no variants) and diplomatic (case 26 → 4
accidentals) views are pinned side by side as *complementary outputs of one engine*. A `--record-punctuation`
flag exposes it on the CLI.

**State:** 99 tests green (7 new `PunctuationTests`); 26 conformance cases (new `26-frankenstein-diplomatic`),
all schema-valid; default substantive goldens unchanged. B6b done.

---

## 2026-06-30 — `design`: scope a full interactive CLI app (B9); split TEI out (B12)

Planning, not code. The prototype `collate-demo` is a one-shot preview harness; **B9** is rescoped to a full,
friendly CLI **harness for the engine**, **`collate`** — a convenient way to *exercise, test, and demonstrate*
CollationKit on real witness files (collate a chosen local directory, view in the console, **export**
text/JSON/CSV), via an **interactive menu** and a **scriptable flag** mode (plus stdin). Framing recorded
explicitly in the plan's §0: `collate` belongs in the **harness** column with the unit tests and
`collate-bench` — a tool that *drives* the engine — **not** a product layered on a finished engine and **not**
a replacement for engine development. The engine remains the primary, still-evolving work that the tests, the
CLI, and any future UI front end all drive. **Two stages recorded in §9:** *Stage A (now)* — a
proof-of-concept harness built out incrementally to drive/test each engine feature, not gold-plated;
*Stage B (later)* — polish `collate` for release **only once CollationKit reaches v1.0 / "finished"**
(hardened UX, packaging, distribution). Engine progress is the priority; CLI shine is deliberately deferred.
The full plan — layering rules, architecture, menu flow, options, output/export formats, docs, and tests — is
in [`CLI_PLAN.md`](CLI_PLAN.md).

Two design decisions worth recording:
- **A testable `CollateCLI` core, thin `collate` shell.** The menu and exporters are written against a
  `ConsoleIO` protocol so they can be unit-tested with a `ScriptedConsoleIO` (queued answers) — no real TTY —
  exactly the project's "pure core, thin shell" stance (`CollationKit` vs `collate-demo`). `main.swift` is a
  tiny adapter. Zero new dependencies (hand-rolled arg parsing).
- **The JSON interchange is always exported.** Whatever console/CSV/text format a user picks, the run also
  writes `collation.json` (the schema-v2 `{graph,pairs}` artifact) + a self-describing run manifest, so any
  result set is reproducible and consumable downstream — the same ethos as the conformance corpus and the
  benchmark header.

**TEI critical-apparatus I/O split out to B12.** It was bundled into B9's "CLI niceties," but correct TEI P5
(`<app><lem><rdg>` parallel-segmentation) is a substantial, standards-driven feature with its own validation
needs and its own render/parse models — distinct from the interactive-CLI work, and naturally paired with B8
(HTML export) as a "scholarly export formats" track. Keeping it separate stops the CLI item from sprawling.

**State:** no engine change; `BACKLOG.md` updated (B9 rescoped, **B12** added), `CLI_PLAN.md` + INDEX rows
added. 99 tests unchanged.

---

## 2026-07-01 — `test`: doc-hygiene — a build-enforced test-count guard, and clarifying the backlog order

Two small maintenance items before the next engine work.

**A build-enforced test count.** The running test count is quoted in prose in `README.md` and in this log's
`State:` lines, and `INDEX.md`'s maintenance convention asks that they be kept in step — but nothing enforced
it, so adding/removing a test could silently leave the docs stale. New `TestCountGuardTests` counts the tests
XCTest actually discovers (via `XCTestSuite.default` reflection) and asserts it equals the advertised number,
failing with a message that names the exact places to update. Turns "remember to edit the README" into an
invariant. (It counts itself, so the advertised number is exactly what `swift test` prints — no off-by-one.)

**Two axes, not one, in the backlog order.** Earlier notes read as if **B9** (the CLI) were simply "next,"
while the paper-facing docs call the token-graph merge "the highest-leverage future change" — both true of
*different* goals. `BACKLOG.md`'s "Recommended order" now separates **highest-leverage *engine* change**
(B6c → B11 → B10, the token-graph line) from **highest-value *harness*** (B9, which never gates the engine),
records the pick-up sequence, and states plainly that **B6c is the on-ramp to B11**.

**State:** `TestCountGuardTests` added (100 tests); README/INDEX updated. No engine change.

---

## 2026-07-01 — `implementation`: pure insertions anchored into the N-witness variant graph (B6c)

The real-edition study (Cases 2 & 7, Whitman) surfaced this: the *pairwise* engine reports inserted text
correctly, but the base-anchored N-witness **graph** dropped pure insertions — the apparatus printed
"(no points of variance)" for stanzas Whitman demonstrably added. B6c closes that, and does so as the
**smallest, lowest-risk slice of the token-graph work** (the on-ramp to B11), not a throwaway.

**The problem.** A pure insertion has no base token position, so the progressive fold — which keys every node
by a base index — had nowhere to hang it and skipped it. The `GraphNode` even reserved `basePosition == -1`
"for inserted-only" but nothing produced such a node, and one sentinel couldn't order or place multiple
insertions anyway.

**The fix (two small, well-motivated pieces).**
- *Thread an anchor from the pairwise classifier.* A new `Variation.insertionAnchor` records, for a pure
  insertion, the base full-token index it *follows* (`prevAFull` at flush time; -1 = before all base text).
  It's `nil` for every other variation type (they carry a `baseTokenRange`). Cheap to compute — the classifier
  already tracks the last matched base index for the punctuation overlay — and useful to the pairwise report
  and JSON too (a consumer can now place an insertion).
- *Emit inserted nodes in `variantGraph`.* Insertions are collected by `(anchor → reading → sigla)`; each
  `(anchor, reading)` becomes a `GraphNode(basePosition: -1, insertedAfter: anchor)` whose reading is the added
  text for its carriers and `∅` for the base and any witness that omits it — so it is a variant node. Nodes are
  merged into one text-ordered sequence with a total sort key (anchor index; base node before inserted at the
  same key; then reading), keeping output deterministic (§9). The apparatus types inserted nodes as
  `.insertion` with a `∅` lemma; the synopsis shows the added row with `∅` in the omitting columns.

**Wire contract → v3.** Because a node's `basePosition` can now be negative and there's a new optional
`insertedAfter`, `schemaVersion` bumped 2 → 3 (`collation.schema.json` relaxed `basePosition` to `minimum -1`
and added `insertedAfter`). `JSONEncoder` omits the `nil` `insertedAfter`, so goldens for cases *without*
insertions changed only in their `schemaVersion` line; the five cases *with* pure insertions (02, 15, 18, 23,
25) gained inserted nodes. All goldens refreshed via `COLLATION_RECORD=1`.

**Verification.** New `GraphInsertionTests` (5) lock the graph/apparatus/synopsis behaviour directly
(inserted node shape, ∅ lemma + carrier sigla, synopsis omission, multi-insertion anchor ordering,
determinism); the conformance goldens pin it end-to-end through the JSON. The Whitman three-edition apparatus
now shows the 1860 section numbers and the 1891 `and sing myself` it previously hid (`CASE_STUDY.md` updated
with the actual output). Spec updated in `reference/ALGORITHMS.md §7b` (pseudocode + a determinism note) and
`reference/PAPER_NOTES.md §5.2/§11`; the engine-paper draft records the item as found-and-fixed.

**What this is *not*.** B6c anchors *insertions*; it does not merge the graph into a full token-graph, so
recurring-word and N-witness **moves** still rely on the pairwise post-pass (§4.5). The complete fix for the
whole move class remains **B11** — but B6c proves the inserted-node shape B11 will generalise, which is why it
was sequenced first.

**State:** 105 tests green (new `GraphInsertionTests`, 5); schema **v3**; all conformance goldens refreshed;
engine change confined to `Variation` (anchor field), `Collation.variantGraph` (inserted nodes), `Apparatus`,
`Synopsis`, `CollationJSON`.

---

## 2026-07-01 — `usage`: the `collate` harness — Stage A (scriptable core), phases 1–2 (B9)

Built the first two phases of the `collate` CLI harness planned in [`CLI_PLAN.md`](CLI_PLAN.md): a **scriptable
`run`/`list`** tool over a **testable, terminal-free core**. (The interactive menu, phase 3, and release polish,
Stage B, are deliberately deferred — engine progress is the scoreboard, per §0.)

**Layering held exactly as the plan requires (§0).** Two new targets: `CollateCLI` (the pure core — parsing,
discovery, exporters, dispatch; depends on `CollationKit` only) and a thin `collate` executable (binds argv +
real stdout/stderr + `exit`). The dependency arrows are one-way — `collate → CollateCLI → CollationKit` —
enforced by the build graph; removing the CLI leaves the engine and its tests untouched. **No engine logic
lives in the CLI**: `CollationRunner` is the single point that calls `Collation.collate` / `variantGraph`, and
the exporters reuse the engine's own render models (`Report`, `Apparatus`, `Synopsis`, `CollationJSON`).

**What Stage A phases 1–2 ship.**
- `collate run [files…]` or `--dir <path> --all` → console output in `text` / `json` / `csv`, or `--out <dir>`
  to export. `--base` / `--order` choose the copy-text and order; `--diplomatic` / `--accidentals` /
  `--record-punctuation` / pagination flags mirror the engine options; a witness's id is its filename stem.
- `collate list --dir <path>` lists discovered `.txt`/`.md` witnesses.
- **Export files:** `text` → located-report/apparatus/synopsis; `csv` → `variants.csv` (one row per variant,
  RFC 4180 quoting); and — **always, whatever the format** — `collation.json` (the `{graph,pairs}` interchange)
  plus a self-describing `manifest.txt`. So any exported result set is reproducible/consumable downstream, the
  same ethos as the conformance corpus and the benchmark header.
- Clear errors + stable **exit codes** (0 ok · 1 usage · 2 witnesses · 3 IO); `--help` / `--version`.

**The design decision worth recording — a terminal-free core so it's unit-testable.** `CollateCLI.main(args,
sink:)` takes an abstract `OutputSink` and returns an exit code; it never calls `exit` or `print` directly, so
tests drive it with plain args + a capturing sink and assert output and codes — no TTY. This is the project's
"pure core, thin shell" stance (as `CollationKit` is to `collate-demo`), and it made the menu-less Stage A fully
testable now, with the interactive `Menu` (phase 3) slotting onto the same `ConsoleIO` seam later.

**The load-bearing test ties the CLI to the corpus (§0 rule 3).** Because the JSON export goes through the
*same* `CollationJSON.outputString` path as the goldens (the runner keeps the witnesses for exactly this),
`testJSONExportEqualsConformanceGolden` asserts the CLI's `collation.json` is **byte-identical** to a committed
golden (case 02, which also exercises B6c through the CLI). A CLI export and a golden are the same artifact —
which keeps the CLI honest as the engine evolves.

**State:** 120 tests green (new `CollateCLITests`, 15); two new targets (`CollateCLI`, `collate`) + a product;
**zero** new dependencies (hand-rolled arg parsing); engine untouched. Remaining under B9: phase 3 (interactive
`Menu` over `ConsoleIO` + `ScriptedConsoleIO`) and Stage B (release polish), both gated per §9.

---

## 2026-07-01 — `usage`: the `collate` harness — Stage A phase 3, the interactive menu (B9), completing Stage A

Added the interactive menu (CLI_PLAN §5), the headline of B9 and the last Stage-A phase. The bare `collate`
invocation (or `collate --dir <path>`) now launches a prompt-driven flow — directory → which witnesses →
base → order → comparison mode → pagination → format → export → confirm — that assembles a `CLIOptions` and
runs it through the **same** `CollationRunner`/`Exporter` path as the scriptable `run` command. One config,
two front doors.

**The seam that keeps it testable — `ConsoleIO`.** The menu is pure logic over a `ConsoleIO` protocol
(`write` + `readLine(prompt:)`), never real stdin/stdout, exactly as the plan requires (§2). Two conformers: a
`TerminalConsoleIO` (the shell binds it to stdin/stdout) and a `ScriptedConsoleIO` (a queued answer list) that
lets `MenuTests` drive every path with **no terminal** — accept-defaults, subset+base+diplomatic+export,
`q`/EOF quit, the confirm-declines-then-edits loop, and the <2-witnesses re-ask. EOF (nil input) is treated as
quit, so a piped or empty stdin can never hang.

**Conventions (§5):** every prompt shows the current default in `[brackets]`; empty input accepts it; `q`
quits. `--no-input` forbids the interactive path (a usage error with no subcommand), so CI must use an explicit
`run …` — the scriptable mode is the CI contract, the menu is for humans. The "which witnesses" grammar is
`all` or a 1-based index list (`1,3`), deduped and order-preserving.

**A found-and-fixed test-assumption bug (worth noting for honesty).** The first `MenuTests` subset case assumed
witnesses in insertion order; discovery sorts them (`[MS, PR, TS]`), so `1,3` picks `MS,TS`, not `MS,PR`. The
`ScriptedConsoleIO` transcript made the mismatch obvious immediately — the test was wrong, the code right — and
it doubles as evidence the scripted seam is a good way to see exactly what the menu asked and did.

**Deliberately deferred (Stage B / §9):** back-navigation (`b`), a per-section output picker, and
overwrite-confirmation before writing into a non-empty export dir — release-polish UX, parked until the engine
reaches v1.0. Stage A forward-covers the full option set and is fully tested.

**State:** 130 tests green (new `MenuTests`, 10); new `ConsoleIO.swift` + `Menu.swift` in `CollateCLI`; the
`collate` shell now passes a `TerminalConsoleIO`; engine untouched. **B9 Stage A is complete** (scriptable +
interactive); only Stage B (release polish) remains, gated on CollationKit v1.0.

---

## 2026-07-01 — `design`: prepare the token-graph merge (B11) for pickup — plan, scaffold, acceptance suite

With B6c and B9 Stage A done, the next major update is **B11 — the token-graph merge**, the recorded "single
highest-leverage future change" (it completes the whole move class *and* subsumes B6c). Because it **replaces
the engine core** — the widest blast radius on the roadmap — this entry is *preparation*, not implementation:
no engine behaviour changed, the shipping fold and post-pass still run.

**What was prepared.**
- **A design + migration plan** — [`TOKEN_GRAPH_PLAN.md`](TOKEN_GRAPH_PLAN.md): why it's worth it and why it's
  risky; the target data model (nodes/edges/spine); the merge algorithm (Gothenburg/CollateX-style, adapted to
  the engine's determinism rules and the page-aware tie-break); and — the important part — a **migration
  strategy that lands it *behind* the existing types**: build `TokenGraph` + a projection to the current
  `VariantGraph`, flip the skipped tests on one at a time, then switch `Collation.variantGraph` to the
  projection in a *single* behaviour-changing commit where goldens are refreshed and every diff scrutinised.
  Retiring B6c's `insertionAnchor` special-casing is explicitly a candidate once the projection makes it
  redundant.
- **A compiling scaffold** — `Sources/CollationKit/TokenGraph.swift`: the intended public shape
  (`TokenGraphNode`/`Edge`/`TokenGraph`, `build`, `projectedVariantGraph`) with placeholder bodies returning
  `nil`. Not wired into the pipeline; nothing calls it yet. It gives the migration a stable target.
- **A skipped acceptance suite** — `TokenGraphTests` (6, `XCTSkip` while `build` returns nil): single-word
  move (parity), the **recurring-word move** (the headline capability the post-pass can't manage — it can only
  mark those `likely` or miss them), N-witness agreement/variance, off-spine pure insertion (no
  `insertionAnchor`), determinism, and projection. The next implementer inherits an executable checklist, not
  just prose.

**Why prepare rather than build now.** The plan is deliberate about risk: the naive shortcut (lower the anchor
floor to single words) is rejected because single words are brittle spine landmarks that invite spurious
transpositions/churn. Landing the real merge safely wants the plan, the acceptance set, and the "behind
existing types" migration in hand first — which is exactly what this step puts in place, so B11 can be picked
up cleanly from TOKEN_GRAPH_PLAN.md.

**State:** 136 tests (130 green + **6 skipped** B11 scaffold); new `TokenGraph.swift` (scaffold, unwired) +
`TokenGraphTests` (skipped); `TOKEN_GRAPH_PLAN.md` added and cross-linked from INDEX/BACKLOG. **No engine
behaviour changed** — the base-anchored fold and the displaced-reading post-pass still ship.

---

## 2026-07-01 — `implementation`: fix a full-novel crash — inverted region range from B-overlapping anchors

A real-editions corpus (competing English translations of Verne, now distributed as `corpus/verne/`)
immediately earned its keep: collating the two **whole-novel** *Twenty Thousand Leagues* witnesses (~106k vs
~148k words, heavily divergent translations) aborted the process with `Fatal error: Range requires lowerBound
<= upperBound`. Fast (<1 s), so a logic trap, not a timeout. Chapter EXCERPTS collated fine; only real
full-novel scale hit it.

**Root cause.** `Transposition.uniqueCommonAnchors` de-overlaps its unique-common anchors **in A only** (it
must: B positions are intentionally non-monotonic in A-order — that's how moved blocks are detected). So two
kept anchors can overlap **in B**. The max-weight-increasing-by-B spine can then place both on the spine with
overlapping B spans, and the between-anchor region span `prevBEnd..<pin.bStart` inverts (`prevBEnd >
pin.bStart`). On the crash input the offending span was `4963..<4962`. The inverted `Range` was constructed at
the *call site* (building the argument to `appendRegion`), so it trapped before any body ran.

**Fix (minimal, no behaviour change).** `appendRegion` now takes **bounds** (`aFrom/aTo/bFrom/bTo`) instead of
pre-built `Range`s, and constructs the spans internally **clamped** (`min(from,to)..<to`). A B-overlap between
spine anchors therefore yields an *empty* gap region (there is no gap), never an inverted range. Anchor
selection, the spine, move detection, and every existing golden are untouched — the change only affects the
degenerate overlap case that previously crashed.

**Why not fix it at the anchor source.** De-overlapping anchors in B as well as A was tried first. That
*regressed* transposition detection (19 test failures): filtering on B with a single forward cursor discards
legitimate moved-block anchors (whose B positions legitimately run backwards). The clamp is the correct,
surgical fix; anchor selection must stay B-agnostic.

**Guarded.** New `PropertyTests.testLargeRepetitiveReorderedPairsDoNotTrap` — seeded (SplitMix64) large
(600–1500 word), low-diversity, block-shuffled pairs, exactly the regime that produces B-overlapping anchors —
asserts the pipeline completes. **Verified it reproduces the crash when the fix is reverted** (so it's a real
regression guard, not a rubber stamp). The Verne full novel now collates in ~3 s (≈21.8k variants), and the
committed reproducer (`corpus/verne/known-issues/repro-*-700.txt`) passes.

**State:** 137 tests green (+1 property regression); engine change confined to `Transposition.appendRegion`
(signature + internal clamp) and its two call sites; **no golden changed**; this is the *second* inverted-Range
class fixed by fuzzing (the first was `Variation.location()`, 2026-06-30).

---

## 2026-07-02 — `implementation`: the token-graph merge lands (B11) — N-witness graph is now one DAG

Implemented **B11**, the recorded "single highest-leverage" engine change: `Collation.variantGraph` no longer
runs a hand-rolled base-anchored fold — it builds a **token-graph** (`TokenGraph.build`) and projects it. All
witnesses merge into one DAG: every comparable base token is a spine node; each further witness's pairwise
collation against the base is *lifted onto that shared structure* — agreement/substitution/deletion recorded as
readings on the node, pure insertions as **off-spine inserted nodes**, and a transposition as a `isMove` **edge**
spanning the moved block. Moves, insertions, and N-witness variance are thus read off *graph structure* rather
than a chain of special cases.

**Migration, exactly per `TOKEN_GRAPH_PLAN.md §4` — behind the existing types.** The scaffold (`TokenGraph.swift`)
became the real merge + a `projectedVariantGraph(baseID:)` that returns the *same* `Collation.VariantGraph`
shape the renderers already consume. The 6 previously-skipped `TokenGraphTests` were flipped to live acceptance
tests (single-word move, **recurring-word move**, N-witness agreement/variance, off-spine insertion,
determinism, projection), plus a 7th asserting the engine's `variantGraph` *is* the projection. Only then was
`Collation.variantGraph` switched to route through it (the legacy fold is retained as `legacyVariantGraph`, a
fallback + A/B oracle).

**The single behaviour-changing diff — one golden, and it is an improvement.** Refreshing the conformance corpus
changed **exactly one** golden: `22-verne-trilingual-graph`, at **one node** (base position 0). The old fold
keyed a witness's substituted reading on its raw *surface*, so the two English witnesses split into `THE`
(en-walter) and `The` (en-mercier) — two apparatus readings differing only in **case**, an accidental the
substantive normaliser folds. The token-graph keys node readings on the **normalised** form, so both English
witnesses now group under **one** reading (`The`, `[en-mercier, en-walter]`). A cleaner, *more correct*
apparatus: witnesses that substantively agree are grouped, not split by capitalisation. Every other golden —
all 25, including the crafted move/insertion cases and the real Frankenstein/Whitman/Verne/Pushkin studies —
reproduced **byte-for-byte**, confirming the projection is a faithful drop-in everywhere the merge doesn't
genuinely improve on the fold.

**The headline capability — recurring-word moves as `certain`.** `testRecurringWordMoveIsRecovered` collates two
witnesses whose moved clause reuses recurring words (`in spring the …`); the graph reports it as move edges
(the pairwise anchor pass finds the relocated clause `certain`, and the graph lifts it), where the single-word
displaced-reading post-pass alone could only manage `likely`/miss. The move is now a first-class structural
fact.

**What this subsumes / retires.** B6c's inserted-node shape is reproduced *by construction* (an insertion is
simply an off-spine node), so the special-casing is now a projection detail rather than a distinct mechanism.
`recoverDisplacedReadings` (the single-word post-pass) still runs *inside* the pairwise collation the merge
consumes — it is the source of single-word moves the graph then lifts — so it is demoted to a pairwise helper,
not removed.

**Residual (honest).** The merge reuses the pairwise engine's move detection (each witness aligned to the base),
not a from-scratch multiple-sequence alignment; a move *nested inside* another move stays single-level as
before, and cross-language anchoring is still **B10** (the token-graph is the substrate B10 will add bilingual
anchors to). The projection's base-anchored ordering is preserved, so the apparatus reading order is unchanged.

**State:** 138 tests green (0 skipped; the 6 B11 acceptance tests are now live + 1 wiring test); one golden
refreshed (`22-verne-trilingual-graph`, the case-folding improvement above); engine change confined to
`TokenGraph.swift` (the merge + projection) and `Collation.variantGraph` (now routes through it, legacy fold
kept as `legacyVariantGraph`); schema **unchanged** (still v3 — the projection reuses the B6c inserted-node
shape, so no wire-format bump). B11 resolved.

**Paper-doc reconciliation (same day).** Because the paper material narrated the token-graph as *future
work*, the whole paper set was reconciled to a single honest framing: **the token-graph is CollateX's
field-standard structure, *adopted* in B11 — a closed shortfall, not a contribution.** Updated the engine-paper draft
(in preparation) to frame the token graph as inherited machinery, not a contribution; also `PAPER_NOTES.md`
(§5.2 rewritten as the token-graph merge with the base-anchored fold + B6c as superseded provenance; §11 and the pipeline diagram),
`COMPARISON.md` (shared-legacy bullets, the "where CollateX is ahead" shortfall, and the net assessment). The
three genuine contributions are unchanged: located page-aware transposition incl. edits-within-moves; citation
as a first-class domain model; the integration-ready pure engine.

**Design-rationale material captured for the paper (same day, follow-up).** The merge-architecture question
— *why does the engine "lift" move detection onto the graph, is CollateX's peer MSA preferable, and how would
one build it out?* — was recorded in depth so the paper can be drafted from the notes:
- **`PAPER_NOTES.md §5.3`** (new): the definitive treatment — what "lift" means at the code level
  (`TokenGraph.build` assembles the graph from N−1 pairwise alignments against a fixed base, reading their moves
  onto edges rather than computing an MSA); how CollateX differs (peer MSA against the whole growing graph); the
  four-point design rationale (migration safety / pairwise-native contributions / predictable cost / copy-text
  fit); a **base-privileged-lift vs. peer-MSA trade-off table**; the honest assessment (CollateX's MSA is more
  general and correct; the lift is a deliberate, well-scoped choice that preserves the located/page-aware
  contributions and corpus stability); and a **five-step staged build-out plan** for the peer MSA (align to the
  consensus spine → structural move detection → deterministic topological spine ranking carrying the page-aware
  tie-break → confidence from graph evidence → land it behind `legacyVariantGraph` the B11 way), with a cost
  note (consensus-spine approximation as the tractable first version, mirroring the banded-fallback stance).
- **`COMPARISON.md`** (new section "The N-witness merge architecture"): the tool-comparison summary of the same,
  cross-linked to §5.3, framing the peer MSA as CollateX's more general design and a named future increment.
- **`PAPER_NOTES.md §11`** + the engine-paper draft: a first-class **peer-MSA future-work item** and
  cross-references so the paper's methods/discussion/future-work sections draw on §5.3; `INDEX.md` updated.
No code changed; 138 tests green. This is the "how and why it was designed, how it relates to CollateX, and how
to move it forward" material the paper needs.

---

## 2026-07-02 — `design` + `implementation`: selectable merge strategy — the seam for base-privileged *vs.* peer MSA (B13 Step 1)

Addressed whether a user should be able to *choose* between the pairwise/base-privileged merge and a
future peer MSA, depending on context (material, speed, app type, complexity). The answer — **yes, they occupy
different points on a quality/cost/base-dependence trade space, so keep both as a selectable option behind one
seam** — is now both *documented* and *implemented as the seam* (not the peer MSA itself, which remains the §5.3
build-out).

**Documented (the argument, for the paper).** A new **`PAPER_NOTES.md §5.4`** records the full case: the
context-map (copy-text workflow / interactive / constrained runtime → base-privileged; base-free material /
offline quality-first → peer MSA), the **two-step shape** (seam now, UI affordance when the second strategy
exists), and an explicit **UI/UX default policy** — *smart-default by context, plain-language framing, never a
bare toggle, pin base-anchored for interactive responsiveness, don't gold-plate the UI before `.peerMSA` is
real*. `COMPARISON.md` gets a paragraph framing the two strategies as complementary options (not a one-way
replacement) and the **two-strategy ablation** they enable; the engine-paper draft adds the ablation as a
self-contained empirical contribution (one engine, one interchange, vary only the strategy, cleaner than the
confounded cross-tool comparison) and threads the selectable-strategy note through its methods section. Backlog item **B13**
records Step 1 done / Step 2 gated.

**Implemented (Step 1 — the architectural seam; non-breaking).**
- A public **`CollationStrategy`** enum (`.baseAnchored` | `.peerMSA`) in `CollationKit`, with `isAvailable`
  (`.peerMSA` → false, reserved), a plain-language `label` (no jargon — for a UI/CLI affordance), and a
  `contextualDefault(hasCopyText:)` policy shared by CLI/tests/any UI (copy-text → base-privileged; no privileged
  witness → peer MSA *once available*, else base-anchored).
- `Collation.variantGraph(strategy:)` (+ `CollationJSON.output`/`outputString`) gain a `strategy` parameter
  **defaulting to `.baseAnchored`**, so all existing callers, behaviour, and **all 26 goldens are unchanged**.
  `.peerMSA` is a *documented* fallback to `.baseAnchored` in the value-returning API (there is exactly one place
  — the `switch` in `variantGraph` — to add the real `.peerMSA` arm when §5.3 lands).
- The `collate` CLI gains **`--strategy`** (friendly aliases: `base-anchored`/`base`, `peer-msa`/`peer`/`msa`),
  shown in `--help`, recorded in the export manifest. **It rejects `--strategy peer-msa` with a clear "not yet
  available" usage error (exit 1)** rather than silently falling back — so a scripted run can never believe it
  collated with a strategy that didn't run. The default path (`.baseAnchored`) keeps the JSON export
  **byte-identical to the goldens** (the §0 rule-3 tie still passes).

**Why this is the right shape (for the paper's discussion).** It (1) *justifies* the base-privileged lift as a
deliberate, retained option fit for the dominant copy-text workflow — not a stopgap; (2) frames the peer MSA as an *additional*
capability the architecture is shaped to accept behind the same seam, with no change to callers or output type;
and (3) turns "which is better?" into a **measurable ablation** rather than an assertion. The engine is now
*ready for the future MSA update* with the plumbing in place and one clearly-marked insertion point.

**State:** 147 tests green (new `CollationStrategyTests`, 9; enum + policy, engine seam non-breaking, CLI
parsing/aliases/rejection); **no golden changed**; schema unchanged (v3); engine change is additive
(`CollationStrategy` + a defaulted `strategy` parameter threaded through `variantGraph`/`CollationJSON`/CLI).
Peer MSA itself is **not** implemented — deliberately (`PAPER_NOTES §5.3` build-out, backlog B13 Step 2).

## 2026-07-03 — `implementation`: configurable scoring presets — verse vs prose (B7)

Turned the Needleman–Wunsch scores — until now a fixed `+2 / −1 / −2` buried as a defaulted parameter — into a
**named genre knob**, the small opportunistic pickup the backlog flagged (B7). The question B7 answers: verse and
prose want *different* alignment behaviour where the aligner must trade a mismatch against a gap. In prose a
reworded word is one **substitution**; in verse a rewritten *line* is a **new line** (a whole delete + insert),
and a function word that happens to recur inside a rewrite should **not** be mistaken for a real anchor.

**The two presets (only the ratio matters — NW maximises).**
- `AlignmentScores.prose` = `+2 / −1 / −2` — **exactly the historical default `AlignmentScores()`.** This is why
  **not one of the 26 conformance goldens changed**: the default *is* prose, so every existing run is unaffected
  byte-for-byte (the `ConformanceTests`/§0-rule-3 ties still hold).
- `AlignmentScores.verse` = `+2 / −3 / −1`. The condition for the aligner to prefer delete+insert over
  substitution across a disjoint run of length *m* is `mismatch < 2·gap` (the score difference is
  `m·(mismatch − 2·gap)`). Prose (`−1` vs `2·−2 = −4`) fails it → substitutes; verse (`−3 < 2·−1 = −2`) satisfies
  it → a reworded run with no shared words aligns as a clean deletion + insertion, and a coincidental recurring
  word inside a rewrite is not latched onto as an anchor. Matches (`+2`) still dominate, so genuinely co-linear
  text is unchanged — the knob only bites in the gap regions where the choice is real.

**A `ScoringPreset` enum** (`prose`/`verse`, with `.scores` and a plain-language `label`) is the user-facing form,
kept beside the engine (not in the CLI) so CLI/tests/any UI share one vocabulary — the same discipline as
`CollationStrategy`.

**Closed a latent gap while threading it.** The N-witness path (`Collation.variantGraph` →
`TokenGraph.build`) silently **dropped** `scores` — the presets couldn't have reached N-witness collation at all.
B7 threads `scores` through `variantGraph`, `legacyVariantGraph`, `TokenGraph.build`, and
`CollationJSON.output`/`outputString`, so a preset now reaches the graph and the JSON interchange, not just the
pairwise entry point.

**CLI.** `collate run` gains **`--scoring prose|verse`** (default prose; case-insensitive; unknown value → a
usage error, exit 1), shown in `--help` and recorded in the export **manifest** (`scoring: <preset>`). A manual
end-to-end run confirms `--scoring prose` vs `--scoring verse` produce visibly different synoptic apparatus on a
recurring-word rewrite; the default keeps the JSON export byte-identical to the goldens.

**Tests.** New `ScoringPresetTests` (11): the preset→scores mapping and the prose==default identity; the
motivating verse behaviour asserted at the **raw aligner** (`needlemanWunsch` on `k a b c k` → `k x y z k`:
prose = 3 substitutions, verse = 3 deletions + 3 insertions), independent of the classifier's coalescing; the
recurring-word-inside-a-rewrite difference at the `collate` level; that the scores reach `variantGraph` and the
JSON; and the CLI flag parsing, default, error, and manifest record. A methodological note worth recording: the
first-draft motivating case (a whole *added* line) turned out to align **identically** under both presets —
because the anchor pass resolves a pure insertion before NW ever sees it, and the classifier coalesces adjacent
substitutions; the honest, observable difference is on a **reworded** span with a recurring word, which is what
the tests now use.

**State:** 158 tests green (was 147; +11 `ScoringPresetTests`; test-count guard + README/`State:` updated per the
INDEX maintenance convention); **no golden changed** (prose == the old default); schema unchanged (v3). Engine
change is additive (a named `AlignmentScores` preset + `ScoringPreset`, and `scores` now threaded through the
N-witness graph it previously bypassed). Spec: `reference/ALGORITHMS.md §10`.

## 2026-07-04 — `test`: B4 closed — a *found* poem-cluster transposition (Whitman *Calamus*, 1860 → 1867)

Completed the last open checkbox of **B4** (real-edition case study): a **found** — historically real, not
semi-synthetic — transposition at the granularity Whitman's revision actually happens. Case 3
(`19-whitman-transposition`) demonstrated the engine's headline transposition feature but had to *construct* the
move (relocate one intact line), because a survey found no clean *line*-level authorial move in Whitman — his
documented rearrangement is at **whole-poem / cluster** scale ("the incessant rearrangement of his poems in
various clusters"). This case supplies exactly that move, from real text.

**The case (`27-whitman-calamus-cluster`).** Both witnesses are verbatim opening lines of the first five 1860
"Calamus" poems, each poem an intact multi-line unit. `ed1860` is the 1860 (third-edition) cluster order
(Calamus 1–5: *In paths untrodden* / *Scented herbage of my breast* / *Whoever you are holding me now in hand* /
*These I singing in spring* / *States!*). `ed1867` is Whitman's resequenced cluster: the whole *States!* /
"For You O Democracy" poem (1860 Calamus 5) **relocated to follow the "In paths untrodden" proem**, the other
four poems intact and in order — a genuine whole-poem relocation between editions.

**What the engine did (verified before writing it up).** Reported it exactly right: **one `TRANSPOSITION`**,
`certain` confidence, of the entire relocated poem (base lines 13–15 → compared lines 4–6) — *not* a three-line
deletion + three-line insertion — and, correctly, **no substantive apparatus variance** (the text is identical;
only the order changed, so the located move carries the whole story). This is contribution-#1 behaviour (located
transposition) shown on a **found, multi-poem** authorial rearrangement, discharging the Case-3 "needs multi-poem
witnesses, future work" caveat.

**Docs (per the INDEX maintenance convention).** New **Case 9** in `development/CASE_STUDY.md` (with the table row,
the 1860 cluster table, and the found-vs-constructed framing); Case 3's caveat and Implications #1/#5 updated to
point at it as the resolution; the intro/scope lines moved from "eight cases" to "nine." `BACKLOG.md` B4 marked
**✓ done** (was ◐) with Case 9 added and the progress lines updated. Corpus count bumped **26 → 27** in the
*current-state* references (the engine-paper draft, `PAPER_NOTES §5.4`/§10, INDEX) — the *historical* "all 26
goldens unchanged" statements in earlier log entries and the B11/B7 notes are left as written (they were true when
recorded).

**State:** 158 tests green (**unchanged** — the conformance corpus is data-driven: a new case adds a golden, not a
test method; `TestCountGuardTests` is unaffected). Corpus now **27 cases / 27 goldens**; the new golden was
recorded via `COLLATION_RECORD=1 swift test --filter Conformance` and all 27 re-lock byte-for-byte (the existing
26 untouched — each case collates its own witnesses independently). Schema unchanged (v3). **B4 is now done**; the
remaining real-text ambition (cross-language French↔English collation for the Verne corpus) is **B10**, gated on
translation-aware anchoring, not on more cases.

## 2026-07-06 — `implementation`: the peer-MSA merge (B14) + translation-aware anchoring (B10) — the token-graph line completes

The two milestones the backlog ordered as "next" landed together — B14 first (B10 attaches to it), plus the
hardening fixes the Verne corpus surfaced while exercising both. This is the largest engine change since B11,
and it closes the two architectural gaps the paper-facing docs have carried as caveats: **base-privilege in
alignment** (PAPER_NOTES §5.3's honest assessment) and **positional degradation across a language boundary**
(CASE_STUDY Case 6).

### B14 — `.peerMSA` runs as itself (`Sources/CollationKit/PeerMSA.swift`)

Implemented per the five-step outline (BACKLOG B14 / PAPER_NOTES §5.3), as the **tractable first version** the
cost note names — align against the graph's **linear consensus spine**, reusing `Transposition.align` (anchors,
NW, the page-aware tie-break via per-slot pages) rather than rewriting alignment:

1. **Progressive merge against the consensus, not the base.** The spine seeds from `witnesses[0]` (the render
   key), then every further witness — processed in **sorted-id order**, not input order — aligns against the
   majority reading per slot. A consensus TIE keeps the **incumbent** (creation) reading: flipping to a variant
   on a 1–1 tie broke anchors for later witnesses (measured as scattered alignments in `collate-bench` before
   the fix). Insertions **splice into the alignable spine**, so a later witness matches text the base lacks —
   `the red rose`(B) vs `a red rose`(C) yields ONE shared `red rose` reading + a `the|a` divergence, where the
   lift produced two unrelated whole-run nodes. (Adjacent inserted slots with identical witness-partitions
   coalesce at finalisation, so a lone witness's inserted run still reads as one apparatus row.)
2. **Structural moves.** Anchor-pass transpositions and a merge-level displaced-run recovery both become
   `isMove` edges; within-move edits apply through the blocks' inner alignments.
3. **Deterministic spine ranking.** Everything is array-ordered with lexicographic ties; the graph is
   **byte-stable under witness reordering** (`PeerMSATests` pins it) — the determinism bar the MSA makes harder,
   met by canonicalising the merge order rather than hoping.
4. **Confidence from structure.** `TokenGraphEdge` gains `confidence`: the lift inherits the pairwise value; the
   peer merge derives it structurally — a displaced pair unique among the *unmatched* occurrences is forced
   (every other occurrence is matched in place; re-pinning identical tokens is a no-op) → **`certain` where the
   pairwise post-pass could only say `likely`** — the headline acceptance criterion, pinned by the
   recurring-word `author` test. Recovery is bounded by a clause-scale **`displacedWindow` (12)**: the Verne
   corpus showed a common word inside a genuinely NEW passage pairing with a distant unrelated omission — a
   false long-range "move" that also punched holes in inserted runs (`absent his lectures` — the `from` was
   carved out). The locality bound killed both symptoms.
5. **Landed the B11 way.** Same `TokenGraph` shape → `projectedVariantGraph` and every renderer unchanged;
   `.baseAnchored` stays the default; **no pre-existing golden changed**; the peer dimension is pinned by NEW
   strategy-pinned conformance cases (meta.json gains optional `strategy` and `lexicon` fields):
   `28-peer-shared-insertion` (the grouped partial insertion) and `29-verne-trilingual-peer` (below).
   `collate-bench`'s graph sweep now runs witness-count × strategy — the peer merge is *faster* than the lift
   (it skips the per-witness classifier) at comparable N-scaling, and both collate the full Verne novels
   (~105k/144k words) in < 4 s.

**Honest residuals, stated where they bite:** alignment is against the linear consensus (an approximation of
full graph alignment, as the plan allows); the apparatus is still *rendered* against `witnesses[0]` — the
output shape needs a copy-text lemma — so base-privilege is confined to rendering and removed from alignment;
and the peer apparatus is token-granular, so an unequal-length local rewrite can render as substitution +
insertion where the lift coalesced one entry (the same granularity that makes cross-witness sharing work; the
bench's higher peer `variants` counts are this, not extra findings).

### B10 — `TranslationLexicon` (`Sources/CollationKit/TranslationLexicon.swift`)

The Verne-corpus enabler, built exactly as specified: an **additive, alignment-only** layer. Equivalence groups
(`"année, year"`; `"marquée, marked, signalised"`) map to one **pivot key** used by `Collation.comparable` — the
anchor pass and NW treat translation pairs as equal — while readings keep each witness's own normalised form and
surface. Consequences, each tested (`LexiconTests`, 7): nil/empty/irrelevant lexicon is **byte-for-byte the
identity** (every pre-existing golden holds); a pairwise lexicon match is structural agreement, guarded from
mis-reporting as a `.variantSpelling` accidental (the classifier now requires normalised equality there — a
no-op without a lexicon); a *moved* translation pair is recovered as a move (`recoverDisplacedReadings` pairs on
pivoted keys); and in the peer merge the consensus keys are pivoted too, so the whole N-witness graph anchors
across the boundary. CLI: **`--lexicon <path>`** (one group per line, comma-separated, `#` comments; clear IO/
usage errors; recorded in the manifest). On the real trilingual opening (case 22's witnesses), the graph now
reads `0 L'année] year en-mercier en-walter · 3 marquée] marked en-walter; signalised en-mercier` — correctly
paired renderings where Case 6 recorded positional drift — pinned as **`29-verne-trilingual-peer`** with the
lexicon inline in its meta.json. *Residual:* single-token noun–adjective inversions (`phénomène inexpliqué` vs
`mysterious phenomenon`) are an NW tie and can pair one slot off; sentence-aligned parallel-text anchors remain
the richer future layer.

### Also in this change-set

- `CollationStrategy.peerMSA.isAvailable` → true; `contextualDefault(hasCopyText: false)` now resolves to
  `.peerMSA`; the CLI accepts `--strategy peer-msa` (the validate guard remains for future reserved strategies).
- `CollationRunner`/`Exporter` thread the lexicon; the manifest records it.
- Stale B13-era tests updated to the new reality (availability, contextual default, CLI acceptance).

**State:** 173 tests green (was 158; +8 `PeerMSATests`, +7 `LexiconTests`; 24 suites); corpus **29 cases / 29
goldens** (27 pre-existing byte-identical; 28–29 pin the peer/lexicon dimension); schema unchanged (v3 — the
strategy/lexicon are run *inputs*, recorded in the CLI manifest and case meta.json, not the wire format). Full
Verne novels: both strategies < 4 s. **B14 ✓, B10 ✓; B13 lacks only a UI affordance (future work). The token-graph
line — B6c → B11 → B13 → B14 → B10 — is complete.**

## 2026-07-07 — `usage`: run feedback (the full-text "hang") + the interactive collation viewer (B8)

Driven by real use: collating the **full** *20,000 Leagues* witnesses (~105k/144k words) from the CLI "seemed
to hang at 'collating'". Diagnosis: the engine was **fine** (the collation itself finishes in ~4 s — the B5-era
crash fix and the banded fallback hold at novel scale); the *harness* was silent while it worked and then
dumped a **7.2 MB / 180 095-line** text report to the terminal — minutes of scroll that reads exactly like a
hang. Fixed as a *feedback* problem, and shipped the result-exploration piece (B8) the text dump was standing
in for:

**1. Progress + explicit completion.** `CollationRunner.run` accepts a `progress` callback; `execute` reports
each stage to **stderr** — witnesses loaded (ids + sizes), `collating pair i/N: a ↔ b …`, `building the
N-witness variant graph (strategy) …`, `rendering (format) …` — so stdout stays clean for piped
`--format json/csv/html`. Every run ends with an unambiguous
`✓ collation finished — 2 witnesses, 21 868 variant(s) …, 57 243 variant node(s) — in 4.2s`, plus
`open …/collation.html to explore the collation interactively` after an export.

**2. Console preview cap.** The console `text` view now truncates at `consoleLineCap` (2 000 lines) with an
explicit notice (total lines, variant counts, and the `--out` pointer). File export always writes the complete
report — the cap is console-only presentation.

**3. B8 — the interactive collation viewer (`collation.html`).** A single self-contained page (no network, no
dependencies), written on **every** `--out` export and available as `--format html` (also in the menu's format
list): **perspective tabs** — the base text annotated with every witness's divergences, each witness's text
annotated with how it differs from the base (the base-anchored pairs the runner now computes for the viewer;
for 2 witnesses this reuses the existing pair, zero extra cost); **alignment at a glance** — unmarked text is
agreement, spans coloured by type (substitution/insertion/deletion/moved/spelling), `likely` moves and
within-move edits visually distinguished; **exploration** — a filterable variant panel, click → detail (both
readings, both citations, type + confidence), and *perspective hops*: an entry with no span on the current side
(a deletion viewed from the witness that omits it) jumps to the side that shows it; the N-witness apparatus
(variant graph) as its own view. Implementation (`HTMLExport.swift`): the page embeds witness texts +
annotations as JSON — `TextLocation.charRange`'s UTF-16 offsets are exactly JavaScript's string indexing — and
slices spans client-side, keeping the exporter a **pure, deterministic** function of the run
(`HTMLExportTests`, incl. a `</script>`-injection guard). **Verified in a real WebKit browser** (Playwright:
tabs with counts, span click → detail, the deletion hop switching perspective, the apparatus view, a
screenshot): zero JS errors; the full-novel 14 MB page loads and renders **~21k interactive spans in ~2 s**,
perspective switch ~100 ms.

**Scale check (the motivating scenario):** `collate run --dir corpus/verne/20000-leagues/full --all` now shows five
progress lines, prints a 2 004-line capped preview, and finishes explicitly; `--out` exports everything
(9.3 s end-to-end incl. all renders) and names the viewer to open.

**Fix (2026-07-07, same change-set).** The console format-switch (feature #2, streaming the picked format to
stdout when there is **no** `--out`) had been nested *inside* the `if let dir = opts.outDir` export branch, so
a no-`--out` run — `collate run a.txt b.txt --format html`, and the interactive menu's console collation — wrote
its files-list but never streamed the report/page. `execute`'s own docstring ("either export **or** print to
the console") disambiguates the intent: moved the switch to the `else` branch. Caught by the two suites that
pin exactly this path (`HTMLExportTests.testConsoleHTMLFormatPrintsThePage`,
`MenuTests.testBareInvocationLaunchesMenuAndRuns`), which had been red; full suite green again.

**Follow-up (2026-07-07): graph-stage progress + a sharper debug warning.** A run was reported "frozen
for a few minutes at *building the N-witness variant graph*". Diagnosis (measured): the *release* build finishes
the full 2-witness *20,000 Leagues* pair in ~5 s, but the same run in a **DEBUG build does not finish in 2 min**
— the graph-build/alignment work is many times slower unoptimised, and because the graph stage was a **single**
progress line, a debug run looked frozen there. Two changes, both feedback (no algorithm change — the graph is
byte-identical):

1. **Per-witness graph progress.** `TokenGraph.build`, `TokenGraph.buildPeerMSA`, and `Collation.variantGraph`
   take an optional `progress: ((String) -> Void)?` (a pure side-effect on the calling thread; nil = silent, so
   the pure/deterministic contract is unchanged). The base-anchored merge reports `merging witness i/N onto the
   spine: base ↔ w (reusing pairwise result | collating — no reusable pair)` as each witness folds, then
   `finalising the graph (S spine nodes, I inserted, M move edge(s)) …`; the peer merge reports `aligning
   witness i/N against the consensus spine …`. The runner forwards these through the same stderr channel,
   indented two spaces so they read as sub-steps under the stage header. (Note: on the normal CLI path the
   pairwise results are *reused*, so the graph merge itself is cheap — the visible time in a debug build is the
   pairwise-collation stage, which already reported `collating pair i/N`; the new lines make the graph stage
   equally legible rather than a black box.)
2. **Debug warning names the symptom.** The `#if DEBUG` large-input warning (>200k chars) now prints the input
   size and states plainly that a stage that *looks* frozen is almost certainly the debug build, with the
   `swift run -c release collate` / `.build/release/collate` fix — measured seconds vs. minutes.

Verified end-to-end: release 3-witness full-novel run shows the two `merging witness …` lines + finalisation and
finishes in ~5.7 s; a debug run emits the warning and the graph sub-steps (visibly progressing) before it is
killed at the timeout. Tests: `HTMLExportTests.testGraphBuildReportsEveryWitnessInOrder` (N-witness ordering +
indentation) plus new assertions in `testRunReportsProgressAndFinishesExplicitly`.

**State:** 181 tests green (was 180; +1 `HTMLExportTests`; 25 suites); corpus unchanged (29 cases; goldens
untouched — the viewer is presentation, the wire format stays schema v3). `OutputFormat` gains `.html`;
`CollationRun` gains `basePairs` (viewer annotations) + `totalPairVariants`. **B8 ✓** — of the scholarly-export
track only B12 (TEI) remains; harness polish beyond it is B9 Stage B.

## 2026-07-07 — `usage`: a visual directory picker in the interactive menu

Running `.build/release/collate run` (the scriptable path) in expectation of the menu hit
`no witnesses: …` — and showed the need for a menu that lets the user **visually navigate** to the witness folder
and the output folder rather than typing paths. Two things were conflated and both are now fixed:

1. **Which invocation is the menu.** The menu has always been the **bare** `collate` (no subcommand); `run` is
   the no-menu scriptable path that requires files. This was under-documented and the error was unhelpful. The
   `no witnesses` error now says so and points to bare `collate`; `--help` USAGE labels the two paths (MENU vs
   scriptable); the README `collate` section leads with the distinction and the release callout shows
   `.build/release/collate` (bare) as the release equivalent of `swift run collate`. (Behaviour identical in
   debug and release — the menu was never debug-only.)
2. **The picker itself (`DirectoryBrowser.swift`).** A browse-and-pick navigator over the existing `ConsoleIO`
   seam (so it's terminal-free and testable): lists the current folder's subdirectories numbered, `<n>` descends,
   `.` goes up, empty line selects the current folder, and a typed/pasted path still works as a shortcut; `q`/EOF
   cancels. Starts from the current working directory
   (or `--dir`). Wired into **both** menu steps: prompt 1 (witness directory, `requireExisting: true`) and the
   reworked prompt 8 (export — now a Yes/No, and on Yes a browser with `requireExisting: false` so a
   not-yet-created output folder typed at the prompt is accepted and the exporter makes it). Verified live on the
   real Verne corpus tree (now `corpus/verne/`): browse to earth-to-moon, pick html + an output folder, and
   `collation.html`/`collation.json`/reports land in the chosen folder.

**State:** 188 tests green (was 181; +7 `DirectoryBrowserTests`; +0 net in `MenuTests` — the 10 existing menu
tests were re-scripted for the browser's select-current step + the Yes/No export prompt; 26 suites). Corpus
unchanged. No engine change — this is CLI harness UX only (`collate` → `CollateCLI` → `CollationKit` one-way dep
intact; the engine kernel is untouched). B9 Stage A gains the directory picker; Stage B (release polish) still
gated on ~v1.0.

**Redesign, same day, after review.** The first picker was clumsy: it listed only subfolders (the witness files
you were about to collate were invisible), "empty line selects the current folder" gave no cue *when* a folder
gets chosen, and it used `.` for "up" — which in Unix is the *current* directory (`..` is up). Rebuilt to read
like a file-oriented CLI tool: each view is a **unified listing** — subfolders numbered (`<n>` opens) *plus* the
witness files present with sizes — over a persistent action line that names every command: `u`/Enter **USE THIS
FOLDER** (its label shows the witness count, e.g. `USE THIS FOLDER (2 witnesses)`, and USE is refused with a
reason until a folder holds ≥2, so you can't leave the browser on a bad choice), `..` up, `<n>` open, type a
path, `q` cancel. Starts at the CWD so a globally-installed `collate` (on `$PATH`, invoked by name) begins where
the user is. The `DirectoryBrowser.Purpose` (`.witnesses` / `.output`) tailors the USE label and the ≥2 guard.
`DirectoryBrowserTests` rewritten (7 → 9); one `MenuTests` case (`testFewerThanTwoWitnessesReasksThenSucceeds`)
re-scripted — the <2 guard now lives *in* the browser (warn + keep browsing), not a bounce out to a menu re-ask.

**State:** 190 tests green (+2 over the first cut; 26 suites). Same UX-only footprint — engine untouched.

**Path fix (same day).** `..` misbehaved: launched with no `--dir`, the browser started at the literal relative
string `"."` (it existed as a directory, so it was kept as-is), and `..` = `deletingLastPathComponent(".")` →
`""` → the `/` guard — so "up" from the cwd jumped to the **filesystem root** instead of the cwd's parent. Fix:
`current` is now made **absolute and standardized** at entry (`normalizedExistingDir` resolves a relative start
against the cwd via `standardizingPath`), so `..`, descent, and typed relative paths all operate on real
absolute paths. Legend clarified to `../` (the Unix relative-parent form; the bare `..` is still accepted), and a
typed `../other` now resolves correctly. Regression pinned by `testRelativeStartResolvesSoUpIsNotRoot` (cd into a
temp subdir, start `"."`, assert `../` shows the parent not `/`) and `testUpGoesToParent` (both `..`/`../`).

**State:** 191 tests green (+1 regression; 26 suites). Engine untouched.

## 2026-07-07 — `usage`: collation.html viewer — performance + UX fixes (3 of 5), rest planned

Real use of the interactive viewer on the full *20,000 Leagues* collation (~248k words, ~21.9k annotations, ~57k
apparatus entries) surfaced five UX issues. The three tractable/high-value ones shipped now; the two large
visualizations are specced in [`VIEWER_UX_PLAN.md`](VIEWER_UX_PLAN.md) for a next pass.

**Root cause of the lag (#1):** `render()` rebuilt the *entire* DOM — re-slicing the 597k-char text into ~21k
spans — on **every** interaction, including a single span/row click (~2.9 s each on the novel). Fixed by
splitting render into cheap chrome (`renderChrome`: tabs/legend/meta) vs. the heavy view (`renderView`:
text/apparatus re-slice), and giving `select()` a **fast path**: same perspective + text already rendered → it
toggles `.active` on just the two affected spans (via a `spanByIdx` index built during slicing), updates the
detail panel and the list's active row — **no re-slice**. Heavy ops (tab/perspective switch, filter change,
perspective *hop*) run behind a **spinner** (`#busy` + `withSpinner()` double-rAF so it paints first). The
apparatus list is chunked + capped (`APPARATUS_CAP = 4000`, "showing N of M" notice) so the unbounded 57k-div
render can't hang. **#4:** clicking a variant row from the apparatus tab now leaves it for the text view (the
`select()` re-render path detects `state.apparatus`). **#5:** the legend hides zero-count types
(`if (!(c[t] > 0)) return`), so `spelling 0` no longer clutters a substantive collation.

**Verified in a real browser** (Playwright + WebKit, against the **14 MB full-novel** page — the small fixture
hides perf regressions; a local harness prototype, not distributed, 11/11): load ~2 s; **selection
handler ~100 ms with 0 text re-slices** (was ~2.9 s); spinner fires on tab switch; apparatus→row jump switches to
text; legend shows only the four types with matches (no `spelling`). No JS errors. Pure-exporter contract intact
(`HTMLExportTests` green; the change is JS/CSS in the template + payload unchanged).

**Remaining (see VIEWER_UX_PLAN.md), not started:** **#2** a *visual* variant-graph view (columnar CollateX-style
alignment table + SVG move arcs, replacing the apparatus text-list) plus a metadata "what was/wasn't detected"
panel; **#3** a *parallel* base⇄witness side-by-side view (matching highlights + linked scroll; connector lines
deferred). Both are self-contained (CSP: no libs), windowed for the novel, and — for the 2-witness case — need no
new engine data (the `annotations[]` already carry both sides). #2 needs a `graph` block added to the payload
from `run.graph` (spine + edges incl. `isMove`).

**State:** 191 tests green (26 suites) — same count; the viewer fixes are JS/CSS in the HTML template, exercised
by the Playwright harness, not the XCTest suite. Engine untouched.

## 2026-07-08 — `usage`: collation.html viewer — the two visualizations + metadata panel (5 of 5 done)

Closed the last two items from [`VIEWER_UX_PLAN.md`](VIEWER_UX_PLAN.md) — the ones needing an actual
*visualization*, not a text list — plus the "what was detected" panel folded out of #5.

- **Engine surface (the one non-JS change).** The apparatus-facing `Collation.VariantGraph` projection
  deliberately drops the merge substrate (spine order, edges, `isMove`, inserted-node anchors) — but the *visual*
  variant-graph needs exactly that back. Added `Collation.variantGraphWithTokens(…)` returning
  `(VariantGraph, TokenGraph?)`; `variantGraph` now delegates to it (byte-identical for every existing caller).
  `CollationRunner` keeps the raw graph on `CollationRun.tokenGraph`. `VariationType` gained `CaseIterable` so the
  summary can list every type (incl. the zero ones).
- **Payload.** `HTMLExport` gained a `graph` block (`spine`, `nodes`, `edges{from,to,isMove,confidence,witnesses}`)
  and a run-wide `summary` block (type counts across the whole run, witness sizes, graph shape). Determinism held
  (sorted keys, no timestamps). *Payload-size lesson:* emitting full `readings`+sigla on all ~145k spine nodes
  made the novel's HTML balloon to ~57 MB; the graph is mostly agreement, whose reading is identical across
  witnesses, so agreement nodes are compacted to a single `agree` surface. (The residual ~37 MB is the 96k genuine
  variant points of two independent translations — irreducible for a full graph.)
- **#2 visual variant-graph** — a columnar CollateX-style "score" layout: spine walked left→right, agreement
  columns greyed/compact, variant columns stack one sigla-labelled, type-coloured row per reading, inserted nodes
  slotted after their anchor column. **Windowed** (only the columns near the viewport are built — ~113 on the full
  novel, not 145k), move edges drawn as inline-SVG arcs (dashed = `likely`) over the visible window, an overview
  minimap, and click-to-cross-link into the base text. (The self-containment guard greps for `http://`; the SVG
  namespace constant is assembled from parts so it isn't mistaken for a fetched resource.)
- **#3 parallel ⇄** — base ⇄ one witness (selector), variation highlighted on *both* sides in matching type
  colours, ∅ gap markers where a side omits, linked scroll, hover flags the counterpart span. No new engine data:
  the base-anchored `annotations[]` already carry both sides.
- **Metadata / "what was detected"** — the tail of #5: run-wide per-type counts where a `0` reads
  *"checked — none found"* (answers "why is there no spelling filter?"), witness sizes, merged-graph shape, run
  settings.

Verified in WebKit via Playwright on the **full** *20,000 Leagues* collation (145k spine / 96k variant / 1,659
move edges): zero JS errors, all five views correct; load 2.6 s, graph switch ~0.5 s (windowed), info ~0.2 s,
parallel ~3.4 s behind the spinner (paragraph windowing remains the lever if that needs to drop).

**State:** 194 tests green (26 suites) — +3 `HTMLExportTests` pinning the new payload blocks (graph substrate,
detection summary, move edges). The interactive JS itself is covered by the Playwright/WebKit harness, not XCTest.

## 2026-07-08 — `usage` + `proof`: `no_collate` editorial exclusion, and a long-distance-transposition defect it exposed

Using the parallel ⇄ view on the *full* 20,000 Leagues collation surfaced that "the two texts never align." Two
distinct causes, one editorial and one algorithmic:

**(1) Front matter — fixed with editorial markup.** Walter and Mercier open with completely different
edition-specific matter (a translator's note + Introduction + Units of Measure vs. a Contents + List of
Illustrations). The global aligner was force-matching these into hundreds of junk "substitutions" AND — worse —
using their unanchored common words to justify matches *across the whole novel*. Added a **`no_collate` region**
to the tokeniser: text wrapped in `<!-- no_collate … -->` (the comment's own `-->` closes it; `<!-- /no_collate -->`
also accepted; an unclosed open runs to EOF) emits **no tokens**, so it never reaches the aligner. This is the
region analogue of the existing page-break marker (which skips a point). The two Verne witnesses' front matter was
consolidated into one clean region each, ending exactly at chapter 1. Result: the first body annotations are now
short chapter-1 prose variants instead of multi-hundred-char garbage; the excluded matter is still *displayed* in
the viewer, just not *aligned*. (`TokenizerTests`: 4 new tests.) The parallel view's linked scroll was also
changed from **proportional** (scroll-%) to **anchored** — it keeps the counterpart of the topmost visible variant
span at the same screen offset — since two translations differ too much in length for proportional to line up.

**(2) Long-distance transpositions — a real engine defect, recorded open.** Even with (1), the body still carries
**~825 `certain` transpositions with |Δbase−Δcomp| > 200k chars** — e.g. base "of the Aleutian" @14.5k matched to
comp @439k. These are the aligner picking the *wrong occurrence* of a recurring phrase far away in the other
witness, then calling the displacement a confident move. They poison the parallel view (spurious moves, and enough
of them that even the anchored scroll can't recover a sane counterpart) and draw false move arcs in the variant
graph. Front-matter exclusion does not touch this — it is the base-anchored displaced-window match being too
permissive about *distance*. **Fix (not yet done):** bound a move's plausible displacement (a max |Δ|, or a
proportional-position gate) and/or downgrade an unanchored recurring-word match from `certain` to `likely`. Filed
as the next engine task; the `no_collate` work + the anchored scroll are independently correct and shipped.

**State:** 198 tests green (26 suites) — +4 `TokenizerTests` for the `no_collate` region. The parallel-view scroll
change is JS, covered by the Playwright/WebKit harness.

## 2026-07-08 — `proof` + `implementation`: the displacement gate — fixing the long-distance-transposition defect

Implemented the fix filed above. Both move-detection paths accepted a match on **content** alone (a unique n-gram,
or a unique-by-elimination displaced word) with **no constraint on how far it travelled**. On two independent
translations of a novel this manufactured hundreds of book-spanning "certain" moves from coincidentally-shared
rare phrases, and — worse — those bad anchors corrupted the surrounding alignment, so the parallel view never lined
up.

**The gate.** Two aligned witnesses are globally **co-linear**: a token a given fraction through A sits near the
same fraction through B. A genuine transposition is a *local* excursion off that diagonal; a coincidence lands
anywhere. So a candidate move is accepted only when its B position is within `moveTolerance` of the
**diagonal-predicted** position (`aStart · bCount/aCount`). Tolerance = `min(6000, max(200, 0.03·len))` comparable
tokens — proportional in the middle, floored for tiny inputs, capped for huge ones. Applied in BOTH paths, sharing
`Transposition.moveTolerance`: the anchor spine (`displacementIsPlausible` filters `movedPins`) and the
displaced-word recovery (`coLinear` gates each del↔ins pairing). A rejected candidate is not a move — its tokens
fall back to ordinary region alignment, i.e. the substitution/insertion/deletion they actually are.

**Why the diagonal, not the spine.** The first attempt interpolated the *stable anchor spine* to predict B. But
with two long independent witnesses the spine is itself partly built from coincidental anchors, so a spine-relative
expectation is unreliable and let far matches look "plausible" next to neighbouring bad anchors. The whole-document
diagonal has no such dependence — it holds no matter how noisy the anchors are. (A measurement gotcha cost time:
raw |Δbase−Δcomp| is NOT the deviation when the witnesses differ in length — Walter 843k vs Mercier 597k chars
means even a perfectly co-linear point has |Δ|≈250k chars. The real metric is deviation from the diagonal.)

**Result on the full 20,000 Leagues pair** (measured as *diagonal deviation*): transpositions 1,654 → 225; **max
deviation 722,845 → 28,388 chars** (~4,800 tokens; a genuine local move), **zero** beyond 50k chars (was hundreds).
The parallel ⇄ view now **aligns** — a WebKit test scrolling the base column to a body variant brings the
counterpart to the same screen offset (Δ 66 px; `synced: true`), and Walter's "CHAPTER 10 / The Man of the Waters"
sits beside Mercier's "CHAPTER X / THE MAN OF THE SEAS". Legitimate local-move detection is unchanged (all move
tests green).

**State:** 201 tests green (26 suites) — +3 `MoveRecoveryTests` (far coincidence rejected, local move kept,
tolerance bound). Determinism and the existing move/transposition suites unaffected.

## 2026-07-08 — `implementation`: expanding-window move search (refining the fixed displacement gate) + full documentation sync

Two things in this entry: the engine refinement suggested when the gate landed, and a full pass over the
documentation and paper notes for the recent run of work (viewer completion, `no_collate`, the gate).

**Expanding-window search.** The fixed displacement gate is robust but blunt: a hard cutoff also rejects a
*genuinely large but singular* move (a relocated chapter). The displaced-word recovery (§6.1) now decides the
distance question with a **nearest-first, expanding-radius** search (`Transposition.pairByExpandingWindow`):
order candidate (deletion, insertion) pairs by diagonal distance; accept a near one immediately; reach past the
near window only when the pairing is **unambiguous** (no rival sharing an endpoint within ~2×, `ambiguityRatio =
0.5`); never pair beyond `maxMoveTokens`. A widened acceptance is `likely`, never `certain`.

*A negative result worth recording.* The first cut also **dropped** the long-standing "unique among the unmatched
words on both sides" restriction, letting the window pair any recurring key by proximity. On the full novel that
manufactured **~1,400 spurious single-word "moves"** — `of`, `and`, `was`, `just` — out of ordinary alignment
noise (common function words the aligner had left unmatched). The fix: keep the uniqueness restriction (it is what
makes "the same word, relocated" a defensible claim) and let the window govern **only distance**. With that, the
full-novel profile is the clean 225 transpositions again (211 `certain` + 14 `likely`), the 14 `likely` being real
unique displacements the fixed bound had discarded — the intended win, with none of the noise. The anchor path
keeps the plain fixed gate (an anchor is unique-in-both by construction — one candidate, nothing to search).
Parallel view still aligns (`synced: true`); all five viewer views clean in WebKit.

**Documentation & paper sync.** Brought the whole doc set current with the viewer completion, `no_collate`, the
displacement gate, and this refinement: `ALGORITHMS.md` (§2 no-collate regions, §5.6 gate + expanding-window
pseudocode, §6.1, §9 determinism rule 8, §10 parameters), `PAPER_NOTES.md` (§3 editorial exclusion, §4.6 the gate
and expanding-window, §9 parameters, §11 resolved-limitations, and a new **Appendix A**), the engine-paper draft
(found-and-fixed bullet), `INDEX.md`, `BACKLOG.md` (three items marked done + the
expanding-window recorded), and the README test count. **Appendix A** ("Why not more memory, and why not learning
across documents?") answers two recurring questions in principled terms: accuracy here is set by decision rules,
not storage (the engine is not memory-bound; the defects we fixed were rule fixes with zero extra state; the only
memory-shaped concern is the viewer payload, a rendering matter); and cross-document learning would trade away the
determinism, reproducibility, and auditability that make computational collation admissible as scholarship, for a
corpus-biased convenience its audience does not want — the legitimate version of that instinct is the explicit,
user-owned configuration the engine already provides (`no_collate`, lexicon, pagination, normaliser, scoring).

**State:** 206 tests green (26 suites) — +5 `MoveRecoveryTests` for the expanding-window (near accept, far-but-
unambiguous accept, beyond-ceiling reject, ambiguous-far reject, nearest-of-two). Determinism and the conformance
goldens unchanged.

## 2026-07-09 — `usage`: collation.html legibility pass (5 fixes from real use)

Five viewer fixes after using the page on the full novel, all JS/CSS in `HTMLExport.template` (the exporter and
its payload are unchanged, so `HTMLExportTests` and the goldens are untouched; verified in WebKit via Playwright):

1. **Persistent colour key on every text tab.** The legend now shows a fixed `Key:` (all five variation types
   with coloured swatches) *plus* the `Show:` filters — the key teaches the colours, the filters toggle them
   (previously only the filters existed, so a reader had no colour legend).
2. **Sticky selected-variation metadata.** `#side` is now a flex column: the `#detail` card is pinned and only
   `#list` scrolls, so the metadata of a selected variation stays visible however far down the (full-novel-long)
   variant list you scroll.
3. **The variant graph now reads as a graph.** Replaced the flat row of boxes with a proper spine diagram: a
   horizontal backbone rule, a node **dot** per position sitting on it, agreement words compact under their dot,
   variant readings hanging **below** as sigla-labelled branches, and the move arcs bowing up from the spine — a
   one-line explainer header names the parts. Column stride widened (40→58 px) so two-translation density stays
   legible; the focused node expands to show full readings.
4. **Apparatus explainer.** A sticky header states plainly what the apparatus criticus *is* and how to read one
   `№ base ] reading SIGLA` line (with a worked example and the witness-ID legend), for non-specialists; entries
   render with styled sigla and `∅` for omissions, and point at the Variant graph tab for the visual form.
5. **"What was detected" → the Overview home tab.** Renamed to **Overview**, moved first, and made the default
   landing view, with an orientation intro (what a collation is; the base + witnesses; a navigation card per tab)
   above the existing whole-run counts / witness sizes / graph shape. A reader now lands on an explanation, not
   raw highlights.

**State:** 206 tests green (26 suites) — no engine or payload change; the viewer work is exercised by the
Playwright/WebKit harness, not XCTest.

## 2026-07-09b — `usage`: collation.html interaction pass (4 fixes from continued use)

Four more viewer fixes (JS/CSS in `HTMLExport.template`; the only payload change is two nullable fields —
`apparatus[].from/to`, the lemma's base char range — so the goldens/`HTMLExportTests` are unaffected). All
verified in WebKit via Playwright on the fixture and the full novel (0 JS errors).

1. **Overview → a dashboard.** The home tab is now data-visualisation: the orientation intro kept, but the
   navigation cards are **clickable** (each jumps to its tab via `goTo(mode)`), the headline numbers are stat
   tiles, the whole-run variation breakdown is a **horizontal bar chart** (a `0` still shown as "checked"), and
   the witnesses render as edition cards with relative size bars.
2. **Graph node → an in-tab detail panel (no redirect).** Clicking a graph node used to navigate to the text
   view. It now populates a panel **below the graph** with the node's readings and a windowed **snippet of each
   text** (base + the witness, `<mark>`-highlighted), plus buttons to *then* open that spot in the base text, the
   witness text, or the parallel view. Nothing navigates until the user chooses.
3. **Graph uses the vertical space.** The spine baseline was raised well down the viewport (`SPINE_TOP` 168 px)
   so move arcs bow up prominently *above* it and variant readings hang on a connector *below* it — reading like
   a real graph rather than a shallow strip. Active node gets an amber halo.
4. **Apparatus is self-contained.** The apparatus tab's list was disconnected from the text-tab sidebar (two
   different datasets; clicking a sidebar row left the tab). Now the apparatus is one panel: a scrollable
   **clickable** list of entries whose click highlights the line and fills the apparatus's **own** detail panel
   below (all readings + sigla + a "Show in base text" link) — staying on the tab. The text-tab sidebar is hidden
   here.

**State:** 206 tests green (26 suites) — payload gained only `apparatus[].from/to` (nullable); viewer behaviour is
covered by the Playwright/WebKit harness.

## 2026-07-09c — `usage`: collation.html — three more fixes (jump-to-variant, node legibility, apparatus scroll)

All JS/CSS in `HTMLExport.template` (no payload/engine change; verified in WebKit on the fixture + full novel, 0
errors):

1. **Graph node links jump to the exact variant.** The graph's node-detail buttons ("Open in base/witness text",
   "Open in parallel ⇄") now land *on* the referenced variant rather than merely opening the tab: the base/witness
   text scrolls to the covering annotation's span (keyed `seg{offset}`, with a nearest-span fallback) and marks it
   `active`; the parallel view scrolls **both** columns to the annotation's `.pv[data-idx]` spans and marks them.
   Both add a brief amber **flash** so the spot is obvious. The jump is made reliable by an `afterRender()` poller
   (the target view renders behind the spinner and a full-novel slice can outlast a fixed timeout) — it retries
   for ~2 s until the target span exists. *Bug found doing this:* the parallel jump targeted `mateAnn.idx`, but the
   found annotation object has no `.idx` — captured the array index (`mateIdx`) explicitly.
2. **Clearer graph nodes.** Each variant node's branch card now STACKS a small witness chip (sigla) above its
   reading, one row per witness, with a type-coloured left stripe — legible in a narrow column, and widening on
   hover/active to show full readings. (A first attempt made the sigla a wide coloured chip that *obscured* the
   reading — reverted to the stacked, quieter form.) Column stride widened to 78 px to suit.
3. **Apparatus list scrolls.** Root cause: `ON_DISPLAY.apparatus` was `block`, but `#apparatus` is a flex COLUMN
   (fixed help header · `flex:1` scrollable `.aplist` · detail panel); as a block the list had no bounded height
   and could not scroll. Changed to `flex`.

**State:** 206 tests green (26 suites) — no payload/engine change; viewer behaviour covered by the Playwright/WebKit
harness.

## 2026-07-10 — `usage`: collation.html — a new "Changes" visualization + four fixes

Five viewer items from continued use on the full novel. All JS/CSS in `HTMLExport.template`; the only payload
additions are two nullable fields (`Annotation.baseAnchor` — an insertion's base char anchor, for #5). Engine
untouched; verified in WebKit (fixture + full novel, 0 JS errors).

1. **Overlapping-span colour precedence.** A segment covered by several annotations (e.g. an INSERTION inside a
   MOVED passage) was given every type's class (`v insertion transposition`), so whichever CSS rule came *last*
   won — the move's blue overrode the insertion's green. Now the span takes only the **narrowest (most specific)**
   covering annotation's type class; `withinMove` still marks it. Verified: 0 spans carry >1 type class.
2. **Graph node hover feedback.** Hovering any node now shows it is clickable — a soft highlight box behind the
   column, an enlarged blue-ringed dot, and a blue position number.
3. **Apparatus cross-links.** Selecting an apparatus entry showed only a base-text link. It now shows the base
   *and* witness citations and the full "open in …" set (base text · witness text · parallel) — via a shared
   `mateForBaseRange()` + `variantLinks()` helper reused by the graph-node detail.
4. **Parallel line numbers.** A checkbox in the parallel bar toggles a per-column line-number gutter; each column
   text is now sliced into `.pline` rows so the gutter numbers every physical line as you scroll.
5. **New "Changes ✎" view — the transformation reading.** A tab that renders the BASE text as a track-changes
   *redline* of how it became a chosen witness: substitutions as struck `old → new`, deletions struck, insertions
   as a `‸added` caret, moves badged — so a reader unfamiliar with the texts can *watch* the base transform. Above
   it, a **change-intensity heatmap** (base split into 160 buckets, warm-shaded by how much changed, click to
   jump) answers *where/how much* at a glance, and a summary states the extent ("64.2 % of the base differs;
   21,509 changes: 17,850 substituted · 2,238 deleted · 1,197 added · 224 moved"). Clicking a change opens the
   parallel view at that variant. This is the intuitive "how/where/why did it change" view the raw highlights
   couldn't give.

**State:** 206 tests green (26 suites) — payload gained `Annotation.baseAnchor` (nullable); the viewer, incl. the
new Changes view, is covered by the Playwright/WebKit harness.

## 2026-07-12 — `usage`: Changes view — preserve the published line breaks

The Changes ("track-changes") view built the transformation reading as plain text nodes but its `.cbody` had no
`white-space` rule, so every `\n` in the base collapsed to a space and the reading was one unbroken wall of text —
hard to read. Fix: `#changes .cbody { white-space:pre-wrap }`, so the base text's own line and paragraph breaks are
preserved (long lines still wrap). The redline now follows the shape of the published prose. JS/CSS only; 206 tests
still green, verified in WebKit on the full novel (0 errors).

## 2026-07-13 — `usage`: an Alignment-confidence map + the Overview as an *analytical* dashboard

Two things: a way to CONFIRM the collation aligned correctly, and a decision on the Overview's dashboard type.
Both JS/CSS in `HTMLExport.template` (no engine/payload change); verified in WebKit on the full novel, 0 errors.

**The confidence problem (diagnosed, not a bug).** A report that the parallel view's line numbers showed a
~5,000-line gap between Walter and Mercier near the end raised the question of how to *confirm the collation
actually worked*.
Investigation showed the alignment is in fact correct end-to-end — the last aligned point is at 100.0 % of both
texts; across the whole work the comparison position stays within ~1 % of the co-linear diagonal. The 5,000-line
"gap" is honest: Walter has 17,874 physical lines, Mercier 12,174 (different translation length + wrapping), and
each column numbers its *own* lines. So the real gap was one of *presentation/trust*, not correctness.

**New "Alignment ✓" view — a correspondence dot-plot.** Every shared variation point plotted at (base position ×
comparison position). A correct collation makes the points hug a clean, monotonic near-diagonal — the reviewer
*sees* the two texts advancing together; a jump/mismatch would throw points off the line. A plain-language
**verdict** states it ("✓ the texts track each other throughout — 18,074 points, max drift 4.8 %, 98.9 %
monotonic — aligned correctly, end to end"), with a tolerance band, hover-for-citation, and click-to-open-parallel.
This is the standard dot-plot idiom from sequence alignment, and it answers "did it work?" the other views can't.
Also clarified the parallel line-number toggle (a tooltip + comment: the two counts differ because the texts do,
not because of mis-alignment).

**Overview → an ANALYTICAL dashboard.** Of the five dashboard archetypes — operational (live monitoring),
analytical (investigate *why*, explore, drill down), strategic (long-horizon KPIs), tactical (progress to a goal),
executive (at-a-glance health) — the collation Overview is best served by **analytical**: a reviewer's task is to
*explore where/how/how-much a text changed and drill into the interesting spots*, not to watch a live process or a
single KPI. The old Overview was closer to *executive* (static summary tiles). Reworked it to lead with the two
investigative questions — **"Can I trust this collation?"** (the alignment verdict, click → the map) and **"Where
do the changes fall?"** (a clickable positional histogram of change intensity across the base, type-stacked, click
a bar → that stretch in the Changes view) — plus a **"What kind of change?"** interpretation callout (dominant
type, proportions), then the type bar chart (now with %) and the reference tiles/witness cards below. Every element
is a drill-down; the shared `alignMetrics()` helper feeds both the Overview strip and the Alignment map.

**State:** 206 tests green (26 suites) — no engine/payload change; the two new surfaces are covered by the
Playwright/WebKit harness.

## 2026-07-13b — `usage`: narrative summary tool + a data-viz paper outline + a tooltip fix + a doc audit

Four items.

**Tooltip fix (viewer).** On the Alignment map, hovering a point near the bottom edge showed a tooltip that ran
off the viewport (only its heading visible); scrolling to see the rest moved the cursor off the point and hid it.
Fixed with a viewport-aware `positionTip()` that flips the tip above/left of the cursor when it would overflow, so
the whole thing stays on screen. Also parented the tip to the `#alignmap` host (cleared on re-render) instead of
leaking one on `document.body` per render.

**Narrative summary tool (`CollationNarrative`, engine).** A new pure function `CollationResult (+ the two witness
texts) → prose` that tells the *story* of a collation the way the dashboard does, in words: the extent ("differs at
N points, touching ~P% of the base"), the dominant kind + proportions, where changes cluster (thirds), the moves
(with certain/likely + cross-page), an accidentals-checked note, and an **alignment-quality verdict** computed from
the co-linearity of the correspondence points (the same drift/monotonicity the alignment map shows). Wired into the
exports as **`summary.txt`** (always written) and as the leading **SUMMARY** section of the console/combined text.
Deterministic, host-agnostic (like `Report`/`Apparatus`). On the full novel it reads: *"mercier differs from walter
at 21,509 points, touching about 64.2% of the base text. The dominant kind is substitution (83%)… The alignment is
sound: the two texts track each other throughout… the difference in overall length simply reflects that the two
texts are not the same length, not a mis-alignment."* (`NarrativeTests`, 5 cases.)

**Data-viz record + paper outline.** A new data-visualisation paper outline (in preparation, not distributed):
Part 1 is a maintained inventory of every viewer visualisation (the seven views + the narrative) — *what* it shows, its
*payload data source*, and *how it aids comprehension/trust* — plus the design constraints and the trust argument
with the full-novel metrics. Part 2 is a draft outline for a paper on *visualising collation results* (distinct
from the engine paper): the view-system over one substrate, the redline comprehension contribution, and the
alignment-confidence trust contribution, with an evaluation plan.

**Doc audit.** Brought the docs current with the seven viewer views and fresh numbers: README (viewer view list),
INDEX (VIEWER_UX_PLAN line), `PAPER_NOTES §8.1` (the interactive viewer + its visualisations
as a rendering/trust section, with the alignment metric), the engine-paper draft (alignment confidence as an
evaluation contribution). Confirmed the full-novel figures cited are accurate against a fresh run (21,509 variants;
alignment 18,074 points, 4.8 % drift, 98.9 % monotonic; ~9 s release).

**State:** 211 tests green (26 suites) — +5 `NarrativeTests`. Engine gained `CollationNarrative` (pure); exports
gained `summary.txt`; the tooltip fix is viewer JS. No change to the JSON interchange or the conformance goldens.

## 2026-07-13c — `usage`: a "Story" tab + parallel-view hover-scroll & colour key

Three viewer items (JS/CSS; the only payload change is a new nullable `narratives[]` block — the prose story per
witness). Verified in WebKit on the full novel, 0 JS errors.

- **"Story ✍" tab.** The prose narrative was previously only in `summary.txt` and the console SUMMARY section, not
  the interactive viewer. Added a Story tab that shows (a) the exact `CollationNarrative` prose (embedded in the
  payload as `narratives[]`, so it's the same single-source story) as a lede, then (b) a **section-by-section
  walkthrough** of the whole work: the base is split into 12 stretches, each summarising its changes by kind and
  showing a handful of representative examples inline in the redline vocabulary (`"old" → "new"`, added, deleted,
  moved), clickable to open in parallel, with "… and N more" for the rest. This is the "full story of all the
  changes" a reader can scroll through.
- **Parallel hover auto-scroll.** Hovering a highlighted change in one column already flagged its counterpart in
  the other; now, if that counterpart is off-screen, the **opposite** column auto-scrolls to bring it into view
  (upper-middle), guarded by a `parallelScrollLock` so the anchored linked-scroll doesn't echo it. So the reader
  always sees how the hovered passage reads in the other text.
- **Parallel colour key.** Added a `Key:` of the highlight types actually present in the pair (substitution /
  insertion / deletion / moved) to the parallel bar, matching the colours used in the two texts.

*(Where the prose summary is written, for reference: `CollationNarrative` → `summary.txt` on `--out`, the SUMMARY
section atop the console/combined text, and now the viewer's Story tab.)*

**State:** 211 tests green (26 suites) — payload gained the nullable `narratives[]` block; the three items are
viewer JS/CSS, covered by the Playwright/WebKit harness.

## 2026-07-15 — `test`: the rarity / locality gate — a lone common word, far off the diagonal, is not a move

**Found by hand-checking the graph/parallel views** of the full-novel *De la Terre à la Lune* pair
(`moonvoyage` base vs the Mercier & King translation, siglum `towle`): "quietly" at base line 2173 was reported
as *moving* to `towle` line 2217 — a phantom `likely` transposition to an entirely unrelated sentence ("a young
Floridan, who quietly said"). The visual variant-graph made the outlier obvious: a lone word arcing ~100 lines to a coincidental
same-spelling token. Reproduced against the engine: the whole duel clause containing the base's one "quietly"
was correctly a `deletion`, and *separately* a `transposition (likely)` carved that "quietly" out to `towle`'s.

**Root cause — the 1:1 test is over the wrong population.** `recoverDisplacedReadings` (§6.1) pairs a displaced
word only when its key is unique *among the unmatched words* on each side. But a word COMMON in a witness
(`towle` uses "quietly" 5×) that the aligner matched at all-but-one of its occurrences is left unmatched exactly
once — so it passes the 1:1 test. The displacement gate then only rejects *far-from-diagonal* pairings, and two
parallel translations put a common word's lone stray *near* the diagonal by coincidence. The `globallyUnique`
signal that would catch this was computed but only used to downgrade `certain`→`likely`, never to reject. Net:
a coincidence promoted to a `likely` move — 26 of them on this pair, "quietly" among them.

**A first, too-coarse attempt (recorded because it is instructive).** The initial gate keyed on the pairing's
`near` flag: drop a lone non-unique word only when it was reached by *widening* (`near = false`). That killed the
clearest far coincidence ("quietly", "along") but LEFT 14 — because `moveTolerance` (the `near` window) is
length-proportional and ≈1785 tokens on this ~60k-token novel, so most coincidences (`daily` dev 1712, `board`
533, …) still counted as "near". Re-checking the survivors by hand exposed the real structure: `near` is the
wrong axis. The one genuine local hop among them — "firearms" ("ancient or modern firearms" → "firearms, ancient
and modern", a within-clause reordering) — had diagonal deviation **46**, while every coincidence had **≥141**.
Absolute distance separates the populations; the scale-inflated `near` window cannot.

**The decision (three options were weighed).**
- *(chosen) Option 1 — locality escape:* keep a lone non-unique word only when its hop is genuinely local
  (diagonal deviation ≤ a small absolute bound). Removes every coincidence AND keeps genuine short hops of
  repeated words. Cost: one scale-independent constant.
- *Option 2 — blanket rejection* of all lone non-unique words: simpler, no constant, but discards real short
  transpositions of repeated words (which the peer-MSA path recovers) — trades false positives for false
  negatives.
- *Option 3 — keep the near-based gate:* leaves the 14 near-diagonal look-alikes in the apparatus as tentative
  moves; does not actually resolve the error class.

Option 1 chosen: highest fidelity, and the corpus evidence (a clean 46→141 gap) directly supports an absolute
bound.

**Fix — corroboration, of which locality is the third source.** A recovered move is kept iff it has at least one
of: (1) global uniqueness (unambiguous however far it moved); (2) a multi-word block (a phrase corroborates
itself); (3) a genuinely LOCAL single-word hop (`maxDeviation ≤ Transposition.localMoveTokens`). Only a lone,
globally-common, non-local word — the coincidence signature — is dropped, reverting to the plain deletion +
insertion the aligner already found. Implemented by threading each pairing's diagonal deviation
(`Transposition.diagonalDeviation`, the SAME metric `pairByExpandingWindow` measures) and `globallyUnique`/`words`
onto the coalesced block (deviation MAX'd, `globallyUnique` ANDed across the block). `localMoveTokens = 80` — the
midpoint of the 46→141 gap (≈1.7×/1.8× margins) — is isolated as one documented constant with its full corpus
calibration beside it, so a future corpus can retune the single number. The gate is a pure function of span,
global frequencies, and integer deviation (determinism preserved).

**Effect on the corpus.** Removed all **26** coincidences (`p`, `level`, `board`, … `quietly`, `along` — dev
141–5536), kept the **one** genuine local hop ("firearms", dev 46) as `likely`, left all **106 `certain`** moves
untouched; carved tokens reverted to deletions/insertions. The earlier displacement-gate work (2026-07-08)
handled *unique-word* far coincidences; this closes the *common-word near-the-diagonal* ones the proportional
tolerance structurally cannot see.

**Regression coverage.** `MoveRecoveryTests` gains 5 tests: `testCommonWordFarCoincidenceIsNotAMove` (a common
word's far leftover stays del+ins — the "quietly" shape, distilled), `testGloballyUniqueSingleWordMoveSurvives…`
and `testLocalHopOfARecurringWordSurvives…` (the two escapes that must be kept),
`testDiagonalDeviationMeasuresOffDiagonalDistance` (the metric), and
`testLocalMoveTokensSeparatesTheVerneObservedPopulations` (guards the calibration: 46 < bound < 141). The
pre-existing `testRecurringWordMoveIsCertainUnderPeerMSA` (a short local hop) still passes. ALGORITHMS.md §6.1 and
PAPER_NOTES §4.5.1 document the gate, the three corroboration sources, the calibration table, and the options.

**State:** 216 tests green (26 suites) — +5 `MoveRecoveryTests`. No schema/payload change (the gate only
suppresses spurious `transposition` variations in favour of the deletion/insertion the aligner already emitted);
goldens unaffected. `ALGORITHMS.md §6.1`, `PAPER_NOTES §4.5.1`, and `README.md` updated.

## 2026-07-16 — `test`: the anchor-path distinctiveness gate — a short common phrase, far off the diagonal, is not a move

**Found by hand-checking the earth-to-moon full-novel pair** (`moonvoyage` base vs the Mercier & King
translation, siglum `towle`, in the Verne corpus). At `towle` line 3783 the phrase "we ought always to" was
reported as a `certain` transposition from moonvoyage line 5079 — but the two are entirely unrelated sentences ("…this is not courteous! we ought always to
treat an adversary with respect" vs. "…I think we ought always to put a little art in all we do"), ≈1300 lines
apart. Not a move: two independent uses of a common phrasal template.

**Root cause — a SECOND coincidence class, on the OTHER move path.** The 2026-07-15 gate hardened the
displaced-*word* recovery (§6.1). This phantom is on the anchor-*spine* path (`Transposition.align`): "we ought
always to" is a **unique-in-both n-gram** (each of its words is common — we 138/122, ought 17/21, always 24/19, to
1384/1112 — but the joined 4-gram occurs once each), so it becomes an anchor, lands off the max-weight spine, and
is emitted as a move. Its only locality gate there is `displacementIsPlausible` with the length-proportional
`moveTolerance` (≈1819 on this novel); the phantom sits 1680 comparable-tokens off the diagonal — *just inside* the
window — so it passed. Measuring the whole pair: **≈90 of 107 "certain" moves were this shape** ("I tell you",
"in cast-iron", "which he would", …) — short common-word phrases scattered 249–1962 off the diagonal. The genuine
local moves cluster at deviation ≤ ~200 (a clean gap at 198 → 249), at every length.

**Why the proportional tolerance structurally cannot see it (same lesson as §6.1, different path).** `moveTolerance`
scales with witness length — right for admitting a genuinely LARGE move corroborated by a long distinctive run, but
far too loose to vouch for a SHORT phrase, whose stray coincidental occurrence routinely lands within ~1800 tokens
of the diagonal on two parallel translations. And unlike the single-word case, the raw anchor pin here is only ~2–3
tokens regardless — word-rarity and pin length do *not* separate the phantom from a real long move ("As soon as
Barbicane…" is also a common-word start). The one signal that separates them is the block's **grown length**: real
long-range moves grow to 12–24 tokens; coincidences stay at 3–5.

**Fix — a distinctiveness-scaled gate that runs AFTER block growth (Option: distinctiveness-scaled tolerance,
chosen over a flat cap or a word-rarity test).** Once each anchor block has absorbed its surrounding
identical run (so its true length is known), keep it only if its diagonal deviation ≤ `anchorMoveTolerance(len) =
localMoveTokens + distinctivenessPerToken · max(0, len − distinctivenessFreeLength)`. A short block earns only the
small absolute `localMoveTokens` (80) bound — it must be genuinely local, exactly the §6.1 single-word rule; each
token past the free length (4) buys `distinctivenessPerToken` (40) more, so a long distinctive passage can still
move a long way. A dropped block is *not* consumed, so its tokens fall back into ordinary region NW — the
substitution/insertion/deletion they actually are (never fabricating; only declining to reclassify). Implemented as
a `filter` over the grown `transpositions`, before the consumed-mask is built (`Transposition.swift`).

**Calibration (earth-to-moon, comparable-key space — the corpus where the phantoms were found by hand).** base
≈60.7k / compared ≈47.9k comparable tokens. Genuine local moves: "enfilading … firing" len 5 dev 37, the "same
weather" passage len 21 dev 63, the Cambridge/Florida passage len 14 dev 249 — all kept (their earned tolerances
120/760/480). Coincidences: "we ought always to" len 4 dev 1680, "I tell you" len 3 dev 1500, "in cast-iron" len 4
dev 1962 — all dropped (tolerance 80). `free = 4` targets the 3–4-gram template signature; `perToken = 40` keeps
every ≤-200 local move while dropping the far short phrases; one long borderline block ("a hundred dollars a day
…", len ~12 dev 296, tol 400) is kept — admitting one long-passage possible-move costs far less than ≈90 short
phantoms. Constants isolated beside their corpus evidence in `Transposition.anchorMoveTolerance` for future retune.

**Effect on the pair.** Transpositions **107 → 16**; the ≈90 short far coincidences reverted to plain
deletion/insertion/substitution; the phantom "we ought always to" is gone; every genuine local move (dev ≤ ~300 at
its length) survives. No golden or synthetic-test move regressed.

**Regression coverage.** `MoveRecoveryTests` gains 3 tests: `testAnchorMoveToleranceScalesWithBlockLength` (the
tolerance formula: base at len ≤ 4, +perToken beyond), `testAnchorBlockGateSeparatesTheVerneObservedPopulations`
(the gate on the exact earth-to-moon numbers — phantom len-4 dev-1680 rejected; the len-5/21/14 local passages
kept; degenerate lengths safe — this is the honest layer for the long-passage ESCAPE, a synthetic whole-passage
relocation being fragile to reproduce), and `testShortCommonPhraseFarOffDiagonalIsNotAnAnchorMove` (end-to-end: the
same short phrase in two unrelated sentences ~600 tokens apart stays del + ins). `ALGORITHMS.md §5.6` (+ the §10
param table) documents the second gate; the 2026-07-15 §6.1 gate is unchanged.

**State:** 219 tests green (26 suites) — +3 `MoveRecoveryTests`. No schema/payload change (the gate only suppresses
spurious `transposition` variations in favour of the sub/ins/del the aligner already emitted); goldens unaffected.
`ALGORITHMS.md §5.6`, `README.md` updated.

## 2026-07-24 — `test` + `proof`: the distinctiveness gate RECALIBRATED — a single-corpus tuning did not generalise

Collating the full *Journey to the Centre of the Earth* (Malleson base vs. Ward, ~74k/86k words) surfaced
outlier moves — "off the rocks" recorded as relocating ~270 lines, "our calculation. Here" swapping with an
unrelated "separate; for surely". Investigating exposed that the 2026-07-16 anchor-path distinctiveness gate
(§4.5.2), calibrated on *one* pair (earth-to-moon), **did not generalise** to other independent-translation pairs.

**Measurement (the decisive step).** A temporary instrumentation pass measured every detected move — grown-block
length and diagonal deviation — across **all four** independent-translation full-novel pairs in the corpus:
journey-to-the-centre (8 moves), earth-to-moon (15), 20,000-leagues (12), mysterious-island (13). **The gate
admitted all 48; every one is a false positive.** (An important correction to the earlier record: the earth-to-moon
"107 → 16" number was the count *after* the 2026-07-16 gate, but those 16 were not clean — the residual is the
near-diagonal class below.) *(Full-novel instrumentation must run `-c release`; the debug build segfaulted on the
~70k-token alignment.)*

**Why it leaked — the coincidences here are NEAR the diagonal, not far.** The original calibration assumed the
phantom signature was *short AND far* (earth-to-moon's "we ought always to" sat 1680 tokens off the diagonal), so
it gave every short block a flat **80-token** base tolerance, expecting real short local moves to sit ≤ ~200 off and
coincidences to sit far beyond. But two *tightly parallel* translations track each other page-for-page, so a
coincidental short unique-in-both phrase ("off the rocks", "I look at", "upon the sides of") routinely lands only
**5–100 tokens** off the diagonal — *well inside* the flat 80 base. Distance alone cannot see them.

**Signals ruled out (recorded so the dead ends aren't re-walked).** Flank-context match and co-move corroboration
are ≈0 for the false moves — but *also* ≈0 for the one genuine relocation (Whitman *Calamus*, case 27): a real move
lands among *different* neighbours too, so context cannot separate them. `dev/len` ratio and content-word ratio do
not separate the populations either (the latter re-confirms the 2026-07-16 "rarity is the wrong axis" finding). The
**only** separating signal remains grown-block **length + locality**: genuine short moves are short *and truly
local* (the crafted goldens sit at dev ≤ 5; a sentence-swap at dev 9), whereas false short blocks sit anywhere.

**The hard constraint that shaped the fix.** The conformance corpus contains genuine *short* moves that MUST
survive: case 25 "author" (len 1, dev 1), cases 04/05 "at last" (len 2, dev 2–5), case 19 (len 8, dev 5), and the
recursive-anchoring sentence-swap (len 11, dev 9). So a blanket minimum-length floor is impossible (it would drop
case 25's 1-token move), and the base tolerance cannot go below ~9 (it would drop the sentence-swap). A 3-token
near-diagonal coincidence like "off the rocks" (dev 5) is therefore **geometrically inseparable** from a genuine
short local hop — an irreducible boundary of a purely geometric method, now recorded.

**Fix — recalibrate the same length-scaled gate, and decouple its base constant.** `anchorMoveTolerance(len) =
anchorBlockBaseTolerance + distinctivenessPerToken · max(0, len − distinctivenessFreeLength)`, with the constants
moved from **(base 80, free 4, per 40)** to **(base 10, free 14, per 18)**. The base is now a *distinct* constant
`anchorBlockBaseTolerance` (10), separate from `localMoveTokens` (80) — the §4.5.1 single-word gate keeps its own
46 → 141 calibration untouched. The new shape: a block up to 14 tokens earns only the tiny base-10 tolerance (must
be genuinely local), and each token beyond 14 buys 18 more, so the 19-token Calamus relocation earns 10+18·5 = 100
≥ 84 (a 16-token margin, not on the boundary).

**Effect (four-pair audit).** False moves **48 → 11** (journey-centre 8 → 2, earth-to-moon 15 → 5, 20,000-leagues
12 → 1, mysterious-island 13 → 3) — a **77 %** cut — with every conformance golden and the genuine Calamus move
preserved. The two reported outliers on journey-centre are gone. The 11 survivors are the irreducible
residual: short blocks sitting almost *on* the diagonal (indistinguishable from a genuine local hop) plus a couple
of long near-diagonal blocks; the least-misleading false-positive shape, rare (~11 across ~1M words), and some
already surface as `likely` (possible) rather than `certain`.

**One golden changed:** `19-whitman-transposition` — the genuine move is still detected, its confidence moved
`certain → likely` (it now sits nearer a gate boundary). Regenerated with `COLLATION_RECORD=1`; no move lost.

**Regression coverage.** `MoveRecoveryTests`: the two calibration tests were rewritten for the new constants and
the corrected understanding (a len-5/dev-37 block — "enfilading, or point-blank firing", which sits at the *same*
position at the very start of both books — is a near-diagonal artifact, NOT a genuine move as the old test claimed);
added `testShortCommonPhraseNEARtheDiagonalIsNotAnAnchorMove` pinning the exact class observed on journey-centre (+1 test → 220).
`PAPER_NOTES §4.5.2 / §9 / §11`, `ALGORITHMS §5.6 / §10`, `README`, `BACKLOG`, and the engine-paper draft updated.

**Methods lesson for the paper.** A gate calibrated on a single corpus can encode that corpus's *accidental*
geometry (there, phantoms were far). Validating the same gate across four independent-translation pairs revealed
the true phantom signature is *short-and-not-locally-corroborated at any distance*, and that the residual class is
provably irreducible on geometry alone — an honest boundary, and a caution about single-corpus calibration.

**State:** 220 tests green (26 suites) — +1 `MoveRecoveryTests`; two existing calibration tests rewritten. No
schema/payload change; one golden refreshed (confidence only). Four-pair phantom-move rate 48 → 11.

## 2026-07-24b — `implementation`: scale-relative move confidence — the gate residual is `.likely`, not asserted

Follow-up to the recalibration above, closing the residual honestly. The ~11 surviving false moves are the
irreducible near-diagonal short-block class: they *cannot be dropped* (a genuine 1–2-token move — conformance cases
04/05/25 — is geometrically identical), so the right treatment is **confidence**, not suppression. "off the rocks"
should be reported as a *possible* move, never asserted.

**The rule (scale-relative, `Transposition.anchorMoveIsCertain`).** An anchor-path move that has passed the gate is
`.certain` iff it is either **distinctive by length** (grown block > `distinctivenessFreeLength` — its own length
corroborates the move, e.g. the len-24 "same weather" passage, Calamus len 22) OR sits in a **short witness**
(≤ `confidentMoveWitnessFloor = 4000` comparable tokens — where a short block's displacement is a meaningful
fraction of the document, a real swap: crafted cases 04/05, len 2, in ~10-token texts). A **short block in a long
parallel witness** — where a small absolute displacement is indistinguishable from a genuine short local hop — is
`.likely`. The signal is deliberately *scale-relative*: the same 3-token block is `certain` in a 10-token swap and
`likely` in a 90k-token novel. Applied in `VariationClassifier.classify` at the point the anchor `.transposition`
`Variation` is built (it has the comparable ranges + `aMap.count`/`bMap.count`); the displaced-word path (§6.1) is
untouched (it sets its own confidence: globally-unique ⇒ certain).

**Effect on the four full-novel pairs.** Journey-to-the-Centre: both residual moves ("off the rocks", "wholesome")
now `likely` — **zero asserted false positives**. Earth-to-moon: the distinctive len-24 "same weather" passage stays
`certain`; the short residuals ("imagine that the") → `likely`. 20,000-Leagues, Mysterious-Island likewise: every
distinctive move `certain`, every short near-diagonal residual `likely`. No move added or removed; only confidence
softened where the geometry cannot assert.

**Why this needs no schema/golden change.** `confidence` is already in the wire format (`certain`/`likely`, schema
v3, added at v2). The crafted goldens all keep `certain` (short witnesses, or the displaced-word path), so **no
golden changed**. A viewer/report already renders `likely` as "possible move".

**Regression coverage.** `MoveRecoveryTests` +2: `testAnchorMoveConfidenceIsScaleRelative` (the helper — distinctive
⇒ certain; short-in-short-witness ⇒ certain; short-in-long-witness ⇒ likely; the witness-floor boundary) and
`testShortNearDiagonalMoveOnLongPairIsLikelyNotCertain` (end-to-end on a synthetic long pair: "off the rocks" near
the diagonal is a move but `.likely`). `PAPER_NOTES §4.5.2 / §9`, `ALGORITHMS §5.6 / §10`, `README`, `BACKLOG`
updated.

**State:** 222 tests green (27 suites) — +2 `MoveRecoveryTests`. No schema/payload change; **no golden changed**
(the softening lands only on long-witness short blocks, which the goldens don't contain). Asserted (`certain`) false
moves on the four full-novel pairs: → **0**.

---

## 2026-10-03 — `test`: test-suite hygiene (release 1 review, blocker B9)

The release 1 review (`docs/development/review-2026-10/`) found two tests that asserted nothing.

- **`testShortNearDiagonalMoveOnLongPairIsLikelyNotCertain`** (2026-07-24b) built two witnesses that shared only the
  phrase "off the rocks", so the phrase became the whole spine and could never be a move; the assertion loop ran
  over an empty list. It also took 68% of the suite's run time. Rewritten: the witnesses now share a 6,000-token
  backbone with the phrase displaced by ten tokens, and the test asserts that exactly one move is recovered and
  that it is `.likely`. (A first probe at 3,000 tokens correctly gave `.certain`: that is below the 4,000-token
  `confidentMoveWitnessFloor`, so the scale-relative rule is working as designed.)
- **`testLongCollationIsDeterministic`** substituted `ship600`, which the generator never produces, so it compared
  identical texts. It now substitutes the real token `ship621` and asserts that the variant is found.

`TestCountGuardTests` is **retired**. It compared the discovered count with its own constant (it never read the
docs), it does not compile on Linux (`XCTestSuite.default` is missing from corelibs XCTest), it cannot see Swift
Testing tests, and two independent green pull requests that each add a test leave `main` red. The living docs no
longer quote an exact test count; a new suite gets a row in `TESTING.md`. Three test-file compiler warnings
(`var` → `let`) are fixed.

**State:** 221 tests green (26 suites), suite time about 8 s → 2.8 s. No engine, schema or golden change.

---

## 2026-10-03b — `implementation` + `test`: no token is used twice (release 1 review, blocker B1)

**Defect.** Unique-in-both anchors are de-overlapped in A only, so two anchors can share tokens in B. The spine
(`maxWeightIncreasingByB`) only required anchors to *start* in increasing B order, so two overlapping spine anchors
emitted the shared B tokens as matches twice. A moved anchor could likewise claim B tokens the spine owned, and two
moved blocks could grow into each other. In every case the base tokens on the other side of the duplicate match were
never reported: `alpha beta gamma delta epsilon beta gamma zeta` vs `alpha beta gamma zeta` reported only "delta
epsilon" deleted. The 2026-07-01 inverted-Range fix had clamped the region so this no longer crashed, which turned
a crash into a silently wrong apparatus.

**Fix (`Transposition.align`).**
1. The spine chain requires B-non-overlap: `bStart[j] + length[j] <= bStart[i]`.
2. Off-spine pins are trimmed to the tokens the spine does not own in either witness (`trimmedOffSpine`); a pin
   with fewer than `minAnchorLength` tokens left, or a spine token inside, is dropped to region alignment.
3. A non-adjacent moved pin whose B span is already claimed by an earlier move is skipped.
4. Block growth (and its bridging `resync`) never enters a token another moved block owns.

**Evidence.** New `AnchorOverlapTests`: the two minimal reproductions from the review and a seeded fuzz over a
small vocabulary asserting the invariant *every token of either witness is used exactly once by the alignment*. On
`main` the three tests fail with 79 assertion failures; after the fix all pass. **No conformance golden changed.** On
the three public-domain full-novel pairs the effect is small but real (Mysterious Island +3 variants; one deletion
reclassified as a substitution on each of the other two; moves and their confidence unchanged).
`ALGORITHMS.md` §5, §5.2, §5.4 and §9 rule 3 updated.

**State:** 224 tests green. No schema or golden change.

---

## 2026-10-03c — `implementation` + `test`: the base-anchored graph keeps every compared word (release 1 review, blocker B2)

**Defect.** The default N-witness merge (`TokenGraph.build`, the B11 lift) folds each pairwise substitution onto the
base nodes it covers. It paired the k-th token of the base range with the k-th token of the compared range, but both
ranges are full-token ranges that include punctuation, and compared tokens past the base range's length were
discarded (and the last one reused). So `red green` → `blue, yellow` gave `green] ,`; `red` → `very bright blue` gave
`red] very`, losing "bright blue" from the graph, apparatus, synopsis and JSON; and `old grey` → `young` claimed
"young" twice. ALGORITHMS §7b prescribed the offset rule. The peer merge (B14) was unaffected.

**Fix.** `TokenGraph.substitutionReading` pairs COMPARABLE tokens only. Equal counts map one-to-one; otherwise the
pairing is one-to-one up to the last shared position, which carries all remaining compared words joined, and any
further base node reads `∅`. The unreachable `Collation.legacyVariantGraph` (114 lines; the pre-B11 fold kept as a
fallback, which shared the bug) is removed.

**Goldens (3 re-recorded, graph only; every pairwise result is unchanged).**
- `15-mixed-variants`: `old grey` → `young` now reads `old] young`, `grey] ∅` (was a second, invented "young").
- `20-verne-translation`: punctuation readings replaced by the dropped words (`downright` → `downright
  inexplicable`, `Traders` → `Traders shipowners`, `the` → `the seaports`, …).
- `22-verne-trilingual-graph`: the French base against two English translations; the repeated, invented readings
  ("two" at several unrelated positions) become `∅`, and every compared word is kept.
Punctuation-only readings across all goldens: **19 → 0**.

**Evidence.** New `GraphSubstitutionTests` (the three reproductions, the rule itself, and a check that no golden has
a punctuation-only reading): without the fix the behavioural tests fail with 22 assertion failures; with it all pass.
ALGORITHMS §7b updated.

**State:** 229 tests green. Schema unchanged (v3); three goldens re-recorded (graph only).

---

## 2026-10-03d — `implementation` + `test`: moves reach the critical apparatus (release 1 review, blocker B3)

**Defect.** The apparatus is built from the variant graph's variant nodes. A moved passage agrees with the base
word for word, so its nodes are not variant nodes and the apparatus never showed a move: a move-only collation
printed "(no points of variance)", and the six-edition example left out its headline cross-page move. The token
graph knew every move (its `isMove` edges), but the projection to the apparatus-facing graph dropped them.

**Fix.** `VariantGraph` gains `moves` (`GraphMove`: base positions, lemma, witnesses, confidence), read off the
token graph's move edges in `projectedMoves`. A move edge runs from the spine node before a moved block to the node
after it, so the block is the spine nodes strictly between; an endpoint that is not on the spine (including the
lift's virtual end id, engine review A13) is treated as end of text. This works for both merge strategies.
`Apparatus.entries(from: graph)` adds one `.transposition` entry per moved passage, with `(moved)` or `(possible
move)` as the reading. Six editions now shows `19 The lamps were lit along the quay one by one] (moved) GB1 PR UNI
US1`; case 04 shows `8 at last] (moved) B`; the Calamus poem relocation appears too.

**No golden or schema change.** The JSON interchange encodes only the graph's nodes (its pairwise results already
carry every move with its citation). New `ApparatusMoveTests`; ALGORITHMS §7b documents the moves and the
apparatus rule.

**State:** 233 tests green.

---

## 2026-10-03e — `implementation` + `test`: the tokeniser reads every character, and quotes are punctuation (release 1 review, blockers B4 and B5)

**B4 — characters above U+FFFF were dropped.** The tokeniser built each scalar from one UTF-16 unit, which returns
nil for each half of a surrogate pair; the "never stall" branch then skipped it. Rare CJK, historic scripts (Gothic,
cuneiform), mathematical letters and emoji never became tokens, so `𠀀` → `𠀁` reported **no variant**. Fixed by
decoding surrogate pairs (`scalarAt`). Supplementary-plane letters are words; symbols such as emoji are
punctuation-class (folded substantively, recorded diplomatically).

**B5 — quotes, apostrophes and dashes were words.** `'`, `’` and `-` were word characters anywhere, so a leading
or closing quote or a dash became part of the word, and only a single `-` counted as punctuation. British vs American
quotation (`'Hello,'` vs `"Hello,"`), `don't` vs `don’t`, and `--` vs `—` were all *substantive* variants. Now a word
must start with a letter, digit or mark; trailing joiners are trimmed back off; any hyphen run is punctuation; and a
new `Normalizer.foldTypographicApostrophes` (on for substantive, off for diplomatic) folds `’ ‘ ʼ` to `'`.

**Effect.** No conformance golden changed (case 13, apostrophes and hyphens, is unaffected). On the full novels the
spurious variants fall: Mysterious Island −140, Journey −37, Earth to the Moon −93; readings involving a quote,
apostrophe or hyphen fall 20–36%; two of Mysterious Island's three "possible moves", anchored on quote tokens,
disappear. One existing test pinned the old behaviour (`-dash` as one word token) and was updated.

New `TokenizerUnicodeTests` fail before the fix (13 assertion failures) and pass after. ALGORITHMS §2 updated.

**State:** 241 tests green. No schema or golden change.

---

## 2026-10-03f — `implementation` + `test`: no_collate regions stay closed (release 1 review, blocker B6)

Three defects let excluded matter leak into the collation (`Tokenizer.noCollateRanges` and the tokenise loop):

1. **The two-comment form never worked.** The source documented `<!-- no_collate --> … <!-- /no_collate -->`, but the
   close pattern accepted any bare `-->`, so the opener's own `-->` closed the region at once.
2. **A nested comment ended a one-comment region.** A `<!-- page break -->` inside multi-page front matter supplied the
   first `-->`, so the rest of the front matter was collated and the body's page numbers shifted.
3. **A `---` or form-feed page break inside a region rewound the scanner.** After the jump past the region, the
   page-break check still fired for the inner marker and reset the position to that marker's end, inside the region.

**Fix.** A self-closed opener waits for the explicit end tag; the one-comment form ends at the first `-->` that does
not close a comment nested inside it; page-break markers inside a region are ignored (they count no page); and a
marker the scanner has already passed is never revisited. ALGORITHMS §2 documents both forms.

**Evidence.** New `NoCollateRegionTests` (the three reproductions, page counting, the explicit end tag and unclosed
regions, and the invariant that no token lies inside a region) fail before the fix with 19 assertion failures and
pass after. The full-novel results are byte-identical (their regions use the plain one-comment form); no golden
changed.

**State:** 246 tests green.

---

## 2026-10-03g — `implementation` + `test`: lexicon entries with accents match, and CRLF lexicon files parse (release 1 review, blocker B7)

**Defect 1.** Token keys are normalised (under the default `.substantive` normaliser, `année` → `annee`), but
`TranslationLexicon` only lower-cased its forms, so every entry containing a diacritic was silently inert. The
documented `année, year` example did nothing; so did most of golden 29's French entries. `LexiconTests` still passed
because its trilingual case's slots lined up by position and never checked that `année` actually pivoted.

**Defect 2.** `parse` split on the `"\n"` Character, which does not match the `"\r\n"` grapheme: a CRLF file was read
as one line and its groups merged, yet still produced a non-empty lexicon, so the CLI's empty-lexicon check did not
catch it.

**Fix.** The lexicon keeps its groups (in canonical order) and `normalized(with:)` re-keys them with a normaliser;
`Collation.collate` and the peer merge apply the run's normaliser on entry, so callers may write forms exactly as
spoken. `parse` splits on every newline style.

**Golden 29 re-recorded** (the one lexicon case; the French original against the Mercier and Walter translations).
With its accented entries now active, the graph pairs a French word with its lexicon equivalent in 37 of 54 possible
places (32 before), and in the French–Mercier pair French words inside a reported variant fall from 68 to 62 of 85:
`L'année ≈ year`, `marquée ≈ signalised`, `l'Amérique ≈ America`, `gouvernements ≈ Governments` and `États ≈ states`
become agreement, and large blanket substitutions split into precise ones. Some local orderings get worse where
French noun–adjective order inverts English (`officiers … militaires` vs `naval officers`): the documented
word-order limitation that sentence-level anchoring (B17) addresses.

New `LexiconNormalisationTests`: the accented-entry and CRLF tests fail before the fix; diplomatic matching and
order-independent equality are guarded too. ALGORITHMS §7d updated.

**State:** 251 tests green.
