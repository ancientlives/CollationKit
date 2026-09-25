# Token-graph merge (BACKLOG B11) — design & migration plan

The next major engine update, and the **single highest-leverage** one on the roadmap: replace the base-anchored
progressive fold with a **token-graph merge** — every token a node, moves as edges — so single-word,
recurring-word, and N-witness moves are handled *uniformly*, and pure insertions are anchored *by construction*
(subsuming **B6c**). Written to be self-contained, so B11 can be implemented from it directly.

> **Status: DONE (2026-07-02).** `Sources/CollationKit/TokenGraph.swift` holds the implemented merge
> (`build`) + projection (`projectedVariantGraph`); `Collation.variantGraph` routes through it (the base-anchored
> fold is retained as `legacyVariantGraph`, a fallback + A/B oracle). `TokenGraphTests` are now **live** (7
> tests). Exactly one conformance golden changed — `22-verne-trilingual-graph`, a case-folding improvement in
> the N-witness apparatus (readings key on the normalised form). `recoverDisplacedReadings` is demoted to a
> pairwise helper the merge consumes; B6c's inserted-node shape is reproduced structurally. Schema unchanged
> (v3). See `DEVELOPMENT_LOG.md` 2026-07-02. The design below is preserved as the record of intent.

---

## 0. Why this is worth doing — and why it is risky

**What it fixes (all recorded as required, not optional):**
- **The whole move class.** The anchor pass needs n ≥ 2-gram landmarks, so a lone move leaks out as
  delete+insert; a conservative post-pass (§4.5 / `recoverDisplacedReadings`) recovers *single/short* moves but
  **cannot reliably recover a move whose words recur and were mis-aligned** (it marks those `likely` or misses
  them). A token-graph handles single-word, recurring-word, and N-witness moves with one mechanism.
- **Pure insertions in the N-witness apparatus.** B6c anchored these as inserted nodes on top of the base fold;
  a token-graph makes them fall out naturally (an inserted token is just a node not on the shared path), so
  B6c's `insertionAnchor` + inserted-node special-casing becomes unnecessary machinery to retire.
- **N-witness alignment quality.** The progressive base-anchored fold aligns each witness to *witness 0*; a
  token-graph merges all witnesses into one structure (the true CollateX-style variant graph), so agreement and
  variance are computed across the whole set rather than pairwise-against-base.

**Why it is risky (do it deliberately, with the suite as the safety net):**
- It **replaces the engine core** (`Collation.variantGraph`, and how moves are classified), so the blast radius
  is the widest of any backlog item. Every conformance golden and every graph/apparatus/synopsis test is in
  scope.
- The naive alternative — *lowering the anchor floor to single words* — is explicitly rejected: single words
  are weak, brittle landmarks (function words recur; uniqueness is fragile under edits), inviting spurious
  transpositions, churn, and perturbing the page-aware tie-break. The token-graph is the principled answer
  precisely because it does **not** rely on brittle single-word spine anchors.

---

## 1. Scope & non-goals

**In scope**
- A **variant graph** built by merging all witnesses' token sequences into a single DAG of aligned tokens,
  with a designated *spine* (the reading order) and *variant* branches.
- **Move edges**: a token/run that appears out of spine order in a witness is one transposition, regardless of
  whether its words are unique, recur, or move alone.
- A **compatibility surface**: `Collation.variantGraph(witnesses:)` and the pairwise `collate(base:compared:)`
  keep their signatures and their output *types* (`VariantGraph`, `[Variation]`), so `Apparatus`, `Synopsis`,
  `Report`, `CollationJSON`, the CLI, and the app are unaffected at the call site. Where the *contents* change
  (better move/insertion handling), goldens are refreshed with a dated log entry.

**Non-goals (keep B11 bounded)**
- Cross-language anchoring (**B10**) — orthogonal; the token-graph is the substrate B10 later adds bilingual
  anchors to, not part of this item.
- Scriptio-continua tokenisation (**B6**, CJK) — independent tokeniser work.
- The semantic/paraphrase layer (a gated, deferrable later stage) — still deferred.
- New public output *shapes* beyond what move/insertion completeness requires (avoid a gratuitous schema bump;
  if one is needed, bump `schemaVersion` 3 → 4 with the same discipline as B6c).

---

## 2. Target data model (scaffold in `TokenGraph.swift`)

```
TokenGraphNode = { id: NodeID,                      // stable within a build
                   readings: map<normalizedKey, {witnesses, surface}>,  // aligned tokens across witnesses
                   isAgreement: bool }              // all witnesses share this node
TokenGraphEdge = { from: NodeID, to: NodeID,
                   witnesses: set<siglum>,          // which witnesses traverse this edge (reading order)
                   isMove: bool }                   // an out-of-spine traversal = a transposition
TokenGraph     = { nodes: [TokenGraphNode],
                   edges: [TokenGraphEdge],
                   spine: [NodeID] }                // the canonical reading order (base/copy-text path)
```

