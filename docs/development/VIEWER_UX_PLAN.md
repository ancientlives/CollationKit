# Collation viewer (collation.html) — UX roadmap

The B8 interactive viewer (`Sources/CollateCLI/HTMLExport.swift`) is a single self-contained page. This tracks
the UX work requested 2026-07-07 after real use on the full *20,000 Leagues* collation (~248k words, ~21.9k
annotations, ~57k apparatus entries). Five items were raised; **all five now shipped** — the two large
visualizations (#2 visual variant-graph, #3 parallel side-by-side) plus the metadata panel landed 2026-07-08.
The specs below are kept for provenance; the "Shipped" notes on #2/#3 record what actually got built.

**Legibility pass (2026-07-09)** — five fixes from real use, all JS/CSS (payload unchanged): a persistent
colour **Key** on every text tab (distinct from the `Show` filters); the selected-variation **detail card pinned**
while only the variant list scrolls; the variant graph redrawn as an actual **spine graph** (backbone rule + node
dots + readings branching below + move arcs, with an explainer header and wider stride); an **apparatus explainer**
("how to read one `№ base ] reading SIGLA` line"); and **"what was detected" promoted to the Overview home tab**
(default landing view) with an orientation intro + per-tab navigation. See DEVELOPMENT_LOG 2026-07-09.

**Interaction pass (2026-07-09b)** — four more fixes (JS/CSS; the only payload change is nullable
`apparatus[].from/to`, the lemma's base char range): the **Overview is now a dashboard** (clickable nav cards that
jump to their tab, stat tiles, a variation bar chart, witness cards); a **graph node click opens an in-tab detail
panel below the graph** — the node's readings + a snippet of each text, with buttons to *then* open the spot in the
base/witness text or the parallel view (no auto-redirect); the **graph uses the vertical space** (spine lowered so
arcs bow up and readings hang below); and the **apparatus tab is self-contained** (its own clickable list + own
detail panel; the disconnected text-tab sidebar is hidden there). See DEVELOPMENT_LOG 2026-07-09b.

**Interaction pass (2026-07-09c)** — three more (JS/CSS only): the graph node buttons now **jump directly to the
referenced variant** (base/witness text scrolls to + highlights the covering span; parallel scrolls BOTH columns to
the annotation's spans; a brief amber flash marks the spot; a robust `afterRender()` poller makes the jump reliable
past the spinner); **clearer graph nodes** (each reading a stacked witness-chip + reading row with a type-coloured
stripe, widening on focus); and the **apparatus list now scrolls** (it was `ON_DISPLAY:'block'` — must be `'flex'`
for the flex-column scroll region to be bounded). See DEVELOPMENT_LOG 2026-07-09c.

**Changes view + fixes (2026-07-10)** — a NEW **"Changes ✎"** tab: the base rendered as a track-changes *redline*
of how it became a chosen witness (struck `old → new` substitutions, struck deletions, `‸added` insertion carets,
badged moves) with a **change-intensity heatmap** and an extent summary — the intuitive "how/where/how-much did it
change" view for a reader who doesn't know the texts. Plus four fixes: overlapping-span colour precedence (a span
now takes only its narrowest covering annotation's type class, so an insertion inside a move keeps its green);
graph-node **hover feedback**; apparatus selection now offers base+witness+parallel links & citations (not just
base); and a parallel **line-number toggle**. Payload gained a nullable `Annotation.baseAnchor` (insertion anchor
char offset, for the Changes view). See DEVELOPMENT_LOG 2026-07-10. *(2026-07-12: the Changes reading now uses
`white-space:pre-wrap` so it keeps the base text's own line/paragraph breaks instead of collapsing into one wall
of text.)*

**Alignment map + analytical Overview (2026-07-13)** — a NEW **"Alignment ✓"** tab to *confirm the collation
aligned correctly*: a correspondence dot-plot (base position × comparison position); a correct collation makes the
points hug a clean, monotonic near-diagonal, with a plain-language **verdict** ("the texts track each other
throughout — max drift X %, Y % monotonic"), tolerance band, hover-for-citation and click-to-parallel. (Diagnosed
from a report that the parallel view's line numbers showed a ~5k-line gap near the end — which is honest text-length
difference, *not* mis-alignment; the map makes the soundness visible.) The **Overview** was reworked from an
executive-style summary into an **analytical dashboard**: it leads with "Can I trust this collation?" (the alignment
verdict → the map) and "Where do the changes fall?" (a clickable positional change-intensity histogram → the Changes
view), then a "What kind of change?" interpretation + the type chart (with %) + reference tiles. No payload/engine
change. See DEVELOPMENT_LOG 2026-07-13. *(2026-07-13b: alignment-map tooltip now flips above/left near a viewport
edge so it isn't clipped at the bottom; and a `CollationNarrative` prose summary — the dashboard's story in words —
is written as `summary.txt` and leads the console output.)*

**Story tab + parallel refinements (2026-07-13c)** — a NEW **"Story ✍"** tab: the `CollationNarrative` prose
(embedded in the payload as `narratives[]`) as a lede, then a **section-by-section walkthrough** of the whole work
(12 stretches, each summarising its changes and showing inline redline examples, clickable → parallel) — the "full
story of all the changes" in the viewer. Plus two **parallel-view** refinements: hovering a highlighted change now
**auto-scrolls the opposite column** to bring the counterpart into view (guarded so it doesn't fight the linked
scroll), and a **colour key** of the highlight types present in the pair was added to the bar. See DEVELOPMENT_LOG
2026-07-13c.

## Shipped (2026-07-07) — verified in WebKit via Playwright

1. **#1 Performance + loading spinner.** `render()` used to rebuild the entire DOM (re-slice the 597k-char text
   into ~21k spans) on *every* interaction, including a single span/row click — ~2.9 s per click on the full
   novel. Fixed by splitting the render:
   - `renderChrome()` (tabs, legend, meta — cheap) / `renderView()` (the heavy text or apparatus re-slice) /
     `renderList()`.
   - `select()` now has a **fast path**: same perspective + text already rendered → it toggles the `.active`
     class on just the two affected spans (via a `spanByIdx` index built during `renderText`), updates the
     detail panel, and moves the list's active row — **no re-slice**. Measured ~100 ms handler time, 0 re-slices.
   - The genuinely heavy operations (tab/perspective switch, filter change, and any perspective *hop*) run
     behind a **spinner** (`#busy` overlay, `withSpinner()` double-rAF so it paints before the work).
   - The apparatus list is chunked + capped (`APPARATUS_CAP = 4000`) with a "showing N of M" notice, so the
     old unbounded 57k-div render can't hang.
