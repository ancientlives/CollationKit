# CollationKit — backlog / next-steps

A ranked list of additions to make the engine as good, and as portable across languages/platforms, as possible. Each item is written to be usable as a self-contained task description. Each landed item gets a dated `DEVELOPMENT_LOG.md` entry (the authoritative record) and a one-line tick here.

Status: ☐ not started · ◐ in progress · ✓ done. **The DEVELOPMENT_LOG is the history**; this file is the
forward-looking list, so completed items are recorded as one line pointing at their log entry, not re-narrated.

## Open items (do these next)

- ◐ **B6 — Tokeniser: scriptio continua (CJK).** The space-delimited scanner handles alphabetic scripts
  (Latin/Greek/French/Cyrillic — verified by conformance cases 14/21/24) but **CJK has no inter-word spaces**, so a
  line collapses into one token. Lift with ICU/Unicode word segmentation. *(Intra-word hyphenation and the
  diplomatic-punctuation overlay — the other two B6 strands — are ✓; see the log 2026-06-30. This CJK strand is all
  that remains of B6.)*
- ☐ **B12 — TEI critical-apparatus I/O.** Import witnesses from, and export the apparatus to, **TEI P5**
  (`<app><lem><rdg>` parallel-segmentation) — the scholarly interchange standard DH tools consume (CollateX,
  Versioning Machine, TEI Publisher). *Output first* (render the N-witness `VariantGraph`/apparatus as TEI `<app>`
  elements — a new render model beside `Apparatus`/`Synopsis`), *input later* (parse a TEI parallel-segmentation
  file into `[Witness]`). Validate against the TEI schema. Pairs with **B8** (the HTML viewer) as the
  "scholarly export formats" track.
- ◐ **B13 Step 2 (UI half only) — expose the merge strategy in a UI.** The engine half is ✓ (B14 shipped
  `.peerMSA`; `contextualDefault(hasCopyText:)` resolves it). What remains is a user-facing affordance in a UI front
  end (future work, outside this repo): an *advanced/opt-in* control with a smart, context-aware default and
  plain-language framing — never a bare toggle. Policy in [`../reference/PAPER_NOTES.md §5.4`](../reference/PAPER_NOTES.md).
- ◐ **B9 Stage B — CLI release polish.** Stage A (scriptable `run`/`list` + interactive menu) is ✓. Stage B —
  packaging, man page, shell completions, back-navigation, overwrite-confirm — is deferred and gated on
  CollationKit v1.0. Engine work takes priority (`CLI_PLAN.md §0/§9`).

## Future ideas (proposed; not yet scheduled)

Newer suggestions, ranked by value-for-effort. Each notes *why* and any risk, so it can be picked up (or declined)
deliberately. Several arose from a 2026-07-16 review of the move-detection false-positive work (the earth-to-moon
phantom); the guiding principle from that review is that a **collation is a pure function of (witnesses + declared
configuration)** — see [`../reference/PAPER_NOTES.md` Appendix A](../reference/PAPER_NOTES.md) — so any "reference
knowledge" belongs in *inspectable, user-owned* inputs, never a learned/opaque memory.

- ☐ **B15 — Witness-profile artifact (single-pass frequency + unique-n-gram tables, exported for audit).** The
  engine already computes, per run, each witness's word-frequency map ([`Variation.globalCounts`](../../Sources/CollationKit/Variation.swift))
  and a unique-in-both n-gram index (the anchor detector, [`Transposition.uniqueCommonAnchors`](../../Sources/CollationKit/Transposition.swift)).
  Compute each witness's frequency + unique-n-gram profile **once** and (a) reuse it across all pairings of an
  N-witness / whole-author set — a clean performance win, orthogonal to correctness — and (b) **export it as an
  inspectable artifact** beside the apparatus, so a user can audit *why the engine treated a given phrase as an
  anchor* (exactly the hand-check that found the earth-to-moon phantom, built in). Low risk; the data already
  exists. **Enables B16, and pairs with the `collate-corpus` wrapper (`CORPUS_PLAN.md`).**
  - *Scope note / non-goal:* this is an **audit + performance** feature, **not** a stop-word/common-phrase
    *blocklist*. Suppressing common tokens up front would blind the aligner to real moves anchored by common words
    (e.g. the genuine local move "he continued with an amiable smile" in earth-to-moon). The engine deliberately
    keeps every token and judges moves by *position and structure*, not by a vocabulary filter — see the 2026-07-16
    log entry and the analysis that rejected the phrase-rarity approach (phrase rarity is *anti*-correlated with
    move-validity: the phantoms were the *rarest* phrases).
