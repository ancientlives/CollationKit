# CollationKit — Algorithm Reference (paper notes)

A **synchronic** companion to [`DEVELOPMENT_LOG.md`](../development/DEVELOPMENT_LOG.md). The log narrates *how* the engine
came to be (chronological, with dead ends and resolved limitations); this document describes *what it is now*
— the finished algorithm, with pseudocode, complexity, parameters, and references — written to be lifted into
the methods/algorithm section of an academic paper on the collation engine.

Scope: the pure collation engine (`CollationKit`), originally prototyped as the collation engine for a native
macOS markdown editor. It is a *substantive* (lexical/structural)
collator; an optional semantic (paraphrase) layer is deferred (§11).

For a **language-agnostic** restatement of these algorithms (neutral pseudocode, invariants, determinism
rules, and a porting checklist — for re-implementing the engine in another language), see the sibling
[`ALGORITHMS.md`](ALGORITHMS.md). This document is the Swift-grounded version with complexity and rationale.

> **Section numbers.** A bare "§X" always means a section of *this* document (§1–§11 below). The engine paper
> (in preparation) has its own, separate section numbering, which these notes do not reference.

---

## 1. Problem statement

Given two or more **witnesses** (versions) of one prose work — e.g. a manuscript, typescript, proofs, and
successive editions — produce the editorial record of how the text changed: a typed, located list of
**variants** (insertion, deletion, substitution, transposition, accidental), and, across N witnesses, a
**variant graph** / **apparatus criticus**.

The defining constraint is that this is **not** a line-oriented `diff`. Line diff (Myers' algorithm over the
longest common subsequence [Myers 1986]) assumes (i) the line is the unit of change, (ii) lines are stable,
and (iii) edits are local and contiguous. Prose violates all three: it reflows (line boundaries are
meaningless), it is revised at word/phrase/sentence granularity, and passages are **reordered and moved across
pages**. The engine must therefore align at the level of meaningful textual units and report *variation*, not
line churn.

## 2. Pipeline overview

The engine instantiates the **Gothenburg model** of computational collation [Gothenburg/CollateX]: a pipeline
of *tokenize → normalize → align → analyse → (visualise)*, each stage independently testable.

```
Witness(text) ─tokenize+normalize─▶ [Token]
            ─project to comparable keys─▶ keys[]  (+ index map, + page list)
            ─align (anchors + NW + transposition)─▶ SegmentAlignment
            ─classify (coalesce, recover internal edits)─▶ [Variation]   (pairwise)
            ─token-graph merge, projected─▶ VariantGraph                  (N-witness; B11)
            ─render─▶ Apparatus | Synopsis | located Report
```

Each `Variation` carries both readings, token ranges in each witness, and a `TextLocation`
(page · line · word-span · char-range) for navigation and citation.

## 3. Stage 1 — tokenisation and normalisation

A witness is segmented into **word** and **punctuation** tokens. Each token records its surface form, a
**normalised comparison key**, its character range, and citation coordinates (page, page-relative text line,
line-relative word position — §7).

**Normalisation** is configurable and is the lever that distinguishes collation from a character diff. It
encodes the editorial distinction between **substantives** (changes in wording/meaning) and **accidentals**
(spelling, punctuation, capitalisation) [Greg 1950]:

- case folding, diacritic folding, optional punctuation dropping (punctuation tokens normalise to the empty
  key and are ignored by alignment), whitespace folding;
- a spelling-equivalence table (a seed GB↔US table is provided, e.g. *colour→color*, *harbour→harbor*), so two
  national editions are not reported as wall-to-wall substitutions.

Two presets: `.diplomatic` (record everything; fold only whitespace) and `.substantive` (default; fold
accidentals). Keeping both the surface and the normalised key per token lets alignment be aggressive while the
apparatus still shows the true reading; accidentals can be surfaced on demand as a distinct `variantSpelling`
variant (read off the *matched* positions whose surfaces differ — they were folded together for alignment).

Page boundaries and line/word numbering are governed by a `PaginationModel` (§7).

**Editorial exclusion (`no_collate` regions).** Whether a stretch of a witness is *part of the work being
collated* is an editorial judgement, not something an algorithm can infer — two editors may legitimately disagree
about whether an introduction, a translator's note, or a list of illustrations belongs in the apparatus. The
engine therefore honours an **explicit, author-controlled marker** rather than guessing: text wrapped in a
`<!-- no_collate --> … <!-- /no_collate -->` region (the minimal form is a single HTML comment,
`<!-- no_collate … -->`, closed by its own `-->`; an unclosed open runs to end-of-text) emits **no tokens** and so
never reaches the aligner. This is the *region* analogue of the page-break marker, which skips a *point*. It is not
a cosmetic convenience: on multi-witness sets whose editions carry different front/back matter, aligning that
matter produces a mass of spurious variants *and* — because it hands the move detector unanchored common words —
corrupts the alignment of the body (the failure the displacement gate, §4.6, also guards against). The excluded
text remains present in the source (a reader-facing view may still display it); it is simply outside the
collation. Placing the decision in inspectable markup, rather than in a heuristic or a learned model, is a
deliberate design commitment consistent with the engine's determinism and its scholarly audience (Appendix A).

## 4. Stage 2 — alignment

Alignment operates on the **comparable** key sequence (punctuation folded out), with an index map back to the
full token list so readings and ranges reference the real text.

### 4.1 Pairwise base aligner: Needleman–Wunsch

Global sequence alignment by **Needleman–Wunsch** [Needleman & Wunsch 1970], chosen over LCS/diff because it
*scores* substitutions and gaps: a changed word is a `substitute`, a reworded clause a *run* of substitutions —
the apparatus unit an editor wants — rather than a delete-block plus insert-block. Scoring (defaults):
`match = +2`, `mismatch = −1`, `gap = −2`. The mismatch penalty is set *above* two gaps in magnitude
(−1 > −2−2 in score terms) so a one-token change is preferred as a substitution over a delete+insert pair;
the gap penalty exceeds a single mismatch so spurious indels are not introduced where a substitution explains
the data. Traceback uses a fixed preference (diagonal > up > left) for deterministic output.

Cost: `O(n·m)` time and space for sequences of length `n, m`. In practice this runs only on the small regions
*between* anchors (§4.2), so the global cost is far lower; the unbounded case is mitigated in §6.

### 4.2 Transposition: anchors + maximum-weight increasing subsequence

NW is monotonic and cannot represent a moved passage — it reports a move as a deletion (where the text was)
plus an insertion (where it went), the diff artifact we must avoid. Moves are recovered by an **anchor** pass:

1. **Anchors.** Find n-grams (default n = 3) of comparable keys that occur **exactly once in each** witness —
   unique, unambiguous shared landmarks. This is the *patience* idea, as in patience diff [Cohen, patience
   diff]. Overlapping anchors are pruned (earliest-in-A kept) so anchor regions are disjoint.
2. **Stable spine.** Sort anchors by position in witness A; take a **maximum-weight strictly-increasing
   subsequence by position in B** — the largest set of anchors keeping the same relative order in both
   witnesses. Anchors *off* the spine are moved material. Equal weights reduce this to a longest-increasing
   subsequence; weighting (§4.3) breaks ties.
3. **Regions vs. moves.** Between consecutive spine anchors, align the gap with NW (ordinary edits). Off-spine
   anchors become `transposition` segments. Transposed token spans are **masked out** of the surrounding
   region alignment, so a move is reported once, not also as churn around it.

Adjacent moved anchors contiguous in both witnesses are **coalesced** into one block (so a moved sentence is
one transposition, not several n-gram fragments), and a block is **grown** to absorb identical neighbouring
tokens no anchor covered (e.g. a repeated final word).

### 4.3 Page-aware tie-break

A two-block swap is symmetric: the longest-increasing-subsequence criterion alone picks an arbitrary one of
the two blocks as "moved". To attribute the move to the block that is *editorially* salient — the one that
**changed page** — each anchor is weighted `2` when it is *page-stable* (same page in both witnesses) and `1`
otherwise, and the spine is the **maximum-weight** increasing subsequence (O(k²) DP over k anchors). A tie in
length is then decided in favour of keeping page-stable anchors on the spine, so the page-crossing block is the
one reported as the move (and flagged `crossesPage`). Page data is passed purely as per-token metadata; the
alignment over keys is unchanged — domain knowledge enters the *order-preservation objective*, not the matcher.

### 4.4 Recursive anchoring (a move that is also edited inside)

An edit inside a moved passage ("they were *tired*" → "*weary*") destroys every n-gram spanning the edited
word, fragmenting the passage into anchor islands; the changed head, having no surviving anchor, would leak out
as delete+insert churn. Two cooperating mechanisms recover it:

1. **Bounded-gap bridging.** When growing a moved block hits a mismatch, search up to `bridgeGap = 4` tokens
   further out for an identical *resync* pair on both sides; if found, absorb the mismatched run into the
   block. Bridging never crosses the stable spine and prefers near, balanced resyncs (penalty
   `= stepsA + stepsB + |stepsA − stepsB|`), so it bridges an *edit* rather than swallowing unrelated text.
2. **Inner alignment.** Once the block spans the whole passage, it is collated *against itself* across the two
   witnesses — a Needleman–Wunsch over the two sub-spans, since a moved block is internally order-preserving.
   The resulting ops are classified like any region but tagged `withinTransposition`, so the edit surfaces as a
   located substitution *inside the move*.

"Recursive" in the precise sense that collation is re-applied to a sub-problem it has already isolated. It is
single-level (the inner aligner is plain NW, not itself transposition-aware), so a move nested inside another
move is not recovered — vanishingly rare in prose; recorded as a limitation.

### 4.5 Single-word move recovery (displaced-reading post-pass)

The anchor pass (§4.2) requires unique **n-gram** landmarks (n ≥ 2), so a word that moves *alone* forms no
shared bigram and the monotonic NW reports it as a deletion (where it was) + an insertion (where it went) — the
diff artifact the engine exists to avoid (e.g. `the well-known author` → `the author is well known`, where
`author` *moved*). A **post-classification** pass recovers these: a base word under a deletion whose normalised
key matches a compared word under an insertion, **unique among the unmatched words on each side**, is carved
out of both and re-emitted as one `transposition`; recovered words contiguous in both witnesses coalesce into a
block. It is conservative — a genuine lone delete/insert has no counterpart, so no move is fabricated — and it
also corrected a pre-existing case where a short phrase (`at last`) moved to the front and the anchor pass had
mis-reported it as insert+delete.

