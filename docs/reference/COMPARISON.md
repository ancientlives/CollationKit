# CollationKit vs. existing collation tools (CollateX, Juxta, …)

An honest answer to a fair question: *is this just a re-implementation of CollateX, or does it add anything?*
Short version: **it shares the same well-established conceptual skeleton (the Gothenburg model) — deliberately,
because that model is correct — but it differs in several substantive ways, two of which are genuine
departures rather than re-implementations.** This document separates "shared legacy" from "what is new here,"
so the paper can position the work accurately and not overclaim.

## What it shares with CollateX (the legacy we build on, and should credit)

These are **not** innovations; they are the field's standard approach, and CollateX/Juxta did them first. Using
them is building on legacy, and the paper must cite them as such:

- **The Gothenburg model** — the *tokenize → normalize → align → analyse → visualise* pipeline. CollationKit's
  pipeline is this model. (CollateX, Interedition.)
- **The witness / variant / apparatus / sigla vocabulary** and the substantive-vs-accidental distinction —
  from textual scholarship (Greg 1950), long predating both tools.
- **A variant graph (token-graph merge) as the N-witness data structure.** CollateX's central contribution is a
  *variant graph* — a token DAG merging all witnesses. CollationKit **adopted this same structure in B11**
  (2026-07-02): `Collation.variantGraph` builds one DAG (spine nodes, `isMove` edges, off-spine inserted nodes)
  and projects it to the apparatus. This is **inherited, not a contribution** — earlier iterations used a
  simpler base-anchored fold, and B11 closed that shortfall relative to CollateX. The remaining *difference*
  (not an advance) is that CollationKit lifts move detection onto the graph from the pairwise anchor pass rather
  than running a from-scratch multiple-sequence alignment (see "differences" and "where CollateX is ahead").
- **Progressive alignment** for N witnesses (align each witness against a growing structure) — CollateX's
  approach; CollationKit's merge is a progressive alignment onto the token-graph.
- **Normalization to separate substantives from accidentals** — standard; CollateX exposes the same idea via
  its tokenizer/normalizer hooks.

If the engine did *only* the above, the concern would be right: it would be a (smaller, less complete)
re-implementation of CollateX. It does more.

## Where it differs — and which differences are genuine contributions

### 1. Transposition as a first-class, *located* result (genuine departure)

This is the clearest novelty relative to the common tools.

- **CollateX** detects transpositions but its standard alignment is built on the variant graph + token
  matching; transposition handling has historically been limited/optional and is reported at the token level,
  not as a *located editorial event*. **Juxta** essentially does **not** model transposition — moved text
  shows as a deletion + insertion (the diff failure mode).
- **CollationKit** treats a move as a typed `transposition` variant via an explicit mechanism — unique-anchor
  spine (patience-style) + **maximum-weight increasing subsequence with a page-aware tie-break** — and then:
  - attributes the move to the block that actually **crossed a page** (not an arbitrary one of a symmetric
    swap), and flags `crossesPage`;
  - **recovers edits made *inside* a moved passage** ("they were *tired*" → "*weary*", while also moved) via
    bounded-gap bridging + a recursive inner alignment, tagging them `withinTransposition` — instead of
    emitting delete+insert churn around the move.

The page-aware attribution and the move-with-internal-edit recovery are, as far as the standard tools go, the
**original** parts. They exist because the target use case (literary editions with real pagination, passages
that move *and* are revised) demanded them.

### 2. Page/line/word **citation as a domain model** (a useful difference, not just a feature)

CollateX/Juxta locate variants by token position / character offset; presentation of page-and-line is left to
the consumer. CollationKit makes **scholarly citation a first-class part of the result**: a `PaginationModel`
(`.markers` / `.linesPerPage(N)` / `.explicit(offsets)` × `.perPage` / `.continuous`) and a `TextLocation`
that yields a printed-edition citation ("p.1 · line 2 · words 3–4", text-lines-only, single-word vs range).
This is an opinionated design the common tools don't centralize — modest, but a real difference in what the
output *is*.