The existing `Collation.VariantGraph` (the apparatus-facing type) becomes a **projection** of `TokenGraph`
(`TokenGraph.projectedVariantGraph()`), so downstream renderers keep consuming the same `GraphNode`/`readings`
shape. Moves are read off the edges; pure insertions are nodes off the spine — no `insertionAnchor` needed.

---

## 3. Algorithm sketch (the merge)

Aligned with the Gothenburg model and CollateX's approach, adapted to this engine's determinism rules (§9):

1. **Tokenise + normalise** every witness (unchanged; reuse `Tokenizer`).
2. **Seed** the graph with the base (witness 0) token sequence as the initial spine.
3. **Progressively merge** each further witness into the graph via alignment to the *current graph* (not just
   the base): match runs join existing nodes; novel tokens become new nodes; a run that aligns to existing
   nodes but *out of spine order* records a **move edge** (the uniform move mechanism — no separate post-pass).
4. **Rank/normalise** the spine deterministically (a topological order with the page-aware tie-break preserved
   from `Transposition`, so a page-crossing move is still attributed to the block that crossed).
5. **Project** to `VariantGraph` for the apparatus/synopsis, and derive pairwise `[Variation]` (incl.
   transpositions with `confidence`) for the located report — so `certain` vs `likely` still has meaning, but
   now `certain` covers recurring-word moves the post-pass could only call `likely`.

Determinism: node ids assigned in a fixed traversal order; edges and readings emitted sorted; ties broken by
the same rules `ALGORITHMS.md §9` already fixes. A port must reproduce the graph byte-for-byte via the JSON.

---

## 4. Migration strategy (how to land it without breaking the suite)

Do it **behind the existing types**, incrementally:

1. **Scaffold (this prep step, done):** `TokenGraph.swift` with the model + a placeholder `build`/`project`
   that is not yet wired into `Collation`; `TokenGraphTests` skipped. Suite stays green (130 tests).
2. **Build the merge + projection** with the skipped tests flipped on one at a time (single-word move,
   recurring-word move, N-witness agreement, pure insertion, page-crossing move). Keep `Collation.variantGraph`
   on the *old* fold meanwhile.
3. **Switch `Collation.variantGraph` (and the move path) to the projection**, refresh conformance goldens
   (`COLLATION_RECORD=1`), and diff: the *only* expected changes are better move/insertion handling; anything
   else is a regression to investigate. Retire B6c's `insertionAnchor` special-casing if the projection makes
   it redundant (or keep the field if the projection still finds it convenient — decide at that point).
4. **Update docs** per the maintenance convention: `ALGORITHMS.md §7b` (replace the fold pseudocode),
   `PAPER_NOTES.md §5.2/§11` (flip B11 to resolved; note what `certain` now covers), `COMPARISON.md`
   (the "planned successor architecture" line becomes "adopted"), the engine paper draft (in preparation), and a dated
   `DEVELOPMENT_LOG.md` entry. Update the test count guard + README.

Each step is independently green; step 3 is the one behaviour-changing commit and is where review attention
concentrates.

---

## 5. Tests to bring from skipped → passing (the acceptance set)

In `TokenGraphTests` (and reinforced by refreshed conformance goldens):
- **Single-word move** — `the well-known author` → `the author is well known`: `author` is one transposition
  (`certain`), `is` an insertion — matching today's post-pass result, but via the graph.
- **Recurring-word move** — a moved run whose words recur elsewhere: reported as a move (`certain`), where the
  post-pass could only manage `likely`/miss. *This is the headline new capability.*
- **N-witness agreement + variance** — three witnesses merge into shared agreement nodes + variant branches;
  the projected apparatus matches the intended readings.
- **Pure insertion** — appears as an off-spine node with the carriers' reading + `∅` for omitters, *without*
  the B6c `insertionAnchor` scaffolding.
- **Page-crossing move** — the page-aware tie-break still attributes the move to the block that crossed a page.
- **Determinism** — identical graph (and projected JSON) on repeat; sorted/stable output.

---

## 6. Risks & mitigations (state honestly)

| Risk | Mitigation |
|------|-----------|
| Core rewrite regresses subtle cases | Land behind existing types; refresh goldens only at the single switch commit; diff every golden. |
| Spurious moves / churn (the reason not to lower the anchor floor) | Moves come from graph structure (out-of-spine traversal), not brittle single-word spine anchors; confidence retained. |
| Page-aware attribution lost in the rewrite | Carry the `Transposition` page-tie-break into the spine ranking; keep the page-crossing test. |
| Schema drift | Prefer projecting to the existing `VariantGraph` shape; bump `schemaVersion` only if genuinely needed, with B6c-style discipline. |

---

## 7. Definition of done

- `Collation.variantGraph` and the move classification are backed by the token-graph; `recoverDisplacedReadings`
  is retired or demoted to a fallback; B6c's insertion special-casing is retired if redundant.
- All `TokenGraphTests` pass; conformance goldens refreshed with only move/insertion-improving diffs; suite
  green with an updated count.
- Docs flipped: B11 resolved in `PAPER_NOTES §11`, `COMPARISON.md`, `BACKLOG.md`;
  `ALGORITHMS §7b` pseudocode replaced; dated `DEVELOPMENT_LOG.md` entry.
