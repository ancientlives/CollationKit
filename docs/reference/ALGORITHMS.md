# Portable collation algorithms — language-agnostic specification

A **language-neutral** specification of the collation engine's algorithms, written so they can be re-implemented
in any language (Rust, TypeScript/JS, Python, C++, Go, …) for any text-based application — independent of the
Swift prototype (`CollationKit`) and of the native macOS markdown editor it was originally prototyped for.

This document defines *what* each stage computes (data structures, pseudocode, invariants, parameters), not
*how Swift does it*. The Swift source is one reference implementation; [`PAPER_NOTES.md`](PAPER_NOTES.md) is the
Swift-grounded narrative; this file is the **port spec**. A port that follows it — and the determinism rules in
§9 — will produce output that matches the reference implementation's JSON (see [the JSON
schema](#8-json-interchange-the-portability-contract)), which is the recommended cross-implementation test.

Pseudocode is in a neutral imperative style; `//` are comments. Indices are 0-based; ranges are half-open
`[lo, hi)`.

---

## 0. Data structures (the portable model)

```
Witness        = { id: string, text: string }

Token          = { surface:    string      // text as written ("colour")
                   normalized:  string      // comparison key ("color"); "" ⇒ ignored by alignment
                   kind:        WORD | PUNCT
                   charFrom, charTo: int     // half-open source offsets (for highlighting)
                   page:        int          // 0-based
                   line:        int          // 0-based, text-lines-only, per the pagination model
                   wordOnLine:  int }         // 0-based position within its line

AlignOp        = MATCH(a,b) | SUBSTITUTE(a,b) | DELETE(a) | INSERT(b)   // a,b are token indices

VariationType  = INSERTION | DELETION | SUBSTITUTION | TRANSPOSITION | VARIANT_SPELLING

TextLocation   = { page, line, endLine, firstWord, lastWord: int; charFrom, charTo: int }

Variation      = { type: VariationType
                   baseReading, comparedReading: string
                   baseTokens, comparedTokens: [lo,hi) | null     // token-index ranges
                   baseLocation, comparedLocation: TextLocation | null
                   crossesPage: bool          // baseLocation.page != comparedLocation.page
                   withinTransposition: bool   // edit found inside a moved block
                   insertionAnchor: int | null } // for a PURE insertion: base index it follows (-1 = before all)

GraphNode      = { basePosition: int,           // base token index, or -1 for an inserted node (B6c)
                   insertedAfter: int | null,   // for an inserted node: base index it follows (-1 = before all)
                   readings: map<string, set<string>> }  // reading → witness sigla ("∅" = omitted)
VariantGraph   = { baseID: string, nodes: [GraphNode] }
```

## 1. Pipeline

```
collate(base, compared, params):
    A = tokenize(base.text, params)            // §2
    B = tokenize(compared.text, params)
    (aKeys, aMap, aPages) = comparable(A)       // keep only normalized != ""; aMap[i] → full-token index
    (bKeys, bMap, bPages) = comparable(B)
    segments = align(aKeys, bKeys, aPages, bPages, params)   // §3–5
    variations = classify(segments, A, B, aMap, bMap, params)  // §6
    return { base.id, compared.id, variations }

variantGraph(witnesses, params):                // §7 (N witnesses)
```

## 2. Tokenisation & normalisation

Segment `text` into WORD and PUNCT tokens; assign citation coordinates per the pagination model.

- **Word** = a maximal run of letters/digits and *intra-word* `'` `’` `-`. **Punct** = a maximal run of other
  non-space characters. Whitespace separates; it is not a token.
- **Hyphen splitting** (configurable; ON for substantive collation, OFF for a diplomatic/exact comparison):
  when on, a word run containing an **interior** hyphen (one not at the run's start or end) is split into its
  component WORD tokens, each hyphen run emitted as a separate PUNCT token (foldable). So `mother-in-law`
  → WORD `mother`, PUNCT `-`, WORD `in`, PUNCT `-`, WORD `law`, and `dun-white` tokenises identically to
  `dun white`. This treats **hyphenation as an accidental of word-division** so the two forms collate as the
  same reading rather than as a 2-tokens-vs-1-token substitution (the rule is a port-visible behaviour — a
  port MUST split the same way to match goldens). A leading/trailing hyphen does **not** split (it abuts the
  word edge); apostrophes never split.
  *Orthogonality (important):* splitting folds only the **orthographic** axis (a compound written with a
  hyphen vs. a space). It is independent of the **substantive** axis (whether the words are reordered or
  rephrased). So `the well-known author` vs `the well known author` (same order) → **no variant**; but
  `the well-known author` vs `the author is well known` → a **real** variant (the words moved / `is` was
  added), reported as insertion/deletion — the hyphen fold does not, and must not, hide a genuine rephrase. A
  word change *inside* the compound (`well-known`→`widely-known`) remains a substitution.
- **normalize(word)** (configurable — the substantive/accidental lever):
  `lowercase? → strip-diacritics? → apply spelling-equivalents (e.g. colour→color)`. PUNCT tokens get
  `normalized = ""` when punctuation is dropped (then ignored by alignment). *Even when dropped, the PUNCT
  token's surface is retained* so the optional **diplomatic punctuation overlay** (§6.2) can compare it.
- **Pagination & citation coordinates** (§ the pagination model):
  - `page` increments at a page boundary (see model below);
  - `line` counts **text lines only** — blank lines and page-break markers are *not* numbered — and resets per
    page (`.perPage`) or runs continuously (`.continuous`); advance `line` lazily on the *first token of a
    line* so a trailing blank never consumes a number;
  - `wordOnLine` resets each new text line.

Pagination model (an explicit input, not inferred):

```
pages       = MARKERS            // break at <!-- page break -->, stand-alone ---, form-feed (skip their text)
            | LINES_PER_PAGE(n)  // new page every n text lines
            | EXPLICIT([offset]) // pages begin at these source offsets
lineNumber  = PER_PAGE | CONTINUOUS
```

**Invariant:** page-break marker characters never become tokens.

- **No-collate regions (editorial exclusion).** Matter that differs per edition and must **not** be aligned —
  front/back matter, a translator's note, a list of illustrations — is wrapped by the editor in a region that
  emits **no tokens at all**, so it never reaches the aligner. This is the *region* analogue of the page-break
  marker (which skips a *point*). Without it, two witnesses' unrelated front matter is force-aligned into a pile
  of junk variants and — worse — feeds the move detector unanchored common words to mis-match across the whole
  document (see §5.6, the defect this prevents at the source).

  ```
  OPEN  = <!-- no_collate            (case-insensitive; `no-collate` also accepted)
  CLOSE = the comment's own -->      (a bare --> ends it)  |  <!-- /no_collate -->  (explicit end tag)
  an OPEN with no CLOSE runs to end-of-text ("everything after here is back matter")
  ```

  Compute the excluded character ranges (each OPEN paired with the next CLOSE at/after it), then during the walk
  skip any position inside one. The excluded text is still *present in the witness* (a viewer may display it); it
  simply produces no tokens. **Invariant:** no token's range intersects a no-collate region. Determinism: regions
  are found by a fixed scan, marker-inclusive, in ascending order.

## 3. Pairwise alignment — Needleman–Wunsch

Global alignment of two key sequences. Scoring (defaults): `MATCH=+2, MISMATCH=-1, GAP=-2`. (Rationale:
`MISMATCH > 2·GAP` ⇒ a one-token change is one SUBSTITUTE, not DELETE+INSERT; `GAP < MISMATCH` ⇒ no spurious
indels.)

```
needlemanWunsch(a, b):
    n=|a|, m=|b|
    if n==0: return [INSERT(j) for j in 0..m)]
    if m==0: return [DELETE(i) for i in 0..n)]
    dp = (n+1)×(m+1) matrix
    for i in 0..n: dp[i][0] = i·GAP
    for j in 0..m: dp[0][j] = j·GAP
    for i in 1..n: for j in 1..m:
        s    = (a[i-1]==b[j-1]) ? MATCH : MISMATCH
        dp[i][j] = max(dp[i-1][j-1]+s, dp[i-1][j]+GAP, dp[i][j-1]+GAP)
    // traceback from (n,m) with FIXED preference: diagonal > up(delete) > left(insert)  ← determinism
    return ops (reversed)
```

Cost `O(n·m)`; in the full engine it runs only on small inter-anchor regions (§5).

## 4. Banded NW (bounded fallback for low-diversity input)

When no anchors exist (§5) and `n·m` exceeds a cell cap, compute only DP cells within `band` of the
length-rescaled diagonal — `O((n+m)·band)`. Globally optimal while the true path stays inside the band.

```
banded(a, b, band):                              // returns (ops, hitEdge)
    w = max(band, |n-m| + 1)
    lo(i) = max(0, floor(i·m/n) - w);  hi(i) = min(m, floor(i·m/n) + w)
    fill dp only for j in [lo(i), hi(i)], cells outside = -inf
    traceback as in §3; set hitEdge if an INTERIOR row's path sits on lo(i) or hi(i)
                                                  // corners (0,0),(n,m) are forced endpoints — not "edge"

bandedAutoWidening(a, b, initialBand, maxBand):
    band = initialBand
    loop: (ops, hitEdge) = banded(a,b,band)
          if not hitEdge or band >= maxBand: return ops
          band = min(band·2, maxBand)            // cap keeps the bound real on structureless input (approx.)
```

Alternative: **Hirschberg** — exact full NW in `O(n·m)` time, `O(min(n,m))` space — if exactness on a
fully-arbitrary pair matters more than the band cap.

## 5. Transposition-aware alignment (the non-diff core)

NW is monotonic and cannot represent a moved passage. Recover moves with an anchor pass.

```
align(a, b, aPages, bPages, params):
    anchors = adaptiveAnchors(a, b, params.anchorLen)        // §5.1
    if anchors empty: return [ REGION( boundedNW(a,b) ) ]    // §4

    byA = anchors sorted by aStart
    weights[k] = (aPages[byA[k].aStart] == bPages[byA[k].bStart]) ? 2 : 1   // page-aware (§5.3)
    spine = maxWeightIncreasingByB(byA, weights)             // §5.2 — the in-order backbone
    moved = byA not in spine

    transpositions = coalesce(moved)                         // merge anchors contiguous in BOTH witnesses
    transpositions = grow(transpositions, a, b, spine)       // §5.4 — identical-neighbour + bounded bridge
    mark consumed = all tokens in transposition ranges (both sides)

    segments = []
    for t in transpositions:
        innerOps = needlemanWunsch(a[t.aRange], b[t.bRange])  // §5.5 recursive anchoring (offset to real idx)
        segments += TRANSPOSITION(t.aRange, t.bRange, innerOps)
    // align gap regions between consecutive spine anchors over UNCONSUMED tokens only:
    prevA=prevB=0
    for pin in spine (in order):
        segments += REGION( nwOverUnconsumed(a, b, prevA..pin.aStart, prevB..pin.bStart, consumed) )
        segments += REGION( [MATCH(pin.aStart+k, pin.bStart+k) for k in 0..pin.length) ] )
        prevA, prevB = pin end
    segments += REGION( nwOverUnconsumed(a, b, prevA..n, prevB..m, consumed) )
    return segments
```

### 5.1 Anchors (patience-style) + adaptive length

```
uniqueCommonAnchors(a, b, n):                    // unique-in-both n-grams of normalized keys
    grams_a = positions of each n-gram in a;  grams_b = same for b
    pins = [ (i, j, n) for gram with grams_a[gram]==[i] and grams_b[gram]==[j] ]
    drop overlaps keeping earliest-in-A          // disjoint anchor regions
    return pins

adaptiveAnchors(a, b, startN):                   // mitigate low lexical diversity
    wanted = clamp(min(|a|,|b|) / 50, 1, 8)
    best = []
    for k = max(2, startN) down to 2:
        anchors = uniqueCommonAnchors(a, b, k)
        if |anchors| >= wanted: return anchors    // largest n that anchors well (longer = more reliable)
        if |anchors| > |best|: best = anchors
    return best
```

### 5.2 Stable spine — maximum-weight increasing subsequence

```
maxWeightIncreasingByB(pins, weights):           // O(k²) DP; pins already sorted by aStart
    best[i] = weights[i];  prev[i] = -1
    for i: for j < i with pins[j].bStart < pins[i].bStart:
        if best[j]+weights[i] > best[i]: best[i]=best[j]+weights[i]; prev[i]=j
    return chain ending at argmax(best), reconstructed via prev   // ties → earliest end (determinism)
```

With equal weights this is a longest-increasing-subsequence; weighting (§5.3) breaks ties.

### 5.3 Page-aware tie-break
Weighting page-stable anchors `2` vs `1` makes the spine prefer them, so the block left *off* the spine — the
reported move — is the one that **changed page**. Resolves the symmetry of a two-block swap. (If page data is
absent, all weights are 1 ⇒ plain LIS.)

### 5.4 Block growth (identical neighbours + bounded bridging)
Grow each moved block outward on both ends, never onto a spine token:

```
mode 1 (identical): if a[edge] == b[edge]: absorb it
mode 2 (bridge):    else find a resync within `bridgeGap` tokens and absorb the mismatched run
                    (this pulls an edit INSIDE a moved sentence into the block — recursive anchoring)

resync(a, b, beforeA, beforeB, gap):             // backward; forward is symmetric
    search ai in [beforeA-gap, beforeA], bi in [beforeB-gap, beforeB], not on spine
    among identical pairs a[ai]==b[bi], choose min penalty = stepsA + stepsB + |stepsA - stepsB|
    return (ai, bi) or none                       // prefers near, balanced resyncs ⇒ bridge edits, not unrelated text
```

### 5.5 Recursive anchoring
A moved block is internally order-preserving, so align its two sub-spans with NW (§3); the resulting `innerOps`
(offset to real indices) are classified like a region but flagged `withinTransposition`. (Single-level: a move
nested inside a move is not recovered.)

### 5.6 Displacement gate (co-linearity constraint on moves)
A pin is an anchor purely because its n-gram is **unique in both** witnesses. On short inputs that is safe, but on
two long, *independent* witnesses (e.g. two translations of a novel) a rare phrase can be unique in each yet occur
at completely unrelated positions — a **coincidence, not a move**. Accepted uncritically, such a pin (a) reports a
nonsense transposition spanning most of the document and (b) corrupts the surrounding region alignment. The fix is
a **co-linearity gate**: two aligned witnesses are globally co-linear, so a *genuine* move is a local excursion off
the diagonal `bExpected(i) = round(i · |b| / |a|)`, while a coincidence lands far from it.

```
moveTolerance(|a|, |b|):                          // shared by BOTH move paths (§5.2 spine, §6.1 recovery)
    return clamp( floor(maxMoveFraction · max(|a|,|b|)),  minMoveTokens,  maxMoveTokens )

displacementIsPlausible(pin, |a|, |b|):
    if |a|==0 or |b|==0: return true              // nothing to gate against
    expected = round(pin.aStart · |b| / |a|)
    return |pin.bStart - expected| <= moveTolerance(|a|, |b|)

// Applied when partitioning anchors (§5.2): keep an off-spine (moved) pin only if displacementIsPlausible.
movedPins = [ p for p in offSpineAnchors if displacementIsPlausible(p, |a|, |b|) ]
// A rejected pin is NOT masked as a move; its tokens fall into ordinary region NW (§3) — i.e. the
// substitution/insert/delete they actually are.
```

Defaults (§10): `maxMoveFraction = 0.03`, `minMoveTokens = 200`, `maxMoveTokens = 6000`. The **diagonal** is used
deliberately rather than interpolating the stable spine: with two long independent witnesses the spine is itself
partly built from coincidental anchors, so a spine-relative expectation is unreliable; the whole-document diagonal
holds regardless of anchor noise. Determinism: the gate is a pure function of positions and lengths (§9).

**Distinctiveness gate (anchor-block path — the second, tighter co-linearity gate).** `moveTolerance` above is
length-proportional (≈1800 on a 60k-token novel), so it only rejects pairings *far* from the diagonal. That leaves a
residual coincidence class: a **short phrase** unique as a joined n-gram that recurs — by chance — in two unrelated
sentences of two independent translations ("off the rocks", "I look at", "we ought always to"). It becomes an
off-spine anchor and is reported as a spurious move. What separates such a coincidence from a genuine long-range
move is the block's **length**: a real relocated passage is a long distinctive run; a coincidence is a short
template. So a *second* gate runs **after block growth** (once the anchor has absorbed its surrounding identical run
and its true length is known), with a tolerance that **scales with block length** — a short block earns almost no
distance credit (must be genuinely local), a long distinctive block earns room to have moved far:

```
anchorMoveTolerance(blockLen):                    // distinctiveness-scaled bound (comparable-token units)
    return anchorBlockBaseTolerance + distinctivenessPerToken · max(0, blockLen - distinctivenessFreeLength)

anchorBlockIsPlausible(block, |a|, |b|):           // block = grown (aRange, bRange)
    dev = |block.bStart - round(block.aStart · |b| / |a|)|      // same diagonal metric as §5.6 / §6.1
    return dev <= anchorMoveTolerance(block.aRange.length)

// Applied after growth, before masking (§5.2): keep a grown block only if anchorBlockIsPlausible; a dropped
// block is NOT consumed, so its tokens fall into ordinary region NW (§3) — the sub/ins/del they actually are.
grownBlocks = [ t for t in grownBlocks if anchorBlockIsPlausible(t, |a|, |b|) ]
```

Defaults (§10), **recalibrated 2026-07-24 across four independent-translation full-novel pairs** (the original
single-corpus tuning — base 80, free 4, per 40, fit on earth-to-moon — admitted all 48 detected moves, every one
false, because on tightly-parallel translations the coincidences sit only 5–100 tokens off the diagonal, inside the
old flat-80 base): `anchorBlockBaseTolerance = 10` (a **distinct** constant, no longer the §6.1 `localMoveTokens`
80 — a short block must be genuinely local), `distinctivenessFreeLength = 14` (only a block longer than this earns
any distance credit), `distinctivenessPerToken = 18` (a 19-token relocation earns 10+18·5 = 100). Calibration set:
genuine moves that must survive range from a 1-token golden move (dev 1) through an 11-token sentence-swap (dev 9)
to the 19-token Whitman *Calamus* relocation (dev 84); false blocks span length 3–14 at deviation 5–508. Effect:
false moves **48 → 11** across the four pairs, every conformance golden and the Calamus relocation kept. The raw
anchor pin is only ~2–3 tokens regardless, which is *why* this gate must run post-growth: the discriminating length
does not exist at pin time. **Residual (irreducible on geometry):** a short block sitting almost *on* the diagonal
is indistinguishable from a genuine short local hop; it cannot be excluded by a length floor (the corpus has a
legitimate 1-token move) or by context (≈0 for genuine relocations too), so the honest treatment is *confidence*
(report as a possible move) rather than suppression:

```
anchorMoveIsCertain(blockLen, |a|, |b|):           // confidence for a block that PASSED the gate
    if blockLen > distinctivenessFreeLength: return true        // distinctive by length ⇒ assert
    return max(|a|, |b|) <= confidentMoveWitnessFloor           // short block: certain only in a SHORT witness
// else `likely` — a short block in a long parallel witness, where a small displacement is ambiguous ("off the
// rocks", dev 5, in an 86k-token novel). Scale-relative: the same 3-token block is certain in a 10-token swap.
```

Default (§10): `confidentMoveWitnessFloor = 4000` (comparable tokens) — between any crafted case (≤ ~120 tokens) and
any full novel (≥ ~40k). This softens confidence only; it never adds or drops a move, and the displaced-word path
(§6.1) sets its own confidence (globally-unique ⇒ certain). Determinism: a pure function of the grown block's
positions, its length, and the two witness lengths (§9).

**Expanding-window refinement (displaced-word path, §6.1).** A fixed cutoff also rejects a *genuinely large but
singular* move. For the displaced-word recovery (§6.1) the accept/reject decision is therefore made by an
**expanding-window search** rather than a hard bound — prefer the nearest candidate, widen only when the near
neighbourhood is unambiguous:

```
pairByExpandingWindow(delPositions, insPositions, |A|, |B|):
    near = moveTolerance(|A|, |B|)                     // the §5.6 near window
    candidates = [ (d, i, dist=|i - round(d·|B|/|A|)|)  for d in delPositions, i in insPositions
                                                        if dist <= maxMoveTokens ]
    sort candidates by (dist, d, i)                    // nearest first; ties by position (determinism)
    for c in candidates (skipping any d or i already used):
        if c.dist <= near:  accept (near = true)                        // a local move
        else:               # widened: accept only if UNAMBIGUOUS —
            if no other still-available candidate sharing c.d or c.i has dist < c.dist / ambiguityRatio:
                accept (near = false)                                   // a large but singular move ⇒ `likely`
    # never pair beyond maxMoveTokens; roughly-equidistant far rivals are declined (stay del + ins)
```

with `ambiguityRatio = 0.5` (a rival must be ≥2× farther for the pairing to count as unambiguous). A `near`
pairing of a globally-unique word is `certain`; a widened one is `likely` (§6.1). The anchor path (§5.2) still
uses the plain fixed gate: an anchor is unique-in-both by construction, so there is only one candidate and nothing
to search. Determinism: the search is a pure, ordered function of positions and lengths (§9).

## 6. Classification

Turn `segments` into typed, located, coalesced `Variation`s.

```
classify(segments, A, B, aMap, bMap, recordAccidentals):
    out = []
    for seg in segments:
        if seg is TRANSPOSITION(aR, bR, innerOps):
            out += Variation(TRANSPOSITION, surfaces, ranges, locations)        // the move itself
            out += classifyRegion(innerOps, withinTransposition=true)            // edits inside it
        else REGION(ops): out += classifyRegion(ops, withinTransposition=false)
    return out

classifyRegion(ops, ...):                         // coalesce adjacent non-matches
    accumulate runs of DELETE (pendingDel) and INSERT (pendingIns); on MATCH or end, flush:
        both non-empty → SUBSTITUTION;  only ins → INSERTION;  only del → DELETION
    on MATCH, if recordAccidentals and surfaces differ (same key) → VARIANT_SPELLING
    each emitted Variation gets locations via location(tokens, range)   // §7
```

Coalescing is why a reworded clause is **one** SUBSTITUTION, not several.

### 6.1 Displaced-reading recovery (single/short moves the anchor pass cannot see)

The anchor pass (§5) needs unique **n-gram** landmarks (n ≥ 2). A token (or short phrase) that moves **alone**
forms no shared bigram, so monotonic NW reports it as a DELETION (where it was) + an INSERTION (where it went)
— the diff artifact the engine exists to avoid (e.g. `the well-known author` → `the author is well known`,
where `author` *moved*). A post-classification pass recovers these:

```
recoverDisplacedReadings(variations, A, B):
    # candidate displaced WORDS: base words under DELETIONs, compared words under INSERTIONs
    #   (skip tokens already withinTransposition)
    for each such word, key = normalize(surface)
    match = a key that is UNIQUE among unmatched deletions AND unique among unmatched insertions
            (exactly one deletion-word and one insertion-word carry it)   # a meaningful 1:1 correspondence;
            # a common word left unmatched by the aligner has no such correspondence — never pair it by proximity
    # DISPLACEMENT via the EXPANDING-WINDOW search (§5.6): pairByExpandingWindow decides the DISTANCE question —
    #   accept the pair if it is NEAR the co-linear diagonal, or far-but-UNAMBIGUOUS (within maxMoveTokens);
    #   otherwise it is a coincidence: leave the words as an ordinary DELETION + INSERTION.
    for each match ACCEPTED by the search: carve that word out of its DELETION and its INSERTION into one TRANSPOSITION
        near = the pairing sat within the NEAR diagonal tolerance (did not need widening)
        confidence = CERTAIN if near AND the word is globally unique in BOTH witnesses
                   = LIKELY  otherwise — reached by widening, or the word recurs (paired by elimination: plausible, not proven)
    for each accepted pairing, record its DIAGONAL DEVIATION = |insTok − round(delTok·|B|/|A|)|   # locality metric
    coalesce matched words CONTIGUOUS in BOTH witnesses into one move block
        (a block is CERTAIN only if every word in it is CERTAIN; globallyUnique is ANDed and deviation MAX'd across it)
    # RARITY / LOCALITY GATE — drop the coincidences the 1:1-among-unmatched test admits:
    keep a move block iff it has a source of CORROBORATION —
        globallyUnique                              # (1) unique on both sides ⇒ unambiguous however far it moved
        OR words >= 2                               # (2) a multi-word phrase corroborates itself
        OR maxDeviation <= localMoveTokens          # (3) a genuinely LOCAL single-word hop (small off-diagonal dist)
        # equivalently: DROP only a LONE, globally-COMMON, NON-local word — the coincidence signature
        # a dropped block reverts to the plain DELETION + INSERTION the aligner already found
    whatever remains of a carved DELETION/INSERTION stays a (smaller) DELETION/INSERTION
```

**The rarity / locality gate.** The 1:1 test at `match` is over the *unmatched* words only. A word that is COMMON
in a witness but matched by the aligner at all-but-one of its occurrences is left unmatched exactly once, so it
passes the 1:1 test; the §5.6 displacement gate then rejects only pairings *far* from the diagonal, but two
independent translations run in parallel, so a common word's lone leftover routinely lands NEAR the diagonal by
coincidence. That manufactures a phantom move. Found by hand on the Verne *De la Terre à la Lune* pair: the
Mercier & King translation (siglum `towle`) uses "quietly" 5×, the moonvoyage base deletes the one clause
containing its single "quietly", and the leftovers paired thousands of tokens apart (diagonal deviation 5375) as a phantom `likely` move to an unrelated sentence — with 25
more lone common words alongside it.

What separates a real recovered move from such a coincidence is **corroboration**, of which there are three
sources, and a lone common word paired by elimination has *none*: (1) **global uniqueness** — one occurrence per
side, so the pairing is unambiguous however far apart; (2) a **multi-word block** — a phrase moving together is
not a coincidence; (3) **locality** — a genuine move of a *repeated* word is a short hop (the word swapped a few
positions with a neighbour inside its clause), whereas a coincidence lands far off the diagonal. The last is the
one that needs a threshold, and it must be **scale-independent**: `moveTolerance` (§5.6) is length-proportional
(≈1785 tokens on this novel) — right for admitting large singular moves of *unique* words, far too loose to vouch
for a *common* word. On the Verne corpus the two populations are cleanly separated by diagonal deviation — the one
genuine local hop ("firearms": "ancient or modern firearms" → "firearms, ancient and modern") at 46, every one of
the 26 coincidences at ≥141 — so a small absolute bound `localMoveTokens = 80` (in the 46→141 gap, ≈1.7×/1.8×
margins) tells them apart. The gate keeps a block with *any* of the three corroborations and drops only the lone
common non-local word. On the full-novel pair this removed all 26 coincidences (incl. "quietly"), kept the one
genuine local hop as `likely`, and left all 106 `certain` moves intact. This was **Option 1** of a deliberated
choice (see DEVELOPMENT_LOG 2026-07-15 and PAPER_NOTES §4.5.1 for the two alternatives weighed and why locality won).

**Determinism:** keys processed in sorted order; only keys unique-among-unmatched on both sides are merged;
ambiguous keys are left exactly as the aligner classified them; the gate is a pure function of the block's span,
global frequencies, and (integer) diagonal deviation. **Conservatism:** a genuine lone delete or
insert has no counterpart, so the pass can never fabricate a move. **Confidence** (`certain` | `likely`) is a
port-visible field on every variation (always `certain` for non-transpositions) and rides the JSON interchange
(added at schema v2; current schema is v3, §8); a report/visualisation surfaces a `likely` move as a *possible* move, not an assertion. This pass
is **required for parity** — a port must reproduce it (and the confidence values) to match the goldens.

### 6.2 Diplomatic punctuation overlay (optional; off by default)

Punctuation is folded out of alignment (§2), so a *substantive* apparatus never reports a punctuation-only
change — right for substantive collation, wrong for a **diplomatic** transcription where punctuation is
editorially significant. With `recordPunctuation` on, an **overlay** compares the punctuation tokens that sit
between two consecutive aligned WORDS, on each side, and emits any difference as a `variantSpelling`
(accidental):

```
recordPunctuation overlay (runs during classification, at each MATCH):
    track prevAFull, prevBFull = the previous matched word's full-token index on each side,
        carried ACROSS regions (anchors are regions too) so a split doesn't double-count;
        reset across a transposition (a move breaks the linear punctuation flow)
    at a MATCH(aFull,bFull): if prev≥0, compare punctuation surfaces in (prevAFull,aFull) vs (prevBFull,bFull)
        (whitespace-trimmed, empty ignored); if they differ → emit VARIANT_SPELLING located at the word
```

It is a **pure overlay**: alignment and the substantive apparatus are byte-identical with it off (the default
goldens are unaffected). Determinism: matches are processed in order; gaps are compared once. *(Surfaced by the
real-edition study — the Frankenstein 1818→1831 passage is substantively identical but differs in punctuation;
the overlay makes those four changes visible. BACKLOG B6b.)*

## 7. Location & citation

```
location(tokens, [lo,hi)):
    first = tokens[lo]; last = tokens[hi-1]
    return TextLocation(page=first.page, line=first.line, endLine=last.line,
                        firstWord=first.wordOnLine, lastWord=last.wordOnLine,
                        charFrom=first.charFrom, charTo=last.charTo)

cite(loc):  // 1-based, human
    single word  → "p.{page+1} · line {line+1} · word {firstWord+1}"
    word range   → "p.{page+1} · line {line+1} · words {firstWord+1}–{lastWord+1}"
    line range   → "p.{page+1} · lines {line+1}–{endLine+1} · words {firstWord+1}…{lastWord+1}"
```

## 7b. N-witness variant graph

```
variantGraph(witnesses, params):                  // base = witnesses[0]
    seed readingsByPos[i] = { baseSurface(i): {base.id} } for each comparable base token i
    insertionsByAnchor = {}                        // B6c: (anchor → reading → set<siglum>)
    for each compared in witnesses[1:]:
        r = collate(base, compared, params); changed = {}
        for v in r.variations:
            DELETION:     for pos in v.baseTokens: readingsByPos[pos]["∅"] += compared.id; changed += pos
            SUBSTITUTION: map each base token to the compared token at the same offset; record its surface;
                          changed += pos
            INSERTION:    if not v.withinTransposition:                     // B6c
                              insertionsByAnchor[v.insertionAnchor][v.comparedReading] += compared.id
            TRANSPOSITION / VARIANT_SPELLING: skip   // transposition = agreement at base
        for each comparable base token i not in changed: readingsByPos[i][baseSurface(i)] += compared.id
    baseNodes = [ GraphNode(basePosition=i, readings=readingsByPos[i]) for i sorted ]
    // B6c: one inserted node per (anchor, reading); witnesses NOT carrying that reading read "∅".
    insertedNodes = [ GraphNode(basePosition=-1, insertedAfter=anchor,
                                readings={reading: carriers, "∅": allIDs − carriers})
                      for anchor sorted, reading sorted ]
    nodes = merge(baseNodes, insertedNodes) ordered by (anchor key; base node before inserted at same key;
                                                         then reading) — so an insertion sits right after the
                                                         base position it follows
    variant nodes = those with >1 reading
```

Determinism (§9): anchors and readings are iterated in sorted order and the merge key is total, so the node
order — including inserted nodes — is stable across runs and ports.

**Implementation note (B11, 2026-07-02).** The engine now realises this fold as a **token-graph merge**: all
witnesses are merged into one DAG (spine nodes = aligned base tokens, `isMove` edges = transpositions, off-spine
nodes = insertions), then *projected* onto the apparatus-facing variant graph the pseudocode above describes.
The projection preserves this base-anchored node ordering and the inserted-node shape (so B6c is subsumed
structurally rather than as a special case), with one refinement: node readings are keyed on the **normalised**
form, so witnesses that substantively agree group into one reading rather than splitting on an accidental. A
port may implement either the fold above directly or the merge-then-project form; both must produce the same
projected graph (verified byte-for-byte by the conformance corpus). The token-graph substrate is also where
cross-language anchoring (B10) will add bilingual anchors.

**Merge strategy is a selectable parameter (B13/B14).** The reference engine exposes the N-witness merge as a
*strategy* choice — `baseAnchored` (the base-privileged fold specified above; the default and what the
unpinned goldens encode) and `peerMSA` (the peer merge, §7c — implemented since B14). A port SHOULD default to
`baseAnchored` to match the default goldens; a port implementing the peer merge verifies it against the
**strategy-pinned** corpus cases (a case's `meta.json` may carry `"strategy": "peer-msa"` and an inline
`"lexicon"`). The two strategies are not byte-identical where the peer merge genuinely resolves
moves/variance differently. Rationale + default policy: `PAPER_NOTES.md §5.3/§5.4`.

## 7c. Peer-MSA merge (`peerMSA`, B14)

The peer strategy removes base-privilege from *alignment* (the apparatus is still rendered against
`witnesses[0]` — the output shape needs a copy-text lemma). The tractable reference form aligns each witness
against the growing graph's **linear consensus spine**, reusing §5's aligner unchanged:

```
buildPeerMSA(witnesses, params, lexicon?):
    spine = one SLOT per comparable token of witnesses[0]        // slot: readings{key→(surface,sigla)},
    for each witness w in SORTED-ID order over witnesses[1:]:    //       page, baseFullPos?, createdKey
        cKeys[i] = pivot(consensusKey(spine[i]))                 // majority non-∅ reading; TIE keeps the
                                                                 // incumbent (createdKey) — never flip the
                                                                 // consensus on a 1–1 tie (anchor stability)
        wKeys    = pivot(comparable keys of w)                   // pivot = lexicon key map (§7d; identity if none)
        segs = align(cKeys, wKeys, params, pages)                // §5, with per-slot pages → §5.3 tie-break
        REGION ops:  match/substitute → w reads slot with ITS OWN token (normalised key + surface);
                     delete → w reads "∅";  insert → queue (afterSlot, token)
        DISPLACED-RUN RECOVERY: a deleted slot and a queued insert with the SAME key, each unique among this
                     witness's unmatched occurrences, AND |insertAnchor − delSlot| ≤ displacedWindow,
                     is a MOVE: w reads the slot (reordered), the insert is consumed, edge confidence=certain
                     (every other occurrence is matched in place — the pairing is structurally forced; the
                     window keeps a common word inside genuinely-new text from pairing with a distant
                     unrelated omission)
        TRANSPOSITION segs: apply innerOps to the slots (insert ops inside a move are within-move edits, not
                     slots); record an isMove edge over the block; confidence=certain (anchor-backed)
        SPLICE remaining queued inserts as NEW SLOTS after their anchor slot (descending anchor order), so
                     LATER witnesses align against them — text the base lacks becomes alignable
    finalise: absent witnesses read "∅" at every slot; ADJACENT inserted slots with IDENTICAL witness-
              partitions coalesce (a lone witness's inserted run is one node; partially-shared runs split
              exactly where carrier sets diverge); nodes = base-carried slots (the projected spine, in order)
              then inserted slots; project as §7b (inserted nodes anchor to the nearest preceding base slot)
```

Determinism (§9): witnesses merge in sorted-id order (NOT input order), so the graph is **byte-stable under
reordering of the non-base witnesses**; all ties are lexicographic; the consensus tie keeps the incumbent.
Properties a port must reproduce (all pinned by tests/goldens): a recurring-word move is `certain` (edge
confidence, from structure) where the pairwise post-pass says `likely`; partially-shared insertions group
across non-base witnesses; §5.3's page-crossing attribution is preserved; simple in-order sets project
identically to `baseAnchored`. Known divergence from the lift: the peer apparatus is **token-granular**, so an
unequal-length local rewrite may render as substitution + insertion where the lift's classifier coalesced one
entry.

## 7d. Translation lexicon (`lexicon`, B10 — cross-language anchoring)

An OPTIONAL, additive key-mapping layer for cross-language witness sets (see also §2's normalisation — the
lexicon operates on normalised forms). A lexicon is a set of equivalence groups of word-forms
(`{année, year}`, `{marquée, marked, signalised}`); each group maps to one **pivot** (its lexicographically
smallest member, so the mapping is deterministic and input-order-independent). Application rule: **alignment
keys only** — wherever comparable keys are extracted (§2 end; §7c's `cKeys`/`wKeys`), a covered form is
replaced by its pivot, so the anchor pass (§5.1) and NW (§3) treat translation pairs as equal — while
readings, surfaces, and normalised forms downstream are untouched (the apparatus shows each witness's own
words). Two behavioural consequences a port must honour: (1) a matched pair whose *normalised* forms differ
(possible only under a lexicon) is structural agreement, NOT a `variantSpelling` accidental — the accidental
check requires normalised equality; (2) displaced-reading recovery (§6.1) pairs on pivoted keys, so a moved
translation pair is recovered as a move. A nil/empty/irrelevant lexicon is the **identity, byte-for-byte** —
every unpinned golden is unaffected. File format (CLI `--lexicon`): one group per line, forms
comma-separated, `#` comments.

## 8. JSON interchange (the portability contract)

The recommended cross-language output. Reshape internal types for portability: ranges as `{from,to}`;
`VariationType` as its lower-case string tag; each variation carries a `confidence` (`certain` | `likely`,
§6.1); locations carry the 1-based `cite` string; graph readings as **sorted**
`[{reading, witnesses:[…sorted]}]`; emit with **sorted keys**. Tag with `schemaVersion` (currently **3** —
v2 added the `confidence` field; **v3 (B6c)** allows a graph node's `basePosition` to be `-1` and adds the
optional `insertedAfter` for inserted nodes). A port that emits this schema can be diffed byte-for-byte
against the reference implementation on shared witnesses.

## 9. Determinism rules (a port MUST follow these to match the reference)

1. NW traceback preference: **diagonal > up(delete) > left(insert)**.
2. Anchor overlap pruning: keep the **earliest in A**.
3. Max-weight subsequence ties: end at the **earliest** maximal chain.
4. `resync`: minimise `stepsA + stepsB + |stepsA − stepsB|`; ties → nearest.
5. All emitted collections that came from a set/map (graph readings, sigla) are **sorted** before output.
6. Displaced-reading recovery (§6.1): process keys in **sorted** order; merge only keys unique-among-unmatched
   on both sides; `confidence = certain` iff the moved word is globally unique in both witnesses, else `likely`.
7. Peer merge (§7c): non-base witnesses merge in **sorted-id order** (never input order); a consensus tie
   keeps the **incumbent** reading; lexicon pivots (§7d) are each group's lexicographically smallest member.
8. Displacement gate (§5.6): a moved anchor pin is accepted **only** when its B position is within
   `moveTolerance(|a|,|b|)` of the diagonal expectation `round(aStart·|b|/|a|)`. The displaced-word path uses the
   **expanding-window** search: candidates are ordered by `(dist, delTok, insTok)` and consumed greedily; a
   widened pairing is accepted only if unambiguous by `ambiguityRatio`; nothing past `maxMoveTokens` is paired.
   The tolerance, the diagonal, and the candidate ordering are pure functions of positions and lengths, so a
   port computes the identical accept/reject set. A rejected candidate becomes ordinary sub/insert/delete.

These rules are made **machine-checkable** by the conformance corpus and JSON Schema under
[`../conformance/`](../conformance/): every golden is byte-stable output the rules above guarantee, and
`collation.schema.json` is the formal wire contract a port can validate against (see §11.7).

## 10. Parameters (defaults, with rationale)

| name | default | meaning |
|------|---------|---------|
| `MATCH / MISMATCH / GAP` | `+2 / −1 / −2` (**prose**, default) | NW scoring; substitution preferred over delete+insert. |
| — verse preset (B7) | `+2 / −3 / −1` | Opt-in genre knob (`--scoring prose\|verse`). The default (**prose**) is what every golden pins. **Verse** sets `mismatch < 2·gap`, so a disjoint reworded run aligns as delete+insert (a rewritten line = a new line) rather than word-against-word substitutions, and a coincidental recurring word inside a rewrite is not treated as an anchor. Only the *ratio* matters; matches dominate, so co-linear text is unchanged. A port MUST default to **prose** to reproduce the goldens. |
| `anchorLen` | `3` | starting unique-n-gram length. |
| `minAnchorLen` | `2` | adaptive floor. |
| anchor-density target | `clamp(N/50, 1, 8)` | when adaptive retry stops shortening. |
| `bridgeGap` | `4` | max mismatched tokens bridged when growing a moved block. |
| `fullNWCellCap` | `1_000_000` | above this the no-anchor fallback bands. |
| `initialBand / maxBand` | `64 / 256` | band start and cap (cap bounds adversarial cost; alignment approx. there). |
| `displacedWindow` (§7c) | `12` | max distance (consensus tokens) between a lone omission and an insertion of the same key for the peer merge to call it a MOVE; beyond it the pair is a coincidence of unrelated edits, not a displacement. |
| `maxMoveFraction` (§5.6) | `0.03` | displacement gate: a move may deviate from the co-linear diagonal by at most this fraction of the witness length. Small because a *genuine* transposition is local; a coincidental unique-phrase match between two independent witnesses lands far off-diagonal. |
| `minMoveTokens` (§5.6) | `200` | gate floor, so short inputs (where 3 % is a token or two) still tolerate a legitimate local swap. |
| `maxMoveTokens` (§5.6) | `6000` | gate ceiling, so even a very long witness cannot admit an implausibly distant "move" merely because 3 % of a huge document is large (~a chapter's worth of tokens). |
| `ambiguityRatio` (§5.6) | `0.5` | expanding-window search: a *widened* (beyond-near) pairing is accepted only if no rival candidate sharing an endpoint is within `1/ratio` × (i.e. 2×) its distance — a clearly-closest far pairing is a real move, roughly-equidistant rivals are declined. |
| `localMoveTokens` (§6.1) | `80` | absolute locality bound (comparable tokens): the §6.1 gate keeps a lone non-unique displaced word only if its deviation ≤ this. Sits in the Verne 46 → 141 gap (≈1.7×/1.8× margins). *(No longer the §5.6 base — decoupled 2026-07-24.)* |
| `anchorBlockBaseTolerance` (§5.6) | `10` | distinctiveness-gate base, **recalibrated 2026-07-24** (was `localMoveTokens` = 80): the deviation a *short* grown anchor block is allowed — it must be genuinely local. Cut from 80 because on tightly-parallel translations short coincidental phrases land only 5–100 off the diagonal, inside the old base (all 48 four-pair moves were admitted). |
| `distinctivenessFreeLength` (§5.6) | `14` | distinctiveness gate, **recalibrated 2026-07-24** (was `4`): a grown move block of ≤ this length earns only the base tolerance — no distance credit — so a short block must be local. |
| `distinctivenessPerToken` (§5.6) | `18` | distinctiveness gate, **recalibrated 2026-07-24** (was `40`): each comparable token past `distinctivenessFreeLength` buys this much extra off-diagonal tolerance (the 19-token Calamus relocation earns 10+18·5 = 100 ≥ its dev 84). |
| `confidentMoveWitnessFloor` (§5.6) | `4000` | scale-relative move confidence (2026-07-24b): a short anchor block (≤ `distinctivenessFreeLength`) is asserted `certain` only in a witness ≤ this size (a real swap); in a longer parallel witness it is reported `likely` (its small displacement is ambiguous). Softens confidence only — never adds/drops a move. |

## 11. Porting checklist

1. Implement §0 model + §2 tokeniser (use the platform's Unicode word segmentation if available; lock parity).
2. §3 NW with the exact tie-break (§9.1); unit-test against the small examples.
3. §5.1–5.2 anchors + max-weight spine; §5.3 page weights.
4. §5.4 growth + bridging; §5.5 recursive inner alignment.
5. §6 classification; §7 locations + citation.
6. §4 banded fallback; §7b variant graph. *(Optional extensions: §7c peer merge, §7d translation lexicon —
   needed only to pass the strategy-pinned corpus cases.)*
7. §8 JSON; then **diff your JSON against the golden corpus** in [`../conformance/`](../conformance/) —
   reproduce every `golden/<case>.json` byte-for-byte (subject to the determinism rules §9 and identical
   tokenisation), and validate your output against `collation.schema.json`. This validates the whole port
   at once. See [`../conformance/README.md`](../conformance/README.md) for the "how a port passes" steps.

For a concrete, performance-oriented target language and milestones, see
[`../porting/RUST_STANDALONE_PLAN.md`](../porting/RUST_STANDALONE_PLAN.md).