### 3. In-tree, pure, value-type, zero-dependency engine (an engineering difference)

- **CollateX** is a Java/Python library (with a server mode); **Juxta** is a Java desktop app. Integrating
  either into a Swift/SwiftUI macOS app means a process/FFI/serialization boundary.
- **CollationKit** is pure Swift value types, no I/O, no dependencies — designed to drop into a Swift application
  as source, with the engine's own types feeding a UI directly. This is *not* an algorithmic contribution, but
  it is a real reason the work exists separately rather than wrapping CollateX (the question of "why not just
  use CollateX?" answered concretely).

### 4. Cost-management choices (incremental, not novel)

Adaptive anchor-length and the **banded NW** no-anchor fallback are standard sequence-alignment techniques
(banding, Hirschberg) applied here; not new in themselves, but the *combination with the anchor pass* and the
empirical lexical-diversity characterization are worth reporting.

## The N-witness merge architecture — the key architectural comparison with CollateX

This is the most important — and most reviewer-anticipating — point of comparison, so it gets its own section.
Both tools now build the same *data structure* (a token-graph / variant graph); they differ in *how they
populate it*, and that difference is the honest boundary between the two engines. Full algorithmic detail, the
trade-off table, and a staged build-out plan are in [`PAPER_NOTES.md §5.3`](PAPER_NOTES.md); the
summary for positioning:

- **CollateX — peer multiple-sequence alignment (MSA).** Each witness is aligned against the *whole growing
  variant graph* (all previously merged witnesses at once). Moves fall out of the **graph structure** (an
  out-of-order alignment to an existing node), decided with full N-witness context. All witnesses are *peers* —
  no privileged copy-text. This is the more general and more correct design; it is also where CollateX spends
  its algorithmic complexity (an A*/decision-graph search with heuristics to stay tractable).

- **CollationKit — base-privileged progressive *lift*.** `TokenGraph.build` seeds a spine from a **base**
  (copy-text) witness, then assembles the graph from **N−1 independent pairwise alignments against that fixed
  base** (`Collation.collate` per witness), *reading* each pairwise result's moves/insertions/substitutions onto
  the shared structure. The graph never re-derives an alignment with the whole set in view — it **lifts** the
  pairwise engine's decisions (incl. the page-aware, within-move, `certain`/`likely` handling) onto the DAG.

**Why the lift, and what it costs (both sides, plainly):**

- *Chosen deliberately, not by omission.* (1) It let B11 land behind the existing types with **one of 26
  conformance goldens changed** (a case-folding improvement), where a from-scratch MSA would have churned the
  corpus that *is* the correctness guarantee. (2) The engine's genuine contributions — located, page-aware
  transposition, edits-within-moves, move confidence — are implemented pairwise, so the lift **preserves them
  for free**; an MSA rewrite risks losing them. (3) Cost is predictable (N−1 bounded pairwise alignments) and
  determinism is easy. (4) For a **copy-text-centric** editorial workflow (one author's successive editions),
  an apparatus keyed to the copy-text is often exactly the scholarly convention (the apparatus criticus is
  keyed to a copy-text lemma).
- *What it gives up.* **Base sensitivity** — the apparatus is computed *through* one witness, so re-choosing the
  copy-text can shift the grouping; and **context loss** — a variant or move that is only unambiguous when *all*
  witnesses are considered jointly may be missed or downgraded to `likely` (e.g. a recurring-word move). Nested
  moves stay single-level. CollateX's peer MSA has none of these limits.

**Net, for the paper's positioning:** *CollateX's peer MSA is the more principled, more general design;
adopting its token-graph structure closed CollationKit's structural shortfall, and — since B14 (2026-07-06) —
CollationKit **ships a peer merge as its second strategy**, built along the staged §5.3 plan (alignment against
the growing consensus spine; moves + confidence from structure; cross-language anchoring — B10 — attached to
that merge as designed).* State the depth difference plainly: CollationKit's peer merge aligns against the
**linear consensus spine** — a deliberate, cheap approximation of CollateX's full-graph A*/beam alignment —
and its recurring-word moves upgrade from `likely` to `certain` structurally, while nested moves stay
single-level under both strategies. This is a strength to narrate honestly: a principled structure adopted, a
pragmatic population strategy chosen with eyes open, the depth increment *delivered* along the published plan,
and the residual (full-graph alignment) still named — not a gap papered over.

**The two strategies are complementary options, not a one-way replacement.** A subtlety worth stating in the
paper: CollationKit does **not** frame base-privileged lift as a stopgap for peer MSA — they sit at different
points on a quality/cost/base-dependence trade space, and the engine keeps **both as user-selectable strategies**
behind one seam (`Collation.variantGraph(strategy:)`; `--strategy` on the CLI). Base-privileged fits the dominant
**copy-text** workflow (one author's editions; interactive/live collation; constrained runtimes) where an
apparatus keyed to the copy-text is the convention and predictable cost matters; peer MSA fits **base-free**
material (competing translations, independent witnesses) and offline production where quality outranks speed. The
UI defaults intelligently by context (copy-text present → base-privileged; no privileged witness → peer MSA)
and exposes the choice only as an advanced affordance in plain language — never a bare toggle. Full
argument, context-map, and UI/UX policy in [`PAPER_NOTES.md §5.4`](PAPER_NOTES.md). **This also
sharpens the empirical story** (see the closing note below): because both strategies share one interchange format, the paper
can run a *controlled two-strategy ablation on the same witnesses* — isolating precisely what base-privilege
costs — which is a cleaner result than a cross-tool comparison against CollateX (that confounds strategy with a
dozen unrelated implementation differences).

## Where CollateX is currently *ahead* (honest shortfalls)

The paper should state these plainly:

- **N-witness merge depth.** Narrowed since B14 but not closed: CollationKit's peer merge aligns against the
  *linear consensus spine*, where CollateX aligns against the *whole graph* (A*/beam over the decision graph) —
  the more exhaustive form; and nested moves stay single-level in CollationKit under both strategies.
- **Maturity & validation.** CollateX is years of work, widely used, with a large real-world corpus behind it.
  CollationKit is a prototype validated on crafted + modest-scale tests.
- **Algorithm pedigree.** CollateX's alignment (e.g. its decision-graph / A* and needle variants) is more
  studied than CollationKit's anchor+NW+banding composition.
- **Ecosystem.** Tokenizer plugins, multiple output formats (TEI, GraphML, …), language bindings — CollateX
  has them; CollationKit has a JSON interchange and three renderers.

## Net assessment (for the paper's positioning)

CollationKit is **not** a copy of CollateX, but it is **built on the same legacy** and should say so. Its
defensible contributions are: (a) **transposition treated as a located, page-aware editorial event, including
recovery of edits inside a move** — the part the common tools handle weakly or not at all; (b) **citation
modelled as a first-class, configurable domain output**; and (c) an **integration-ready pure engine** for
native applications. It shares CollateX's core **token-graph** structure (adopted in B11, not claimed as a contribution).
Its honest position relative to CollateX is "a focused, embeddable collator that goes deeper on transposition and
citation, on the same variant-graph structure, while being far less battle-tested and lifting move detection
from a pairwise pass rather than a from-scratch multiple-sequence alignment."

A strong empirical section for the paper would **collate the same witness sets with both tools** (the
`--json` interchange makes this mechanical) and report where the transposition/citation handling diverges —
turning this qualitative comparison into measured results.

## References (tools)

- **CollateX** — Interedition; R. Haentjens Dekker, D. van Hulle, G. Middell, V. Neyt, J. van Zundert,
  "Computer-supported collation of modern manuscripts: CollateX and the Beckett Digital Manuscript Project,"
  *DSH/Literary & Linguistic Computing* (2015). The Gothenburg model.
- **Juxta** / **Juxta Commons** — NINES; a desktop/web collation tool (the diff-style baseline that does not
  model transposition well).
- See `PAPER_NOTES.md` §References for the algorithmic citations (Needleman–Wunsch, Hirschberg, Greg, etc.).

> Citation details to be verified against primary sources before publication.