- ☐ **B16 — Corpus-wide commonness signal for move confidence.** Once B15 provides per-witness (and, at corpus
  scale, per-author) commonness profiles, thread a **corpus-wide** commonness value into the `certain`/`likely`
  confidence scoring, so the engine can tell "rare in this novel but a stock phrase for this author" from
  "genuinely singular." This *sharpens confidence*; it is **not** a coincidence-catcher (the 2026-07-16 review
  established that neither word- nor phrase-rarity separates a coincidental match from a real move — only the
  **geometric** signal, block-length × off-diagonal distance, does, which is what the shipped gates use). Frame it
  in the paper as a confidence refinement, and keep it a declared, inspectable input (a commonness table travelling
  with the corpus), consistent with Appendix A.2, point 5.
- ☐ **B17 — Sentence-aligned parallel-text anchor layer (B10's richer successor).** The `TranslationLexicon`
  anchors cross-language collation on word-equivalence pairs; its documented residual is single-token
  noun–adjective inversions (`phénomène inexpliqué` vs `mysterious phenomenon`) that are an NW tie. A
  **sentence-aligned parallel-text** anchor layer (align at sentence granularity first, then within-sentence) is
  the richer future option for corpus-scale French↔English work — the enabler for a fully collated Verne digital
  corpus. Attaches to the peer merge as additional seeding anchors (same shape as B10). Larger effort; defer until
  a corpus-scale translation need is concrete.
- ☐ **B18 — Deeper (structural) nested-move recovery.** Recursive anchoring (§4.4) is single-level: a move nested
  inside another move is not recovered. Vanishingly rare in prose, so low priority — but the peer-MSA merge (§5.3)
  is the natural place a structural, depth-recovering version would live if a real case ever demands it.
- ☐ **B19 — Adversarial cost benchmark point.** `collate-bench` floors anchor density above zero, so the
  near-zero-anchor (all-repetition) regime the banded fallback exists for is *characterised*, not *measured*. Add
  an explicit adversarial all-repetition point to the sweep so the cost cliff the fallback caps is a recorded
  number, closing the one gap the B3 benchmark notes call out.

## Done (chronological; full record in `DEVELOPMENT_LOG.md`)

The token-graph line — **B6c → B11 → B13 Step 1 → B14 → B10** — is complete: all witnesses merge into one DAG
with two selectable strategies (base-anchored lift / peer MSA), moves as edges, insertions as off-spine nodes,
cross-language anchoring via a lexicon. Portability (**B1/B2**) and evaluation (**B3/B4/B5**) are in place.

| item | what | landed |
|------|------|--------|
| **B1** | Conformance corpus + golden JSON (`docs/conformance/`); a port passes by reproducing goldens byte-for-byte | 2026-06-29 |
| **B2** | Formal JSON Schema (`collation.schema.json`, draft 2020-12) for the interchange | 2026-06-29 |
| **B3** | Benchmark harness with recorded numbers (`collate-bench`; `BENCHMARKS.md`) | 2026-06-30 |
| **B5** | Property-based / fuzz tests (`PropertyTests`; found+fixed a latent inverted-`Range` crash) | 2026-06-30 |
| **B6b** | Punctuation as a first-class diplomatic accidental (`recordPunctuation` overlay) | 2026-06-30 |
| **B6 (hyphenation)** | Intra-word hyphenation folded as an accidental (`splitHyphenatedWords`) | 2026-06-30 |
| **B6c** | Pure insertions anchored into the N-witness graph as inserted nodes | 2026-07-01 |
| **B9 Stage A** | Scriptable `collate run`/`list` + interactive menu over a testable `CollateCLI` core | 2026-07-01 |
| **Doc-hygiene** | Build-enforced `TestCountGuardTests` so the advertised test count can't rot (retired 2026-10: it blocked Linux and made parallel PRs conflict; the docs no longer quote exact counts) | 2026-07-01 |
| **B11** | Token-graph merge (`TokenGraph.build`) replacing the hand-rolled fold; subsumes B6c | 2026-07-02 |
| **B13 Step 1** | Selectable merge-strategy seam (`CollationStrategy` + `--strategy`; `.baseAnchored` default) | 2026-07-02 |
| **B7** | Verse/prose scoring presets (`--scoring`; prose == historical default, no golden changed) | 2026-07-03 |
| **B4** | Real-edition case study — 9 real cases, 3 authors, 3 scripts (incl. the found Calamus cluster move) | 2026-07-04 |
| **B14** | Peer-MSA merge (`.peerMSA`, `PeerMSA.swift`) behind the B13 seam; recurring-word moves `certain` from structure | 2026-07-06 |
| **B10** | Cross-language collation via `TranslationLexicon` (alignment-only pivots; nil = identity) | 2026-07-06 |
| **B8** | Interactive `collation.html` viewer + CLI run-feedback (stderr progress, capped preview) | 2026-07-07 |
| **Viewer UX** | All 5 viewer items (perf/spinner, visual variant-graph, parallel ⇄, metadata panel, tab-jump) | 2026-07-08 |
| **`no_collate`** | Editorial-exclusion regions (per-edition front/back matter emits no tokens) | 2026-07-08 |
| **Displacement gate** | Co-linearity gate on both move paths → long-independent-witness false moves fixed (1654 → 225) | 2026-07-08 |
| **Expanding-window search** | Nearest-first, widen-if-unambiguous refinement of the displaced-word gate | 2026-07-08 |
| **Rarity/locality gate (§4.5.1)** | A lone *common* word far off the diagonal is a coincidence, not a move (the "quietly" phantom); `localMoveTokens = 80` | 2026-07-15 |
| **Anchor-path distinctiveness gate (§5.6)** | A *short common-phrase* anchor unique-in-both by coincidence, far off the diagonal, is dropped; tolerance scales with grown-block length so a long distinctive passage survives (the earth-to-moon "we ought always to" phantom) | 2026-07-16 |
| **Distinctiveness gate RECALIBRATED (§4.5.2/§5.6)** | The single-corpus (earth-to-moon) tuning did not generalise — a four-pair audit (journey-to-the-centre, earth-to-moon, 20,000-leagues, mysterious-island) showed it admitted **all 48** detected moves, every one false, because on tightly-parallel translations the coincidences ("off the rocks", "I look at") sit *near* the diagonal. Base decoupled + recalibrated (80→10 / free 4→14 / per 40→18): false moves **48 → 11**, every golden + the Calamus relocation kept. Residual near-diagonal short coincidences are provably irreducible on geometry alone (honest boundary; treat as `likely`, not suppress) | 2026-07-24 |
| **Scale-relative move confidence (§4.5.2)** | The gate residual is now reported honestly: a short anchor block that passes only by near-diagonal proximity on a LONG parallel pair is `likely` ("possible move"), not asserted `certain` (`anchorMoveIsCertain`, `confidentMoveWitnessFloor = 4000`); distinctive-length blocks and short blocks in short witnesses stay `certain`. Drives *asserted* false moves on the four full-novel pairs to **0**; no move added/removed, no golden changed | 2026-07-24 |

## Recommended order

Engine first (closes real gaps, firms the paper), then harness/export. Of the open items:
**B6 (CJK)** and **B12 (TEI)** are the substantive engine/interoperability pieces; **B15** is a cheap, low-risk
enabler (audit + single-pass profiles) that unlocks **B16**; **B13 Step 2** and **B9 Stage B** are UI/polish, gated
on a UI front end and on v1.0 respectively. **B17/B18/B19** are deferrable refinements. Tier ordering, in short:

1. **B15** (witness-profile artifact — cheap, enables B16, gives the audit surface the move work motivated).
2. **B12** (TEI I/O — the biggest interoperability win) and **B6 (CJK)** (the last tokeniser gap).
3. **B16 / B17** (confidence + cross-language refinements) as the corpus scales.
4. **B13 Step 2 / B9 Stage B** (UI/CLI polish) when a UI front end / v1.0 arrive; **B18/B19** opportunistically.

> Separate track: a native (non-HTML) collation viewer is possible future work, independent of this backlog. The `collate-corpus` wrapper (collate + publish many works of one author) is specced separately in
> [`CORPUS_PLAN.md`](CORPUS_PLAN.md); B15 is its natural first building block.