4. **#4 List→jump switches tab.** Clicking a variant row while on the **apparatus** tab now leaves it: `select()`
   detects `state.apparatus` (or a needed perspective hop) and does one bounded re-render to the text view with
   the span active, instead of doing nothing.
5. **#5 Hide zero-count types.** The legend only offers a filter for a variation type that actually occurs in
   the current perspective (`if (!(c[t] > 0)) return`), so `spelling 0` no longer clutters a substantive
   collation. *(The richer "what was/wasn't detected" summary is folded into #2's metadata view below.)*

## Shipped 2026-07-08 (#2, #3, metadata) — verified in WebKit via Playwright on the full novel

- **Engine seam.** `Collation.variantGraphWithTokens(…)` now returns the raw `TokenGraph` alongside the
  projected `VariantGraph`; the runner keeps it on `CollationRun.tokenGraph`. (The apparatus projection drops
  the spine/edge/move structure — the visual graph needs it back.) `variantGraph` is unchanged (delegates).
- **Payload.** `HTMLExport` gained a `graph` block (`spine`, `nodes`, `edges` with `isMove`/`confidence`) and a
  run-wide `summary` block. Agreement nodes are compacted to a single `agree` surface (no per-witness sigla) —
  without that the ~145k-node novel graph dominated the file. Deterministic (sorted, nil-skipping). Pinned by
  `HTMLExportTests.testPayloadCarriesTheGraphSubstrate` / `…TheDetectionSummary` / `…MoveEdges`.
- **#2 variant graph** — columnar "score" layout, windowed (only ~113 columns built near the viewport on the
  full novel), inserted nodes slotted after their anchor column, move edges as SVG arcs (dashed for `likely`),
  an overview minimap, and click-to-cross-link into the base text. Tab: **variant graph**.
- **#3 parallel ⇄** — base ⇄ one witness (selector), variation highlighted on both sides in matching type
  colours, ∅ gap markers, linked scroll, hover flags the counterpart. Tab: **parallel ⇄**.