Each move carries a **confidence**: `certain` when the moved word is globally unique in both witnesses (an
unambiguous displacement), `likely` when it recurs (the occurrences were paired by elimination — surfaced as a
*possible* move, not asserted). `confidence` is part of the JSON interchange (added at schema v2; current schema
is v3, §5.2) so a UI can render certain vs. tentative moves differently. *(As of the token-graph merge (B11,
§5.2), the N-witness graph reads moves off structure — an out-of-spine edge — so single-word, recurring-word, and
N-witness moves share one representation; this pairwise post-pass remains the source of single/short moves the
graph lifts. Adopting the token-graph is field-standard maturation (CollateX's structure), not a novel algorithm
— see COMPARISON.)*

#### 4.5.1 The rarity / locality gate — rejecting coincidental phantom moves

The 1:1-among-unmatched criterion is the pass's safeguard against pairing common words by proximity, but it has a
blind spot that only surfaces at novel scale, and the reasoning behind how it was closed is worth recording in
full — it is a representative example of the kind of judgement a collation engine repeatedly faces (*when is
apparent evidence of a textual event actually just an artefact of the alignment?*).

**The failure.** The 1:1 test is evaluated over the *unmatched* words only. A word that is **common** in a witness
but that the aligner matched at all-but-one of its occurrences is left unmatched exactly once — so it satisfies
"unique among the unmatched" despite being frequent in the text. The displacement gate (§4.6) then rejects only
pairings *far* from the co-linear diagonal; but two independent translations of the same work run in parallel, so
a common word's lone leftover routinely lands *near* the diagonal purely by coincidence. The pass therefore
emits a phantom transposition. This was discovered not by a test but by **hand-inspection of the interactive
variant-graph** on the Verne *De la Terre à la Lune* pair (moonvoyage vs. the 1873 Mercier & King translation,
siglum `towle`): the reader noticed "quietly" reported as *moving* ~100 lines to an unrelated sentence ("a
young Floridan, who quietly said"). The Mercier & King translation uses "quietly" five times; the base deletes
the one clause containing its single "quietly"; the two lone leftovers were paired thousands of tokens apart. Twenty-five further lone common words ("daily", "board",
"level", "present", …) exhibited the same artefact.

**The principle.** What licenses re-reading a deletion+insertion of the same word as a single *move* is
**corroboration**, and there are exactly three independent sources of it — a lone common word paired by
elimination has none:

1. **Global uniqueness.** The word occurs once on each side, so "these two are the same word, relocated" is
   unambiguous *however far* they sit apart. This is what admits a genuinely large but singular move.
2. **A multi-word block.** Several contiguous words all displacing to the same destination together is not a
   coincidence; the phrase corroborates itself. (This is why block-coalescing precedes the gate.)
3. **Locality.** A genuine move of a *repeated* word is a *short* hop — the word swaps a few positions with a
   neighbour inside the same clause. A coincidental pairing of a common word lands far off the diagonal.

**Why locality needs a scale-independent bound.** Sources (1) and (2) are structural (no threshold). Source (3)
needs a distance cutoff, and the existing proportional `moveTolerance` (§4.6) cannot serve: it scales with witness
length (≈1785 comparable tokens on this ~60k-token novel), which is correct for admitting a large singular move of
a *unique* word but far too permissive to vouch for a *common* one. The empirical justification for an **absolute**
bound is that the two populations are cleanly separated in diagonal-deviation space. Measured on the Verne pair:

| population | words | diagonal deviation (comparable tokens) |
|---|---|---|
| genuine local single-word move | "firearms" (*"ancient or modern firearms"* → *"firearms, ancient and modern"*, a within-clause reordering) | **46** |
| coincidences (lone common word, paired by elimination) | "p", "level", "board", … "quietly", "along" (26 in all) | **141 – 5536** |

The gap **46 → 141** is wide and unambiguous, so a fixed `localMoveTokens = 80` (its midpoint, ≈1.7× above the
true-positive ceiling and ≈1.8× below the coincidence floor) separates them robustly. A block is kept iff it
satisfies (1) ∨ (2) ∨ (3); only a lone, globally-common, non-local word is dropped, reverting to the plain
deletion + insertion the aligner already produced. On the full novel this eliminated all 26 coincidences, kept
the single genuine local hop as `likely`, and left all 106 `certain` moves untouched.

**Alternatives weighed (and why locality won).** Three designs were on the table:

- *(chosen)* **Locality escape.** Keep a lone non-unique word only when its hop is genuinely local. Cost: one
  scale-independent constant. Benefit: removes every coincidence *and* retains genuine short hops of repeated
  words — the highest-fidelity option, and the one the corpus evidence directly supports.
- **Blanket rejection** of *all* lone non-globally-unique words. Simpler (no constant), but it discards a real
  capability — short transpositions of repeated words (a word swapping with its neighbour), which the peer-MSA
  path relies on recovering. This trades false positives for false negatives.
- **Status quo ante / near-only.** Reject only the *far* coincidences (those admitted by widening) and keep the
  near-diagonal ones as tentative `likely` moves for a human to adjudicate. Least intervention, but at novel scale
  the near-diagonal window is ~1785 tokens, so it leaves dozens of book-spanning look-alike coincidences in the
  apparatus — it does not actually resolve the class of error.

The locality bound is deliberately isolated as a single documented constant (`Transposition.localMoveTokens`) with
its calibration recorded beside it, so a future corpus that shifts either population can retune the one number
without disturbing the surrounding logic. Note it governs *only* the non-unique single-word case; genuine large
moves of unique words pass via source (1) and are unaffected — so this cutoff is orthogonal to the §4.6 gate that
handles unique-word far coincidences. (Development record: DEVELOPMENT_LOG 2026-07-15.)

#### 4.5.2 The anchor-path distinctiveness gate — a short common phrase is not a distant move

§4.5.1 closes the coincidence class on the *displaced-word post-pass*. A **sibling** class lives on the *anchor
spine* (§4.2), and it was found the same way — by hand, on the reader's screen — one edition further on (the Verne
*De la Terre à la Lune* full-text pair, moonvoyage base vs. the Mercier & King translation, siglum `towle`). The
reader noticed *"we ought always to"* reported as a `certain` move between two entirely unrelated sentences
(*"…this is not courteous! we ought always to treat an adversary with respect"* vs. *"…I think we ought always
to put a little art in all we do"*), ~1,300 lines apart. Measuring the whole pair showed it was not one phantom but **≈90 of 107 "certain"
moves** — short common-word phrases ("I tell you", "in cast-iron", "which he would") scattered across the book.

**The failure.** A pin becomes an anchor because its n-gram is **unique in both** witnesses (§4.2). On two
independent translations a *short common-word* phrase can be unique as a joined n-gram yet occur, by coincidence,
in two unrelated sentences. The §4.6 displacement gate only rejects pairings *far* from the diagonal, and its
tolerance is length-proportional (≈1,800 comparable tokens on this ~60k-token novel), so a phrase a few hundred to
a couple of thousand tokens off the diagonal passes — a spurious move, which (as in §4.6) also corrupts the
surrounding region alignment.

**Why the §4.5.1 signals do not transfer.** Global word-uniqueness (§4.5.1 source 1) does not apply — the phrase's
words are all common. Multi-word-block corroboration (source 2) *actively backfires*: a common **phrasal template**
("we ought always to") recurs verbatim across a novel exactly as a single common word does, so "it's a phrase,
therefore self-corroborating" is precisely the wrong inference. And — the empirically decisive point — **phrase
rarity is anti-correlated with move-validity here**: the phantoms are the *rarest* phrases (unique 4-grams),
whereas a genuine long move like "the Observatory of Cambridge …" recurs 9×. Neither word-rarity, phrase-rarity,
nor the raw anchor length (uniformly ~2–3 tokens at detection time) separates the populations.

**The principle.** The one signal that *does* separate them is **distinctiveness expressed as grown-block length**.
A genuine relocated passage is a long, distinctive run (in this corpus it grows to 12–24 comparable tokens); a
coincidence is a short template (3–5). So the tolerance an off-spine block earns should **scale with its length** —
a short block must be genuinely local (the §4.5.1 bound), a long distinctive block may move much farther:

```
anchorMoveTolerance(len)   = anchorBlockBaseTolerance + distinctivenessPerToken · max(0, len − distinctivenessFreeLength)
accept a grown block B     ⟺  |B.bStart − expectedB(B.aStart)| ≤ anchorMoveTolerance(len(B))
```

with `anchorBlockBaseTolerance = 10`, `distinctivenessFreeLength = 14`, `distinctivenessPerToken = 18` (§9 — these
are the **recalibrated 2026-07-24** values; the base is a *distinct* constant, no longer the §4.5.1
`localMoveTokens = 80` — see the calibration note below for why the original 80 / 4 / 40 was replaced). Crucially
the gate runs **after block growth** (§4.2), not at pin time: the raw anchor is only ~2–3
tokens regardless of the eventual block, so the discriminating length *does not exist* until the block has absorbed
its surrounding identical run. A rejected block is not consumed — its tokens fall back into ordinary region
alignment (§4.1), the substitution/insertion/deletion they actually are.

**Calibration — RECALIBRATED 2026-07-24 across four corpora (superseding the single-corpus tuning).** The first
calibration was `base = localMoveTokens (80)`, `free = 4`, `perToken = 40`, fit on earth-to-moon alone, where the
phantoms sat *far* off the diagonal (deviation 249–1962). **It did not generalise.** Instrumenting every detected
move across all four independent-translation full-novel pairs in the corpus — Journey-to-the-Centre (Malleson↔Ward),
earth-to-moon, 20,000-Leagues, Mysterious-Island — showed that gate admitted **all 48** detected "moves", every one
a false positive. The reason is structural and is the key methodological finding: two *tightly parallel*
translations track each other page-for-page, so a coincidental short unique-in-both phrase ("off the rocks", "I
look at", "upon the sides of") lands only **5–100 tokens off the diagonal** — *inside* the flat 80-token base. The
original tuning had encoded earth-to-moon's *accidental* geometry (phantoms happened to be far); the true phantom
signature is *short and not locally corroborated at any distance*.

The recalibrated constants — `anchorBlockBaseTolerance = 10`, `distinctivenessFreeLength = 14`, `distinctivenessPerToken
= 18` — make a short block earn almost no distance credit, so it must be **genuinely local** to count; only a long
distinctive block earns tolerance to have relocated far. `anchorBlockBaseTolerance` is now a *distinct* constant, no
longer sharing `localMoveTokens` (80): the §4.5.1 single-word gate keeps its own 46 → 141 calibration untouched.

Calibration set (grown span | diagonal deviation), across the goldens + the four-pair audit:

| population | example | len | dev | earned tolerance | verdict |
|---|---|---|---|---|---|
| genuine (golden) | case 25 "author" | 1 | 1 | 10 | keep |
| genuine (golden) | case 04/05 "at last" | 2 | 2–5 | 10 | keep |
| genuine (golden) | case 19 Whitman line | 8 | 5 | 10 | keep |
| genuine (sentence-swap) | "they were tired …" ⇄ "the lamps …" | 11 | 9 | 10 | keep |
| genuine (real relocation) | Whitman *Calamus* poem-cluster (case 27) | 19 | 84 | 100 | keep |
| **false** | **"off the rocks" / "our calculation. Here …"** | 3 / 10 | 5 / 217 | 10 | **drop** |
| false | the Cambridge phantom / "we ought always to" | 14 / 4 | 249 / 1680 | 10 | drop |

**Effect (four-pair audit):** false moves **48 → 11** — Journey-to-the-Centre 8 → 2, earth-to-moon 15 → 5,
20,000-Leagues 12 → 1, Mysterious-Island 13 → 3 (a 77 % cut) — with every conformance golden and the Calamus
relocation preserved, and the two reported outliers gone. One golden (`19-whitman-transposition`) had its
single move's confidence move `certain → likely`; the move itself is unchanged.

**The irreducible residual (an honest boundary of the geometric method).** The 11 survivors are short blocks sitting
almost *on* the diagonal (dev ≤ ~9, e.g. "off the rocks" at dev 5) plus a couple of long near-diagonal blocks. A
3-token near-diagonal coincidence is **geometrically inseparable** from a genuine short local hop — and it cannot be
excluded another way: the corpus contains a legitimate 1-token move (case 25), so no minimum-length floor is
admissible; and context/co-move corroboration is ≈0 for genuine relocations too (they land among *different*
neighbours), so it does not separate the classes. This is the precise limit of a positions-only gate.

**The honest treatment — scale-relative confidence (2026-07-24b).** Since the residual cannot be *dropped*, it is
instead not *asserted*: an anchor move that passes the gate is reported `certain` only when it is either distinctive
by length (grown block > `distinctivenessFreeLength`, so its own length corroborates it) or sits in a *short*
witness (≤ `confidentMoveWitnessFloor = 4000` comparable tokens, where a short block's displacement is a meaningful
fraction of the document — a real swap). A **short block in a long parallel witness** — where the displacement is
lost in the noise of two page-for-page translations — is `likely` ("possible move"). The signal is deliberately
*scale-relative*: the same 3-token block is `certain` in a 10-token crafted swap and `likely` in a 90k-token novel.
On the four full-novel pairs this drives the *asserted* (`certain`) false-move count to **0** — "off the rocks" now
surfaces as a possible move, never a claim — while every distinctive relocation (the len-24 "same weather" passage,
Calamus) stays `certain`, and every conformance golden keeps its confidence (short witnesses, or the §4.5.1
displaced-word path which sets its own). (Development record: DEVELOPMENT_LOG 2026-07-24 / 2026-07-24b, superseding
the 2026-07-16 entry; language-neutral spec: ALGORITHMS §5.6.)

**The two gates together (§4.5.1 + §4.5.2), as a methods point.** The engine now closes the false-move class on
*both* detection paths with the *same* discipline — a move must carry corroboration, and where the proportional
displacement tolerance (§4.6) is structurally too loose, an **absolute, distinctiveness-aware** bound supplies it:
per-word for the recovery path (§4.5.1), per-grown-block for the anchor path (§4.5.2). Both were found by
**hand-inspection of the interactive viewer**, not by a failing test — evidence for §8.1's claim that the
visualisation is an evaluation instrument, not decoration — and both are pure functions of positions, lengths, and
integer deviations, so determinism and the conformance goldens are preserved.

### 4.6 Displacement gate: a co-linearity constraint on moves

Both move-detection paths above — the anchor spine (§4.2) and the displaced-word post-pass (§4.5) — decide a
move on **content** (a unique n-gram; a unique-by-elimination word) with, until this refinement, **no constraint
on how far the two occurrences sit apart**. On short, closely-related witnesses that is safe. On two *long,
independent* witnesses it is not: a rare phrase can be unique in each yet occur at unrelated positions — a
**coincidence, not a move**. This surfaced sharply on the full 20,000 Leagues pair (two independent English
translations, ~145k / ~105k tokens): the engine manufactured **~825 book-spanning "certain" transpositions** (e.g.
base "of the Aleutian" paired to a compared occurrence ~400k characters away), and those spurious anchors
**corrupted the surrounding region alignment**, so a side-by-side reading of the two texts never lined up.

The fix rests on a structural fact: **two aligned witnesses are globally co-linear** — a token a fraction *f*
through witness A sits near fraction *f* through B. A *genuine* transposition is a **local** excursion off that
diagonal (a sentence hops a few paragraphs); a coincidental match lands far from it. So a candidate move is
admitted only when its B position is within a tolerance of the diagonal expectation:

```
expectedB(i)         = round(i · |B| / |A|)
moveTolerance(|A|,|B|) = clamp( ⌊maxMoveFraction · max(|A|,|B|)⌋, minMoveTokens, maxMoveTokens )
accept a move at (aStart, bStart)  ⟺  |bStart − expectedB(aStart)| ≤ moveTolerance(|A|,|B|)
```

with `maxMoveFraction = 0.03`, `minMoveTokens = 200`, `maxMoveTokens = 6000` (§9). One `moveTolerance` is shared
by both paths so they judge distance identically. A **rejected** candidate is not masked as a move: its tokens
fall back into ordinary region alignment, i.e. the substitution / insertion / deletion they actually are — which
is the truthful reading of a coincidentally-shared phrase.

**Why the diagonal, not the spine.** The natural first attempt predicts B by interpolating the stable anchor
spine (§4.2). It fails precisely in the hard case: with two long independent witnesses the spine is itself partly
built from coincidental anchors, so a spine-relative expectation is unreliable and lets far matches look
"plausible" against neighbouring bad anchors. The **whole-document diagonal** has no such dependence — it holds no
matter how noisy the anchors are, which is exactly the property a robust gate needs. (A measurement pitfall worth
recording for anyone re-deriving this: the *raw* offset difference |Δbase − Δcompared| is **not** the deviation
when the witnesses differ in length — Walter 843k vs. Mercier 597k characters means even a perfectly co-linear
point carries |Δ| ≈ 250k characters. The meaningful quantity is deviation *from the diagonal*.)

**Effect** (full-novel pair, measured as diagonal deviation): transpositions 1,654 → 225; maximum deviation
722,845 → 28,388 characters (~4,800 tokens — a genuine local move); **zero** beyond 50k characters (was hundreds).
The side-by-side view then aligns: scrolling one column to a body variant brings its counterpart to the same
screen offset, and the two translations' chapter headings sit level. Legitimate local-move detection is unchanged
(every move/transposition regression test still passes). The gate is a pure function of positions and lengths, so
it preserves determinism and the conformance goldens.

**Expanding-window refinement (shipped).** A single fixed bound also rejects a *genuinely large but singular*
move (a relocated chapter). The displaced-word path (§4.5) therefore decides distance not by a hard cutoff but by
an **expanding-window search**: it prefers the candidate **nearest** the diagonal and reaches further out only
when the pairing is **unambiguous** — no rival candidate sharing an endpoint sits within ~2× the distance
(`ambiguityRatio = 0.5`) — up to the `maxMoveTokens` ceiling. So a lone unique word displaced far but singularly
is recovered (as a `likely` move, since it was reached by widening), while a rare word recurring at several
unrelated spots stays plain deletion + insertion. Crucially, the pairing is still restricted to words **unique
among the unmatched** on both sides: a common function word left unmatched by the aligner has no 1:1
correspondence and is never paired by mere proximity (an earlier over-eager version that dropped this restriction
manufactured ~1,400 spurious single-word "moves" out of alignment noise on the full novel — a useful negative
result). On the full-novel pair the refinement leaves the clean 225-transposition profile unchanged (211
`certain` + 14 `likely`), the 14 being real unique displacements the fixed bound had discarded. The anchor path
keeps the plain fixed gate — an anchor is unique-in-both by construction, so there is only one candidate and
nothing to search.

## 5. Stage 3 — classification and the N-witness variant graph

### 5.1 Pairwise classification

A `SegmentAlignment` (regions of `AlignOp`s + transposition segments) is coalesced into typed `Variation`s:
runs of `match` are skipped; adjacent `delete`+`insert` merge into a **substitution**; like-with-like into
**insertion**/**deletion**; transposition segments pass through carrying their inner edits. Coalescing is why a
reworded five-word clause is *one* apparatus entry, not five.

**Accidental layers (opt-in, off by default).** Two overlays add the *diplomatic* detail a substantive
apparatus folds away, without changing alignment: (1) `recordAccidentals` reports a matched pair whose
*surfaces* differ but normalise equal (colour/color, End/end) as a `variantSpelling`; (2) **`recordPunctuation`**
compares the punctuation tokens between consecutive aligned words and reports differences (comma drops, `:`→`;`,
`—`→space) as `variantSpelling` accidentals. Both are pure overlays — the substantive apparatus is byte-identical
with them off — addressing the real-edition finding that the Frankenstein 1818→1831 changes are almost entirely
punctuation (§10/B6b; conformance case 26 pins the diplomatic view beside the substantive one).

### 5.2 Variant graph (token-graph merge, B11)

For N witnesses the engine builds a **token-graph** — the field-standard CollateX structure, adopted here — and
projects it onto the apparatus-facing `VariantGraph`. All witnesses are merged into one DAG: every comparable
base token is a **spine node**; each further witness is collated to the base and its result *lifted onto the
shared structure* — agreement/substitution/deletion recorded as readings on the spine node, a **transposition**
as an out-of-spine `isMove` **edge** (so a move is a structural fact, not a per-position change), and a **pure
insertion** as an **off-spine node**. Each spine node maps *reading → set of witnesses (sigla)*; a node with
more than one reading is a point of variance (the apparatus). Readings are keyed on the **normalised** form, so
witnesses that substantively agree group into one reading rather than splitting on an accidental (e.g. `The`
and `THE` share a node) — a correctness gain over the earlier surface-keyed fold, visible in the Verne
trilingual golden.

**Provenance and what B11 subsumes.** Earlier prototype iterations built this graph by a *base-anchored
progressive fold* (readings folded onto base positions), and **B6c** added inserted nodes so pure insertions
appeared (each collected against an *insert-after anchor* — the base token it follows, −1 = before all base
text — via `Variation.insertionAnchor`, emitted as `basePosition = −1`, `insertedAfter = anchor`, reading `∅`
for omitters). **B11 (2026-07-02) replaced the hand-rolled fold with the token-graph merge**, which makes the
inserted node *structural* (an off-spine node needs no `insertionAnchor` special case) and reads moves off
edges. The projection preserves the same `GraphNode` shape and node ordering, so the wire schema stays **v3**
(negative `basePosition` + optional `insertedAfter`, retained from B6c) and `Apparatus`/`Synopsis`/
`CollationJSON` are unchanged. **Honest scope:** the merge *lifts* each witness's move detection from the
pairwise anchor pass rather than computing a from-scratch multiple-sequence alignment — so nested moves are
single-level and a recurring-word move is only as good as the pairwise pass makes it — and cross-language
anchoring is a further additive layer (B10). Adopting the token-graph closes a known shortfall relative to
CollateX; it is not claimed as a contribution of this work (see COMPARISON).

### 5.3 The merge architecture: base-privileged progressive *lift* vs. peer MSA (why, trade-offs, and how to advance it)

This subsection records — for the paper's methods/discussion sections — precisely *how* CollationKit builds its
N-witness graph, *why* it was built that way, how that choice compares to CollateX's, and *how to build out* the
more general design. It is the single most reviewer-anticipating architectural point in the engine, so it is
documented in full rather than left as a one-line caveat.

**What "lift" means, concretely.** `TokenGraph.build(witnesses:)` (in `Sources/CollationKit/TokenGraph.swift`)
does **not** compute any alignment itself. It seeds a spine from the base witness's comparable tokens, then
loops over `witnesses.dropFirst()` and for each calls the *pairwise* engine `Collation.collate(base:compared:)`.
Each pairwise result already contains typed variations — `.substitution` / `.deletion` / `.insertion` /
`.transposition`, the moves found by the anchor pass (§4.2) and the single-word displaced-reading post-pass
(§4.5), each carrying page-aware attribution (§4.3), within-move edits (§4.4), and a `certain`/`likely`
confidence. `build` then **reads those results and records them on the shared graph**: agreement/substitution/
deletion become readings on the corresponding spine node, a pure insertion becomes an off-spine node, and a
`.transposition` becomes an `isMove` **edge** spanning the moved block. So the graph is assembled from **N−1
independent pairwise alignments against a fixed base**; it never re-derives an alignment decision with the whole
witness set in view. That is the "lift."

**How CollateX differs.** CollateX performs a true **progressive multiple-sequence alignment (MSA) into the
variant graph**: each witness is aligned against the *whole growing graph* (all previously merged witnesses at
once), not against a single fixed base. Moves are then a property of the **graph structure itself** — a token
that aligns to an existing node but out of the graph's reading order is a transposition, decided with full
N-witness context. All witnesses are *peers*; there is no privileged copy-text through which the others are
seen.

**Why CollationKit lifts (the design rationale, for the paper):**
1. **Migration safety with the conformance suite as the oracle.** B11 was landed *behind the existing types*
   (`TOKEN_GRAPH_PLAN.md §4`): build the graph, project it back to the existing `VariantGraph` shape, and change
   only what genuinely improves. Reusing the mature pairwise engine meant **exactly one of 26 conformance
   goldens changed** (a case-folding *improvement*, §10). A from-scratch MSA re-derives every alignment decision
   and would have churned most goldens — an unacceptable blast radius for a single-maintainer prototype whose
   correctness guarantee *is* the golden corpus.
2. **The engine's genuine contributions are pairwise-native.** Page-aware move attribution (§4.3),
   edits-within-moves via recursive anchoring (§4.4), and `certain`/`likely` move confidence (§4.5) are
   implemented in the pairwise pass and are the paper's actual novelties. Lifting *preserves them for free*; a
   naïve MSA adoption would have to re-implement each inside the alignment core or risk losing them.
3. **Predictable, bounded cost.** N−1 pairwise alignments, each anchor-chunked and banded (§6), give a cost
   model that is easy to state and measure (§6). MSA is precisely where CollateX spends its algorithmic
   complexity (an A*/decision-graph search with heuristics); reproducing it deterministically and cheaply is a
   research task in its own right.
4. **Fit to the target workflow.** The motivating use case is one author's *successive editions* with a natural
   **copy-text** (the base): a manuscript → typescript → proofs → editions lineage. A base-privileged apparatus
   *keyed to the copy-text* is often exactly what the scholarly convention wants (the apparatus criticus is
   traditionally keyed to a copy-text lemma, §7). The peer-symmetric graph is most valuable when there is *no*
   privileged witness.

**The trade-offs (state both sides honestly):**

| Axis | CollationKit — pairwise-lifted | CollateX — MSA into the graph |
|------|--------------------------------|-------------------------------|
| Alignment context | Each witness vs. **base only** | Each witness vs. **all prior witnesses** |
| Base sensitivity | **Base-sensitive** — the apparatus can shift if the copy-text is re-chosen | Base-agnostic — witnesses are peers |
| N-witness variance shared by non-base witnesses | Seen only *through* the base; a variant two non-base witnesses share but the base lacks is folded via the base lens | Emerges directly from the merged structure |
| Recurring-word / ambiguous moves | Only as good as the pairwise pass makes them (§4.5 marks recurring ones `likely`) | Resolved with full context — generally better |
| Nested moves (a move inside a move) | Single-level (pairwise limitation, §4.4) | Can be recovered at depth |
| Cost | N−1 bounded pairwise alignments; simple to state/measure | MSA is harder; needs heuristics (A*) to stay tractable |
| Determinism (ALGORITHMS §9) | Easy — one fixed pairwise code path, reused | Harder to keep byte-stable across witness orderings |
| Risk to land / maintain | Low; small, testable core | High; rewrites the alignment core |
| Preserves page-aware / within-move / confidence work | **Yes, inherited** | Would need re-implementing inside the MSA |

**Assessment (for the paper's discussion).** *Algorithmically, CollateX's peer MSA is the more correct and more general
design*, and the paper should say so plainly. The base-privileged lift has two real weaknesses: **(a) base
sensitivity** — the apparatus is computed *through* one witness, so a different copy-text can yield a different
grouping; **(b) context loss** — a variant or move that only becomes unambiguous when *all* witnesses are
considered jointly may be missed or downgraded to `likely`. CollateX's MSA has neither. But "preferable" is
goal-relative: for a copy-text-centric editorial workflow the base-privileged apparatus is often *what is
wanted*, the cost is predictable, and — decisively for this project — the lift **preserves the located,
page-aware, within-move handling that is the engine's contribution**, which a naïve MSA rewrite could forfeit.
The honest framing is therefore: *the token-graph structure is adopted from CollateX; the move detection is
lifted from a base-privileged pairwise pass as a deliberate, well-scoped choice; the peer MSA is now a
**shipped second strategy** (B14, 2026-07-06 — see below), built exactly along the staged path this section
laid out.*

**How the peer MSA was built out (B14 — landed 2026-07-06; the steps below were the plan and are kept as the
methods narrative).** `TokenGraph.buildPeerMSA` (`Sources/CollationKit/PeerMSA.swift`) implements the
tractable form the cost note anticipated — alignment against the **linear consensus spine** — with three
engineering decisions the paper should report: (i) non-base witnesses merge in **sorted-id order**, making the
graph byte-stable under witness reordering (the determinism bar step 3 set); (ii) a consensus tie keeps the
**incumbent** reading, so a 1–1 disagreement never flips the anchor keys later witnesses align against;
(iii) the displaced-run recovery is bounded by a clause-scale window (`displacedWindow = 12`), because an
unbounded structural pairing let a common word inside genuinely-new text pair with a distant unrelated
omission (surfaced by the Verne corpus). Weakness (a) above is thereby confined to *rendering* (the apparatus
is still keyed to the copy-text lemma); weakness (b) is closed: recurring-word moves are `certain` from
structure, and partially-shared non-base insertions group (both pinned by `PeerMSATests` and the
strategy-pinned conformance cases 28/29). Spec: `ALGORITHMS.md §7c`.
1. **Progressive merge against the graph, not the base.** Replace the "collate each witness to the base" loop
   with: align witness *k* to the *current graph's spine reading* (the consensus path so far), not to witness 0.
   Concretely, extract the graph's current reading order as a token key-sequence, align the new witness's keys
   to *it* with the existing anchor+NW machinery (reused, not rewritten), and merge: matched keys join existing
   nodes; novel keys become new nodes; out-of-order matches become `isMove` edges. This removes base-privilege
   incrementally while reusing Stage-2 alignment.
2. **Structural move detection.** Once alignment is against the graph, a move is definitionally *an out-of-spine
   traversal in the merged order* — detect it on the edges (the `isMove` flag already models it), retiring the
   dependence on the pairwise `.transposition`. Carry the page-aware tie-break (§4.3) into the **spine ranking**
   (a topological order over the DAG with the page bonus), so page-crossing attribution survives the rewrite —
   this is the one contribution most at risk and must be explicitly preserved by a test.
3. **Rank/normalise the spine deterministically.** The DAG needs a canonical linear reading order for the
   apparatus/synopsis. Use a deterministic topological sort with the ALGORITHMS §9 tie-breaks (sorted node ids, page bonus)
   so the projected `VariantGraph` — and its JSON — stays byte-stable across runs *and* witness orderings (the
   determinism bar MSA makes harder; make it a property test).
4. **Confidence from structure.** Recompute `certain`/`likely` from graph evidence (how many witnesses support a
   node/edge, whether a moved run's tokens are unique in the merged graph) rather than from a single pairwise
   pass — this is where recurring-word moves that the post-pass can only call `likely` become `certain`.
5. **Land it the B11 way.** Keep `legacyVariantGraph` (the current lift) as an A/B oracle; build the peer merge
   behind a flag; flip conformance goldens only at a single switch commit and scrutinise every diff (the
   *expected* diffs are better handling of non-base-shared variance and ambiguous moves — anything else is a
   regression). Cross-language anchoring (B10) then attaches to *this* merge: bilingual/parallel-text anchors
   become additional edges seeding the alignment in step 1.

*Cost note for the implementer:* the naïve "align to the whole graph" is expensive; CollateX uses A*/beam search
over the alignment decision graph. A tractable first version can align to the **linear consensus spine** (cheap,
reuses banded NW) and accept that it is an approximation of full graph alignment — the same "exact-where-cheap,
approximate-only-where-necessary" stance the banded fallback already takes (§6). Measure it with `collate-bench`
extended to witness-count × merge-strategy.

### 5.4 Selectable merge strategy: keep base-privileged *and* peer MSA as user-choosable options

The two population strategies of §5.3 are **not** a "worse one to be replaced by a better one" — they occupy
**different points on a quality/cost/base-dependence trade space**, and the *right* one depends on the material,
the workflow, and the host. The engine therefore treats the merge strategy as a **selectable option** behind one
stable seam (`Collation.variantGraph(strategy:)`), not as a hard-wired choice. This subsection records the design
argument, because it both *justifies the current architecture* and *grounds a real research/UX contribution the
paper can make*: a controlled comparison of two collation strategies through one interchange format.

**Why keeping both is genuinely useful (the trade-offs differ by context, not by quality alone):**

| Context / material | Preferred strategy | Why |
|--------------------|--------------------|-----|
| One author's successive editions with a clear **copy-text** (MS → TS → proofs → editions) | **base-privileged lift** | The apparatus *criticus* is conventionally keyed to a copy-text lemma (§7); folding through that witness is what the scholar wants, and it is cheaper and predictable. |
| **No privileged witness** — competing translations, independent manuscripts, sibling recensions | **peer MSA** | Base-agnostic; will not distort the apparatus by viewing all witnesses through one arbitrary base. |
| **Interactive / live-editor** collation (keystroke latency, a document open in an editor) | **base-privileged lift** | Bounded, predictable cost (N−1 pairwise alignments, anchor-chunked + banded, §6); fast enough to run on edit. |
| **Batch / offline** critical-edition production where quality outranks speed | **peer MSA** | Resolves recurring-word / nested moves and non-base-shared variance with full context. |
| **Reproducibility / regression pinning** | either, but **pinned** | Determinism must hold per strategy; the conformance corpus carries the strategy as an explicit dimension (below). |
| Very large corpora / constrained runtime (WASM, mobile) | **base-privileged lift** | Lower and more predictable cost; the MSA's A*/beam search is the expensive path. |

So the choice is a function of **base-dependence** (is there a copy-text?), **quality vs. speed** (offline vs.
interactive), **host constraints** (native desktop vs. WASM/mobile), and **complexity budget**. A single engine
that can be *told* which to use serves all of these; forcing one strategy serves only some.

**The design shape — a seam now, a UI choice when the second strategy exists (two steps):**

- **Step 1 — the architectural seam (implemented; low-risk, non-breaking).** A public `CollationStrategy` enum is
  threaded through `Collation.variantGraph(strategy:)` (and the JSON/CLI entry points), defaulting to
  `.baseAnchored` (the current B11 token-graph lift), so *all existing behaviour and goldens are unchanged*. This
  makes the (formerly dead-fallback) base-anchored path a **named, first-class, selectable** strategy and gives
  the future peer MSA a place to slot in as `.peerMSA` with no further plumbing. The CLI exposes `--strategy`, so
  the strategy is scriptable and pinnable from day one — including for the ablation experiment below.
- **Step 2 — the second strategy + the UI affordance.** *Engine half done 2026-07-06:* `.peerMSA` landed (B14)
  through the *same* seam — selectable, CLI-scriptable, `contextualDefault(hasCopyText: false)` resolves to it.
  What remains is only a UI affordance (future work for any front end), which should follow the policy below: an
  **advanced/opt-in** control with a smart default, never a bare either/or.

**UI/UX policy (recorded so a UI front end doesn't mis-expose the choice):** most users neither know nor should have to
decide which alignment strategy to use, so the choice must be **defaulted intelligently by context, not dumped on
the user**:
- **Smart default from context.** If the collation set has a designated copy-text/base (the common editorial
  case), default to `.baseAnchored`. If there is *no* privileged witness (e.g. the user loaded a set of competing
  translations with no base marked), default to `.peerMSA` (available since B14; `contextualDefault` implements
  exactly this). The UI *suggests*, the user may override.
- **Plain-language framing, not jargon.** Surface it as e.g. *"Apparatus keyed to a copy-text (faster)"* vs.
  *"Peer alignment — best when witnesses have no base text (slower, more thorough)"*, under an **Advanced /
  alignment** affordance, not a prominent toggle. Never show the words "MSA" or "base-privileged lift" to an
  end user.
- **Performance-aware.** In an interactive context (live editor, large set) a front end may pin `.baseAnchored` for
  responsiveness regardless of the default, offering peer MSA as an explicit "re-collate thoroughly" action —
  the same "fast by default, thorough on request" pattern the banded fallback embodies at the algorithm level.
- **Don't gold-plate before the second strategy is real.** Exposing a UI toggle while only one strategy exists is
  a choice of one; Step 2's UI work is deliberately gated on `.peerMSA` existing (the same Stage-A/Stage-B
  discipline the CLI harness uses).

**Why this grounds the architecture (for the paper's discussion).** Making the strategy explicit and selectable does three
things for the write-up: (1) it *justifies* the base-privileged lift as a deliberate, retained option fit for the
dominant copy-text workflow — not merely a stopgap; (2) it frames the peer MSA as an *additional* capability the
architecture is shaped to accept, not a rewrite that discards prior work; and (3) it converts the "which is
better?" question from an argument into a **measurable experiment** (below), which is a stronger contribution than
asserting either strategy's superiority.

**Determinism & conformance across strategies.** The interchange (§8) and the conformance corpus (§10) treat the
strategy as an **explicit input**: a golden is pinned *per strategy* — the default, `.baseAnchored`, is what the
27 unpinned goldens encode; `.peerMSA` is pinned by strategy-tagged cases (`28-peer-shared-insertion`,
`29-verne-trilingual-peer`, whose `meta.json` carries `"strategy": "peer-msa"` and, for 29, the inline B10
lexicon). The strategy (and any lexicon) is recorded **beside** the output — in the case's `meta.json` and the
CLI run's manifest — keeping the wire format unchanged at schema v3; a consumer or port reproduces
byte-for-byte against the right target. Each strategy independently satisfies the ALGORITHMS §9 determinism rules (the
peer merge adds ALGORITHMS §9 rule 7: sorted-id merge order, incumbent-tie consensus).

**The paper contribution this unlocks — a two-strategy ablation.** With both strategies behind one seam and
one interchange format, the same witness sets can be collated *both ways* and the JSON diffed — a controlled
**ablation** isolating exactly what base-privilege costs (where the apparatus grouping shifts, where an ambiguous
or recurring-word move is resolved differently, where cross-witness variance surfaces only under the peer merge).
This is a cleaner, self-contained empirical result than a cross-tool comparison against CollateX (which confounds
strategy differences with a dozen implementation differences), and it directly evidences the §5.3 trade-off table
with measured cases rather than argument.

## 6. Cost, lexical diversity, and the bounded fallback

The anchor pass chunks the `O(n·m)` NW matrix into small inter-anchor regions **only when unique shared
n-grams exist**. Cost is therefore a function of the witness's *lexical diversity*, not merely its length:
natural prose has high local uniqueness (anchors plentiful → near-linear chunks), but pathologically repetitive
text (a tiny lexicon, refrains) yields no anchors and would fall back to a single full matrix. Two mitigations:

- **Adaptive anchoring.** If unique n-grams at the requested length are too sparse to chunk usefully (target ≈
  one anchor per 50 comparable tokens, capped at 8), retry with successively **shorter** n-grams down to a
  floor of 2; shorter grams are likelier to be unique-in-common. The longest length that clears the bar wins
  (longer anchors are more reliable); distinctive prose keeps trigrams.
- **Banded fallback.** When even bigrams find nothing, the no-anchor alignment is exact NW below a cell cap
  (~10⁶ cells) and a **banded** NW above it: only DP cells within `band` of the (length-rescaled) diagonal are
  computed, `O((n+m)·band)`. The band **auto-widens** (doubling) while the optimal traceback rides its
  *interior* edge, converging to full NW for loosely co-linear input while staying cheap when drift is small.
  On genuinely structureless input every path scores alike and the optimum hugs the edge everywhere, so the
  band is **capped** (`maxBand = 256`) and the alignment is accepted as *approximate* — there is no meaningful
  optimal alignment of near-random tokens to forfeit. Unlike a positional chunker (the earlier approach, which
  cut both witnesses at the same offset and produced seam artifacts), banding is globally optimal within the
  band and seam-free.

**Alternative.** Hirschberg's algorithm [Hirschberg 1975] gives exact full NW in `O(n·m)` time but only
`O(min(n,m))` space — it cures the *memory* cliff for a fully-arbitrary large pair, though not the time cost.
Banding is preferred because the realistic worst case is a long but loosely co-linear pair, where a small band
is both correct and far cheaper.

**Measured (BACKLOG B3; see [`../development/BENCHMARKS.md`](../development/BENCHMARKS.md)).** A deterministic
sweep (median of 5 release-build trials) confirms the analysis above: pairwise time is **near-linear in
length** for realistic anchor densities — 500 → 8000 words (16×) is ≈ 1.4 → 27.8 ms (≈ 19×), an 8k-word
lightly-edited pair in **under 30 ms** — and **lexical diversity has only a modest effect** across the
0.1–0.9 range (~30 % at fixed length) precisely because the adaptive anchor pass keeps the chunking effective
while *any* unique n-grams survive. The N-witness graph scales **~linearly in witness count** (2 → 8
witnesses ≈ 10.6 → 59.3 ms). The cost cliff is the *near-zero* anchor-density regime, which the banded
fallback caps by design; the harness floors anchor density above zero, so that point is characterised rather
than measured (an adversarial all-repetition point is the natural extension).

## 7. Locating and citing a variant

Locating a variant is a *domain* problem, not a string-offset problem: the unit of reference is dictated by how
scholars cite witnesses. Each `Variation` carries a `TextLocation` per side with:

- **page** and **line** — line numbered over *text lines only* (blank lines and page-break markers are not
  numbered, as in a printed critical edition), **page-relative** by default;
- a **word span** on the line — a *single-word* variant cites a word *position* ("p.1 · line 2 · word 3"), a
  *multi-word* variant a word *range* ("… · words 3–4"), a reading crossing lines a *line range*;
- the exact **character range** for visual highlighting.

The page/line convention is an explicit input — a `PaginationModel` — not inferred from the text:

| axis | options |
|------|---------|
| page boundaries | `.markers` (source breaks: `<!-- page break -->`, stand-alone `---`, form feed — default) · `.linesPerPage(N)` (uniform printed page of N text lines) · `.explicit(offsets)` (a real edition's page starts, by source offset) |
| line numbering | `.perPage` (reset each page — critical-edition layout) · `.continuous` (through-numbered, e.g. a poem cited line 1–1247) |

This separates *source-page* citation (right for born-digital copy) from *printed-page* citation (faithful to a
physical edition when its pagination is supplied).

## 8. Rendering (model → presentation)

The output models are decoupled from any one display format (one collation drives footnotes, a panel, exported
HTML, or a CLI dump without recomputation):

- **Apparatus** — the *apparatus criticus*: per point of variance, a *lemma* (base/copy-text reading) and the
  variant readings grouped by the *sigla* (witnesses) carrying them. Built from a pairwise result or the
  N-witness graph.
- **Synopsis** — parallel-segmentation columns: one row per base position, one column per witness, `∅` for
  omission, a variant flag where witnesses disagree.
- **Report** — a located list keyed to *position*: each change with its page·line·word citation and `crossesPage`
  / `withinTransposition` tags; the basis for "jump to" and inline highlight in a UI.

### 8.1 The interactive viewer and its visualisations (`HTMLExport`)

`collate --format html` (always written on `--out`) emits a single, self-contained, deterministic HTML page — a
pure function of the `CollationRun` — that turns the model above into an **interactive, analytical exploration
surface**. It matters to the paper for two reasons: (a) it is the concrete demonstration artifact, and (b) it
tackles a problem the numbers alone don't — *helping a reader/reviewer trust and understand a collation*. The views
(all driven from the embedded texts + base-anchored annotations + the projected variant graph; no recomputation):

| view | what it shows | data it draws on | why it helps |
|------|---------------|------------------|--------------|
| **Overview (analytical dashboard)** | confidence verdict, positional change-intensity histogram, type breakdown, witness sizes, graph shape — every element a drill-down | `summary` block + the alignment metric (below) | orients an investigation; answers *can I trust this?* and *where/what changed?* first |
| **Text (per witness)** | the witness text with every difference highlighted in place, coloured by type; a pinned detail panel | base-anchored `annotations` (UTF-16 char ranges) | read a version and see its variants *in situ* |
| **Variant graph** | a spine (agreement backbone) with readings branching where witnesses diverge and SVG arcs where a passage moved | the projected `VariantGraph` / token-graph (spine, edges, `isMove`) | the alignment *structure* at a glance; the CollateX "graph" idiom made legible + windowed |
| **Apparatus (list)** | the traditional *apparatus criticus*, one clickable line per point of variance | the N-witness graph | the scholarly print form, cross-linked to the text |
| **Parallel ⇄** | base and one witness side by side, differences aligned, anchored linked-scroll, optional line-number gutter, a colour key, hover-to-reveal (hovering a change scrolls the other column to its counterpart) | annotations (both sides) | read *across* two versions; always find the matching passage |
| **Changes ✎ (redline)** | the base rendered as track-changes into a chosen witness — struck `old → new`, deletions, `‸added` carets, moved badges — with a change-intensity heatmap | annotations (base + comp + insertion base-anchor) | *watch* the base transform; intuitive for a reader who doesn't know the texts |
| **Alignment ✓ (correspondence map)** | a dot-plot of (base position × comparison position); a clean, monotonic near-diagonal = the texts track each other | annotations' base/comp offsets | **confirm the collation aligned correctly** — the trust question, made visible |
| **Story ✍** | the prose narrative as a lede, then a section-by-section walkthrough of the whole work with inline redline examples | `narratives[]` (embedded `CollationNarrative`) + annotations | read the whole collation as an account; dip into any example |

**Alignment-confidence metric (an evaluation contribution).** The Alignment map computes, from the shared
correspondence points, the **maximum off-diagonal drift** (deviation from the co-linear diagonal, as a % of length)
and the **monotonicity** (% of consecutive points where the comparison position also advances). A sound collation
has both near-ideal; it is reported as a plain-language verdict. On the full *20,000 Leagues* pair (two independent
English translations, Walter 843,520 chars / 17,874 lines vs. Mercier 597,023 chars / 12,174 lines) the **18,074
shared points show max drift 4.8 % and 98.9 % monotonic** — a visibly clean diagonal confirming the alignment is
correct end to end. This directly answers a reviewer's "did the tool align these correctly, or jump somewhere?"
that a raw variant list cannot — and it distinguishes *genuine* text-length divergence (Walter's 5,700 extra lines)
from a mis-alignment. (Full inventory + rationale: [`VIEWER_UX_PLAN.md`](../development/VIEWER_UX_PLAN.md).)

**Narrative summary.** The same annotation data feeds a text **narrative** of the collation (`CollationNarrative`)
— a plain-prose account of how, where, and how much a witness changed (dominant kinds, where changes cluster, the
alignment verdict). It is the single source of truth for the collation's story, rendered in the console SUMMARY
section, exported as `summary.txt`, and shown in the viewer's **Story** tab (as a lede, above a section-by-section
walkthrough) — a paper-friendly, quotable characterisation of a result.

## 9. Parameters (tunables, with rationale)

| parameter | value | role / rationale |
|-----------|-------|------------------|
| `match / mismatch / gap` | `+2 / −1 / −2` | NW scoring; mismatch cheaper than two gaps ⇒ prefer substitution over delete+insert; gap dearer than one mismatch ⇒ no spurious indels. |
| anchor length `n` | `3` | trigram: distinctive enough to be unique, short enough to survive small edits nearby. |
| `minAnchorLength` | `2` | floor for adaptive retry; below 2, "unique" grams degenerate to single tokens. |
| anchor-density target | `≈1 / 50` tokens, cap `8` | when adaptive retry stops shortening n; scales with witness size. |
| `bridgeGap` | `4` | max mismatched tokens bridged when growing a moved block; the recursive-anchoring tunable (too small misses larger internal revisions; too large conflates a move with adjacent edits). |
| `fullNWCellCap` | `10⁶` | above this the no-anchor fallback switches from exact NW to banded. |
| `initialBand` / `maxBand` | `64` / `256` | banded-NW drift tolerance and the cap that keeps the cost bound real on adversarial input (above which the alignment is approximate). |
| `maxMoveFraction` | `0.03` | displacement gate (§4.6): a move may deviate from the co-linear diagonal by at most this fraction of witness length. Small because a real move is local; a cross-witness phrase coincidence lands far off-diagonal. |
| `minMoveTokens` / `maxMoveTokens` | `200` / `6000` | gate floor and ceiling (comparable tokens): the floor keeps short-input local swaps admissible; the ceiling stops a small fraction of a very long document from admitting an implausibly distant "move". |
| `localMoveTokens` | `80` | rarity/locality gate (§4.5.1): the absolute deviation within which a lone *non-unique* displaced word is kept as a local move. Sits in the Verne 46 → 141 gap. (No longer the base of the §4.5.2 tolerance — decoupled 2026-07-24.) |
| `anchorBlockBaseTolerance` | `10` | distinctiveness gate (§4.5.2) base, **recalibrated 2026-07-24** (was `localMoveTokens = 80`): the absolute deviation a *short* grown anchor block is allowed — it must be genuinely local. Cut from 80 because on tightly-parallel translations short coincidental phrases land only 5–100 off the diagonal, inside the old base. |
| `distinctivenessFreeLength` | `14` | distinctiveness gate (§4.5.2), **recalibrated 2026-07-24** (was `4`): a grown move block of ≤ this length earns only the base tolerance — no distance credit — so a short block must be local. Raised because the four-pair audit showed 3–13-token coincidences, not just 3–5. |
| `distinctivenessPerToken` | `18` | distinctiveness gate (§4.5.2), **recalibrated 2026-07-24** (was `40`): each comparable token past `distinctivenessFreeLength` buys this much extra off-diagonal tolerance (the 19-token Calamus relocation earns 10+18·5 = 100 ≥ its dev 84). |
| `confidentMoveWitnessFloor` | `4000` | scale-relative confidence (§4.5.2, 2026-07-24b): a short anchor block (≤ `distinctivenessFreeLength`) is asserted `certain` only in a witness ≤ this size (a real swap, a meaningful fraction of the document); in a longer parallel witness its small displacement is ambiguous, so it is reported `likely`. Between any crafted case (≤ ~120 tokens) and any full novel (≥ ~40k), so robust. |

These are the parameters a cost/quality sweep in the paper would vary; current values were validated on the
literary test corpus (§10) but are **not learned** — they are fixed constants chosen from the structure of the
problem, so the engine stays a deterministic, reproducible function of its input (see ALGORITHMS §9 determinism rules and
Appendix A on why the engine deliberately does *not* adapt them from data).

## 10. Evaluation corpus and method

**Crafted corpus.** Validation is by unit test on crafted witnesses, including the canonical literary
scenario — a short two-page passage as it evolves across **manuscript → typescript → proofs → GB 1st edition
→ US 1st edition → Uniform edition** — exercising: a single-word substantive revision; GB/US accidental
spelling (no substantive variants under folding, surfacing when folding is off); a sentence **moved across a
page boundary** (one cross-page transposition, no churn); a move that is also **edited inside** (one
transposition + a `withinTransposition` substitution); and a deterministic N-witness variant graph
(agreement + variant nodes). Scale/cost behaviour is tested on 2k–4k-token inputs across the diversity
spectrum, including the adversarial low-diversity case.

**Conformance corpus + real witnesses.** Beyond the crafted fixtures, a language-neutral conformance corpus
([`../conformance/`](../conformance/)) pins the engine's `--json` output as committed goldens (validated
against `collation.schema.json`). It includes **nine real, public-domain cases**
across three authors, three scripts, and pairwise + N-witness counts, written up in
[`../development/CASE_STUDY.md`](../development/CASE_STUDY.md):

| variant type / kind | witnesses | engine result |
|---------------------|-----------|---------------|
| substitution / accidental-heavy revision | *Frankenstein* 1818 vs 1831 | near-identity, **no false positives** |
| insertion / authorial revision | Whitman *Song of Myself* 1855 vs 1891 | 1 word + an 8-line stanza block as **one insertion** |
| transposition (line-scale, controlled) | Whitman, a relocated intact line | 1 **TRANSPOSITION**, not delete+insert |
| **transposition (poem/cluster, found)** | Whitman *Calamus* 1860 vs 1867 order | 1 `certain` **TRANSPOSITION** of a whole relocated poem — a real authorial move |
| substitution / **translation collation** | Verne, Mercier vs Walter English | 13 coalesced phrase-level substitutions |
| null / **French tokenisation** | Verne, two French editions | correct *no variants* (comma folded); accents + elisions handled |
| **N-witness cross-language** | Verne French + Mercier + Walter | deterministic graph, but **positional** alignment — limit of base-anchoring across languages |
| **N-witness three editions** | Whitman 1855 / 1860 / 1891 | pairwise tracks evolution exactly; apparatus now surfaces the pure insertions as inserted nodes (B6c resolved) |
| **Cyrillic** tokenisation | Pushkin *Я вас любил* (controlled variant) | variant located at line 7, word 5 — third script family |

The headline result: the engine, built and tuned on the crafted corpus, **reproduced its crafted-corpus
behaviour on unseen real text** (correct types, located, no churn) and **generalised** to translation
comparison and to three scripts — while the same exercise **bounded** that generality (cross-language
collation needs translation-aware anchoring; scriptio continua is out of scope) and surfaced the concrete
limitations now recorded in §11.

**Property-based / fuzz testing.** Beyond fixtures and the corpus, `PropertyTests` asserts **invariants** over
seeded pseudo-random inputs (deterministic, reproducible): self-collation is empty; collation is
deterministic; K non-adjacent substitutions yield ≤ K substitution variations; reported readings round-trip
to real tokens; insertion/deletion mirror under direction swap; and citations are well-formed for arbitrary
input. This last property *caught a latent crash* — an inverted highlight `Range` for an out-of-order token
span — now fixed and regression-guarded; concrete evidence that the correctness claims hold beyond the
hand-chosen cases.

The engine is **pure** (value-type input/output, no I/O, deterministic), so all of the above is verifiable in
isolation; a CLI harness (`collate` / `collate-demo`) also runs it on arbitrary user-supplied files. The suite is
in the low‑hundreds of unit tests plus the 29-case conformance corpus (9 of them the real cases above);
`swift test` reports the exact count.

## 11. Limitations and future work

- **Semantic layer (deferred; proposed — see ALGORITHM_SURVEY Part II, item 10).** Distinguishing *paraphrase* (same meaning, reworded) from literal
  substitution — an embedding-similarity or lexical-overlap layer — is specced but unbuilt; the substantive
  engine stands without it.
- **Cross-language collation (B10, resolved 2026-07-06).** Alignment anchors on shared *word-forms*; across a
  language boundary there are almost none, so the graph degraded to *positional* alignment — *surfaced by the
  trilingual Verne case*. Resolved exactly as this note prescribed — an **additive** layer, not a change to
  the within-language engine: a **`TranslationLexicon`** (bilingual equivalence groups) whose forms share one
  alignment key, applied to alignment keys ONLY, so the apparatus shows each witness's own renderings
  (`marquée | signalised | marked`); a nil lexicon is the byte-for-byte identity. Pinned by conformance case
  `29-verne-trilingual-peer`. Spec: `ALGORITHMS.md §7d`. *Residuals:* single-token noun–adjective inversions
  across the boundary are an NW tie and can pair one slot off; sentence-aligned parallel-text anchors remain
  the richer future layer for corpus-scale French↔English work.
- **Variant graph — token-graph merge (B11, resolved 2026-07-02).** `Collation.variantGraph` builds a
  **token-graph**: all witnesses merged into one DAG (spine nodes = aligned base tokens, `isMove` edges =
  transpositions, off-spine nodes = insertions), projected onto the apparatus-facing shape so the renderers are
  unchanged. This **subsumes** the earlier base-anchored fold and B6c's inserted-node special case (an insertion
  is simply an off-spine node), and keys node readings on the **normalised** form, so witnesses that
  substantively agree group into one apparatus reading instead of splitting on an accidental (case/spelling) —
  surfaced concretely on the Verne trilingual case (`The`/`THE` grouped). *Residual:* the merge lifts the
  pairwise engine's per-witness move detection onto the graph (not a from-scratch multiple-sequence alignment),
  so nested moves stay single-level and cross-language anchoring is B10.
- **Move detection — anchor-bound, with a post-pass, lifted onto the graph.** The anchor pass needs n ≥ 2-gram
  landmarks, so a lone/short move is invisible to it and would leak out as delete+insert (the diff artifact); a
  conservative **displaced-reading post-pass** (§4.5) recovers single/short moves with a `certain`/`likely`
  confidence — *surfaced by a reported `the well-known author` → `the author is well known` case*. As of
  B11 the N-witness graph reads moves off **structure** (an out-of-spine `isMove` edge), unifying single-word,
  recurring-word, and N-witness moves in one representation rather than a special pass bolted onto the fold; the
  post-pass survives as the pairwise source of single-word moves the merge then lifts. Lowering the anchor floor
  to single words was rejected (weak, brittle spine landmarks → spurious transpositions/churn); the token-graph
  is the principled answer precisely because moves are structural, not anchor-floor-dependent. **Backlog B11,
  resolved.**
- **Peer multiple-sequence alignment (B14, resolved 2026-07-06 — see §5.3).** The peer merge is now a
  **shipped, selectable strategy** (`.peerMSA`): each witness aligns against the growing graph's consensus
  spine, so non-base-shared variance groups, recurring-word moves are `certain` from structure, and B10's
  lexicon anchors attach to the merge — the staged §5.3 build-out executed as planned, landed the B11 way with
  no pre-existing golden changed and the peer dimension pinned by strategy-tagged conformance cases.
  *Residuals to state honestly:* alignment is against the **linear consensus spine** (an approximation of full
  graph alignment — CollateX's A*/beam search over the decision graph remains the more exhaustive form);
  base-privilege persists in *rendering* (the apparatus is keyed to the copy-text lemma by design); nested
  moves stay single-level; and the peer apparatus is token-granular (an unequal-length rewrite may render as
  substitution + insertion where the lift coalesced one entry).
- **Tokenisation — scriptio continua.** The space-delimited tokeniser handles alphabetic scripts
  (Latin/Greek/French/Cyrillic, verified) but **CJK** (no inter-word spaces) would collapse a line into one
  token; lift with Unicode/ICU word segmentation. *(Backlog B6. The related intra-word-hyphenation issue —
  `dun white`/`dun-white` reading as a substitution, surfaced by the Frankenstein case — was **resolved**
  2026-06-30 by folding hyphenation as an accidental: the tokeniser splits hyphenated compounds under
  substantive normalisation; see ALGORITHMS §2.)*
- **Punctuation as a recordable accidental — resolved (B6b, 2026-06-30).** Punctuation is folded before
  alignment, so a substantive apparatus never reports a punctuation-only change. The opt-in
  **`recordPunctuation`** overlay (§5.1, "Accidental layers") now compares the punctuation between aligned words and reports
  differences as `variantSpelling` accidentals — the diplomatic view — without altering alignment or the
  substantive apparatus. *Surfaced by the Frankenstein/Whitman/French-Verne cases; the Frankenstein passage's
  four punctuation changes now visible (conformance case 26).*
- **Nested moves.** Recursive anchoring is single-level (a move inside a move is not recovered). The peer-MSA
  increment (§5.3) is the natural place a deeper, structural nested-move recovery would live.
- **False-move coincidences on long independent witnesses — resolved, in three complementary layers (§4.6,
  §4.5.1, §4.5.2).** Collating two independent translations of a novel exposed, over three editions of the corpus,
  three distinct ways a coincidentally-shared reading was mis-reported as a move — each found by hand-inspecting
  the interactive viewer, each closed by a *better rule* (not more state), each a pure function of positions and
  lengths:
  1. **Unique-phrase far coincidence (displacement gate, 2026-07-08, §4.6).** A rare phrase unique in each witness
     but positionally unrelated was accepted as a `certain` move — ~825 book-spanning false transpositions that
     also corrupted the body alignment. Fixed by a **co-linearity gate** on both move paths (a move must sit within
     a diagonal-relative tolerance); max diagonal deviation 722k → 28k chars, the side-by-side view aligns.
     *Refined the same day with an **expanding-window search** (nearest-first, widen-if-unambiguous) so a genuinely
     large but singular move is still recovered as `likely`, restricted to words unique-among-unmatched.*
  2. **Lone common *word* near the diagonal (rarity/locality gate, 2026-07-15, §4.5.1).** A word common in a
     witness but left unmatched exactly once passed the displaced-word 1:1 test and landed *near* the diagonal by
     coincidence ("quietly" → an unrelated sentence). Fixed by requiring **corroboration** — global uniqueness, a
     multi-word block, or genuine locality (`localMoveTokens = 80`); removed all 26 such coincidences on the pair.
  3. **Short *phrase* anchor not truly local (distinctiveness gate, 2026-07-16; RECALIBRATED 2026-07-24, §4.5.2).**
     A short phrase unique as an n-gram *by coincidence* became an off-spine anchor and was reported as a move.
     Fixed by a **length-scaled** tolerance run *after block growth*, so a short block must be local while a long
     distinctive passage may move far. The 2026-07-16 constants were fit on one pair (earth-to-moon, where the
     phantoms sat *far* off the diagonal); a 2026-07-24 audit across **four** independent-translation pairs showed
     that tuning admitted **all 48** detected moves — the coincidences on tightly-parallel translations sit *near*
     the diagonal (5–100 tokens), inside the old flat 80-token base. Recalibrated (base 80 → 10, free 4 → 14, per 40
     → 18): false moves **48 → 11** across the four pairs, every golden and the genuine Calamus relocation kept.
     Together (2)+(3) close the class on *both* detection paths where the proportional tolerance (1) is structurally
     too loose. **Residual boundary (irreducible on geometry alone):** a short block sitting almost *on* the diagonal
     is indistinguishable from a genuine short local hop, and cannot be excluded another way — the corpus has a
     legitimate 1-token move (case 25), so no length floor is admissible, and context corroboration is ≈0 for
     genuine relocations too (they land among different neighbours). The honest treatment of the ~11 residual
     coincidences is *confidence* (surface as `likely`/"possible move"), not suppression — **implemented 2026-07-24b**
     as a scale-relative rule (`anchorMoveIsCertain`): a short block in a long parallel witness is `likely`, driving
     the *asserted* false-move count on the four pairs to **0** while distinctive relocations stay `certain`.
- **Editorial exclusion of non-collatable matter — resolved (`no_collate` regions, 2026-07-08 — see §3).**
  Edition-specific front/back matter (introductions, translator notes, illustration lists) was force-aligned into
  spurious variants and fed the move detector noise — *surfaced on the full-novel translation pair*. Resolved by
  an explicit, author-controlled `<!-- no_collate --> … <!-- /no_collate -->` marker that excludes the enclosed
  text from tokenisation (it never reaches the aligner) while leaving it in the source for display. Placing the
  decision in inspectable markup rather than a heuristic is deliberate (Appendix A).
- **Adversarial cost.** On capped-band, structureless input the fallback alignment is approximate by design.
- **Tunables are fixed constants**, not learned (§9) — a deliberate design choice for a deterministic, scholarly
  engine, argued in **Appendix A** (why more memory and cross-corpus learning are *not* the right levers here).

## References

- M. A. Needleman, C. D. Wunsch (1970). "A general method applicable to the search for similarities in the
  amino acid sequence of two proteins." *J. Mol. Biol.* 48(3):443–453. — global sequence alignment.
- T. F. Smith, M. S. Waterman (1981). "Identification of common molecular subsequences." *J. Mol. Biol.*
  147(1):195–197. — local alignment (context; the engine uses global).
- D. S. Hirschberg (1975). "A linear space algorithm for computing maximal common subsequences." *CACM*
  18(6):341–343. — linear-space alignment (the noted exact alternative, §6).
- E. W. Myers (1986). "An O(ND) difference algorithm and its variations." *Algorithmica* 1:251–266. — the
  LCS/diff baseline this work departs from.
- W. W. Greg (1950–51). "The Rationale of Copy-Text." *Studies in Bibliography* 3:19–36. — substantive vs.
  accidental; copy-text editing.
- The Gothenburg model / **CollateX** (Interedition): the tokenize → normalise → align → analyse → visualise
  pipeline and the variant-graph data model. (See CollateX documentation and R. Haentjens Dekker et al.,
  "Computer-supported collation of modern manuscripts: CollateX," *DSH/LLC* 2015.)
- B. Cohen, *patience diff* — unique-common-element anchoring (the basis for the anchor pass, §4.2).
- P. Robinson, "Collation, textual criticism, publication, and the computer" (1989) and the *Text Encoding
  Initiative* critical-apparatus guidelines — context for apparatus/parallel-segmentation rendering.

> Reference details (years, page numbers, exact CollateX citation) should be verified against primary sources
> before publication; they are recorded here as the intended bibliography, not yet copy-edited citations.

## Appendix A — Why not more memory, and why not learning across documents?

Two questions recur when a collation engine is scaled to book-length, multi-witness work: *would giving it more
memory make it more accurate?* and *should it learn from the documents it has already collated and carry that
knowledge forward?* Both are intuitively appealing and both are, for **this** engine and **this** audience, the
wrong lever. The reasoning is worth stating precisely, because it is a design commitment the rest of the system
depends on — not an omission.

### A.1 More memory does not buy accuracy

Accuracy here is set by the **algorithm's decision rules**, not by available storage. Concretely:

- **The engine is not memory-bound.** It already holds every witness and the full alignment structure in memory,
  and — thanks to patience-style anchoring (§4.2), the banded fallback (§6), and the base-anchored / peer merges
  (§5) — runs at roughly linear cost in document length and witness count (§6, §10). A full-novel pair (~100k–150k
  words) collates in seconds. Adding RAM changes no alignment decision; the binding constraints are the
  *scoring model*, the *anchor/​move criteria*, and the *tokenisation* — all algorithmic.
- **The errors we actually saw were decision errors, not capacity errors.** The defects this work fixed — the
  long-distance false transpositions, the force-aligned front matter, and the near-diagonal coincidental moves —
  were all cured by *better rules* (the co-linearity displacement gate, §4.6; the `no_collate` exclusion, §3; the
  rarity/locality and distinctiveness gates, §4.5.1–§4.5.2), each a handful of lines and *zero* extra
  state. No amount of memory would have prevented them; a bigger cache of intermediate results would merely have
  stored the wrong answer faster.
- **Where memory *does* legitimately matter, it is a rendering concern, not an accuracy one.** The interactive
  HTML viewer embeds the witnesses and the variant graph, so its payload grows with the corpus. That is a
  presentation/transport trade-off (windowing, compaction of agreement nodes), entirely separate from whether the
  underlying collation is *correct*. Optimising it never changes a reported variant.

The one memory-shaped idea that *is* worth pursuing is **local, bounded, per-run** state — the expanding-window
move search (§4.6, §11): remember the near neighbourhood of the expected position and widen only when it yields no
unambiguous match. Note what this is and isn't: it is a *search strategy within a single collation*, deterministic
and derived only from the current inputs. It is not accumulated cross-document memory. That distinction is the
whole of A.2.

### A.2 Learning across passes and documents is the wrong model for scholarly collation

A system that *learned* from the documents it had already collated — tuning its parameters, or biasing its
alignment, from a growing corpus — would trade away the properties this engine is built to guarantee, in exchange
for benefits its audience does not want.

1. **Determinism and reproducibility are foundational, not optional.** The engine is a *pure function* of its
   inputs: the same witnesses always yield the same apparatus, byte-for-byte (enforced by the conformance goldens
   and the determinism rules, ALGORITHMS §9). A learned model makes the output depend on **what the tool saw before** —
   collation order, prior corpora, model version. For a scholarly edition that is disqualifying: an editor must be
   able to state that the apparatus is exactly reproducible by anyone, from the witnesses alone, today and in ten
   years. "The result depends on the model's training history" cannot appear in a critical apparatus.

2. **Citability and auditability.** Every reported variant is traceable to an explicit rule and an exact textual
   location (§7). A reviewer can follow *why* the engine called a move a move. A cross-corpus learned bias is, by
   construction, not locally explainable — it encodes statistics of other texts. Textual scholarship requires the
   apparatus to be *defensible line by line*, which an opaque adapted weight is not.

3. **The target is the individual work, not a population.** Machine learning pays off when today's input is drawn
   from the same distribution as past inputs. Critical editing is the opposite: each witness set is *sui generis*
   — a specific author, period, language, transmission history. Knowledge that "dialogue tags often reorder"
   learned from one 19th-century novel is not a safe prior for a medieval charter or a modernist poem; applied
   automatically it would **import bias** and manufacture variants that are artefacts of other texts. Overfitting
   to a corpus is not a bug to be tuned away here; it is the failure mode.

4. **Small, adversarial, and heterogeneous data.** Even setting principle aside, the practical conditions for
   learning are absent: witness sets are few, short relative to ML corpora, and deliberately varied. There is no
   large, homogeneous training distribution to learn from without overfitting.

5. **The legitimate version of the instinct is explicit, user-owned configuration — which the engine already
   provides.** The real content behind "let it learn recurring patterns" is *let recurring editorial knowledge be
   captured and reused.* The right home for that is **inspectable input the editor controls**, not an opaque
   learned memory: the `no_collate` regions (§3), the `TranslationLexicon` for cross-language equivalence (§5,
   §11), the pagination/citation model (§7), the substantive-vs-accidental normaliser and its spelling table
   (§3), and the prose/verse scoring preset (§9). Each is declarative, versionable, diff-able, and travels with
   the edition; each keeps the engine a *pure function of (witnesses + declared configuration)*. If a pattern
   recurs across an editor's projects, the answer is a reusable **config artefact**, not a self-adapting model.

**In short.** More memory would make a correct engine no more correct, and a marginal-latency rendering concern is
the only place capacity bites. Cross-document learning would purchase a fragile, corpus-biased convenience at the
cost of the determinism, reproducibility, and auditability that make computational collation admissible as
scholarship. The engine therefore stays a deterministic function of explicit inputs, and pushes every genuinely
useful "memory" into declarative, user-owned configuration.