- **Metadata / "what was detected"** — run-wide type counts (a `0` reads *"checked — none found"*), witness
  sizes, merged-graph shape, run settings. Tab: **what was detected**. This is the reassurance the tail of #5
  called for. Full-novel perf (WebKit): load 2.6 s, graph switch ~0.5 s, info ~0.2 s, parallel ~3.4 s (behind
  the spinner; see the note under #3 — paragraph windowing is the remaining lever if it needs to be faster).

The original specs follow.

### #2 — A visual variant-graph view (replace the apparatus text-list)

**Problem.** The `apparatus (variant graph)` tab is a flat text list (`lemma] reading sigla; …`). It is the
printed apparatus criticus in HTML — not a *visualization*, and unintuitive for seeing structure. On a full
novel it is also tens of thousands of rows.

**Goal.** Show the collation as an actual graph/column structure: the shared **spine** (agreement) as a
backbone, with **variant nodes** branching where witnesses disagree, and **move edges** drawn where a witness
reordered. This is exactly what the engine already computes — `run.graph` is a `TokenGraph` projected to a
`VariantGraph` (spine nodes + off-spine inserted nodes + `isMove` edges). The data is there; only the *rendering*
is a list.

**Data available now** (see `HTMLExport.payload`): `apparatus[]` = `{position, lemma, type, variants:[{reading,
sigla}]}`. **Missing for a real graph:** the spine/edge structure (which nodes are agreement vs variant, and the
move edges with from/to). Add a `graph` block to the payload from `run.graph` directly:
`{ nodes: [{id, isAgreement, isInserted, readings:[{reading, sigla}]}], spine: [id…], edges: [{from, to, isMove,
witnesses, confidence}] }`. `TokenGraph` already carries `spine`, `edges` (with `isMove`/`confidence`), and
`insertedAnchorByNodeID` — surface those. Keep it deterministic (sorted).

**Rendering approach (self-contained, no libs — CSP blocks CDNs):**
- A **columnar "score" layout** is the most legible and cheapest: walk the spine left→right; each spine position
  is a column; agreement columns render compact/greyed, variant columns render the stacked readings (one row per
  witness reading, sigla-labelled, type-coloured). This is the CollateX "alignment table" idiom and reads far
  better than a list. Virtualise/window it (render only the columns near the viewport) since a novel has tens of
  thousands — reuse the `APPARATUS_CAP`/chunking pattern, or a scroll-driven window.
- **Move edges** drawn as SVG arcs over the columns (inline `<svg>` overlay; from-column → to-column), coloured
  as `moved`, dashed for `likely`. Only draw edges for the visible window.
- Clicking a variant column selects it and cross-links to the text view (reuse `select()`/`spanByIdx`).
- A lightweight **overview strip** (a full-width minimap of where variation clusters) helps navigate a novel.

**Also here — the metadata / "what was detected" panel (the tail of #5).** A small summary view: per type total
counts across the whole run (not just the current perspective), which types had **zero** matches (so the user
knows *spelling was checked and found nothing*, vs. *not checked*), the strategy/scoring/lexicon settings, the
witness list with sizes, and the graph shape (spine length, variant nodes, inserted nodes, move edges). This
turns "why is there no spelling filter?" into an explicit, reassuring statement. Cheap; do it alongside #2 or
first.

### #3 — Parallel side-by-side view (base ⇄ one witness)

**Problem.** Today you flip *perspective* (one text at a time). There's no way to see two texts **next to each
other** and read how they relate — what moved, what was deleted base→witness, what was substituted.

**Goal.** A two-column view: base on the left, a chosen witness on the right, variation highlighted on **both**
sides in matching colours, with the relationship legible:
- **Substitution:** both sides highlighted, same colour, hovering one flags the other.
- **Deletion (in base, absent in witness):** base span marked; the witness side shows a `∅`/gap marker at the
  aligned position.
- **Insertion:** mirror of deletion.
- **Move:** the moved block marked in both columns at its two positions; its base and witness locations linked.

**Interaction detail (deferred — decide when building):** start with the **simpler "columns + matching
highlights + linked scroll/hover"**; only add **drawn connector lines/arrows** between counterpart spans (moves
especially) if they read well and stay performant on a novel. Connectors are an inline-SVG overlay between the
columns; they must be windowed like #2's edges.

**Data available now.** `annotations[]` already carry both sides (`base:{from,to,cite,reading}` /
`comp:{…}`) for base↔witness — this is exactly the alignment the parallel view needs. For N>2, pick one witness
(a selector); the base-anchored `basePairs` already give base↔each-witness. No new engine work required for the
2-witness case; the payload has enough. (Alignment *between two non-base* witnesses would need a pair the runner
doesn't currently compute — out of scope for the first version.)

**Performance.** Reuse the shipped patterns: build once, window the rendered region, no full rebuild on
selection, spinner on the initial slice. Two 597k-char columns is heavier than one — virtualising by
paragraph/line is likely necessary for the full novel.

## Constraints (apply to both)

- **Self-contained only.** Strict CSP: no CDN scripts, no external fonts/styles/images, no fetch. Everything
  inline. (This is why the plan avoids d3/graph libraries.)
- **Deterministic + pure.** `HTMLExport.html` stays a pure function of `CollationRun` (snapshot/`HTMLExportTests`
  cover payload shape, escaping, determinism). Any new payload block must have sorted keys and no timestamps.
- **UTF-16 offsets.** `charRange` offsets == JS string indexing; keep using them for spans.
- **Verify in a browser.** Unit tests can't exercise the JS. Use a Playwright + WebKit harness
  against the **full-novel** page — the small fixture hides perf
  regressions.
