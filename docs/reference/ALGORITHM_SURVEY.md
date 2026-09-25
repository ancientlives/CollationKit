# CollationKit — algorithm survey, analysis, and candidate improvements

A single place to see **every algorithm in the engine**: what it is, why it is here, how it works, what it
costs, where it is weak, and what could replace or extend it. Written for a contributor deciding *what to work
on next*, and for the papers' methods and future-work sections.

**How this differs from its neighbours.** [`ALGORITHMS.md`](ALGORITHMS.md) is the *port spec* — normative
pseudocode a re-implementation must match. [`PAPER_NOTES.md`](PAPER_NOTES.md) is the *Swift-grounded reference*
— what the engine is now, with rationale. This document is the *analytical survey*: it assumes those two exist,
does not restate their pseudocode, and adds the layer neither has — comparative analysis, honest weakness
assessment, and a ranked catalogue of algorithms the project does not yet use. Where a claim here is normative,
it cites the section of `ALGORITHMS.md` that owns it.

**Status of the numbers.** Complexities are derived from the implementation (file and line cited where it
matters). Measured times are from [`../development/BENCHMARKS.md`](../development/BENCHMARKS.md) (release
build, median of 5 trials, macOS/8-core). Test and case counts verified 2026-09-06: 222 tests, 29 conformance
cases.

**Notation.** `n`, `m` = comparable-token counts of the two witnesses; `N` = witness count; `k` = anchor-pin
count; `r` = tokens in a single inter-anchor region. "Comparable" tokens are those with a non-empty normalised
key (§2) — punctuation folded out of alignment does not count.

---

## Part I — The algorithms in the engine

### Contents

| # | Algorithm | Stage | Cost | §
|---|---|---|---|---|
| 1 | Scanner tokenisation + normalisation | tokenise | `O(c)` | [1](#1-tokenisation--normalisation-a-hand-written-scanner) |
| 2 | Needleman–Wunsch global alignment | align | `O(n·m)` | [2](#2-needlemanwunsch-global-alignment-the-core) |
| 3 | Banded NW with auto-widening | align (fallback) | `O((n+m)·w)` | [3](#3-banded-needlemanwunsch-with-auto-widening-the-bounded-fallback) |
| 4 | Patience-style unique-n-gram anchoring | moves | `O(n+m)` expected | [4](#4-unique-common-n-gram-anchoring-patience-style) |
| 5 | Adaptive anchor-length retry | moves | `O(L·(n+m))` | [5](#5-adaptive-anchor-length-retry) |
| 6 | Max-weight increasing subsequence (spine) | moves | **`O(k²)`** | [6](#6-maximum-weight-increasing-subsequence-the-stable-spine) |
| 7 | Page-aware tie-breaking | moves | `O(k)` | [7](#7-page-aware-tie-breaking) |
| 8 | Block growth + bounded bridging (`resync`) | moves | `O(g²)` per edge | [8](#8-block-growth-and-bounded-bridging) |
| 9 | Recursive anchoring | moves | `O(b²)` per block | [9](#9-recursive-anchoring-edits-inside-a-move) |
| 10 | Displacement gate (co-linearity) | moves | `O(1)` per pin | [10](#10-the-three-false-move-gates-the-projects-hardest-won-algorithms) |
| 11 | Distinctiveness gate (length-scaled) | moves | `O(1)` per block | [10](#10-the-three-false-move-gates-the-projects-hardest-won-algorithms) |
| 12 | Rarity/locality gate | moves | `O(1)` per block | [10](#10-the-three-false-move-gates-the-projects-hardest-won-algorithms) |
| 13 | Expanding-window pairing search | moves | `O(d·i·log)` | [11](#11-expanding-window-pairing-search) |
| 14 | Run-coalescing classification | classify | `O(n+m)` | [12](#12-run-coalescing-classification) |
| 15 | Displaced-reading recovery | classify | `O(V·log V)` | [13](#13-displaced-reading-recovery) |
| 16 | Punctuation overlay | classify | `O(n+m)` | [14](#14-diplomatic-punctuation-overlay) |
| 17 | Base-anchored token-graph lift | merge | `O(N·P)` | [15](#15-base-anchored-token-graph-lift) |
| 18 | Peer-MSA consensus merge | merge | `O(N·P)` | [16](#16-peer-msa-consensus-merge) |
| 19 | Translation-lexicon pivoting | anchoring | `O(n)` | [17](#17-translation-lexicon-pivoting) |
| 20 | Location & citation mapping | locate | `O(1)` per variation | [18](#18-location-and-citation-mapping) |

---

### 1. Tokenisation & normalisation (a hand-written scanner)

**Role.** Stage 1 of the Gothenburg pipeline, and the decision that constrains everything downstream: it fixes
*what a unit of comparison is*. Every later algorithm operates on the token stream this produces, so a
tokenisation error is unrecoverable — no aligner can repair a bad segmentation.

**How it works.** A single linear scan over the character stream (`Tokenizer.swift`, 342 lines) classifies
maximal runs: a WORD is letters/digits plus *intra-word* `'`, `’`, `-`; a PUNCT is a maximal run of other
non-space characters; whitespace separates but is never a token. The same pass does four other jobs, which is
why it is more interesting than it sounds:

- **Hyphen splitting** — an interior hyphen splits the run (`dun-white` → `dun`, `-`, `white`), so hyphenation
  becomes an *accidental of word-division* rather than a 2-vs-1-token substitution. This is deliberately
  orthogonal to the substantive axis: `well-known` vs `well known` is no variant, but `well-known author` vs
  `author is well known` still is.
- **Normalisation** — the substantive/accidental lever: lowercase → strip diacritics → apply a spelling
  equivalence table (`colour`→`color`). PUNCT gets `normalized = ""` and is thereby invisible to alignment,
  *but its surface is retained* so the diplomatic overlay (§14) can still compare it.
- **Citation coordinates** — page, text-line, and word-on-line, per an explicit `PaginationModel`. Lines count
  *text lines only* and advance lazily on a line's first token, so a trailing blank never consumes a number.
- **`no_collate` regions** — editor-declared spans that emit *no tokens at all*.

**Complexity.** `O(c)` in characters, single pass, no backtracking. Negligible against alignment.

**Why this design.** The two non-obvious choices both pay off later. Retaining folded punctuation surfaces is
what makes the punctuation overlay a *pure overlay* — substantive output stays byte-identical with it on or
off. And `no_collate` fixes a problem *at source* that no downstream heuristic could: two editions' unrelated
front matter, force-aligned, produced junk variants *and* fed the move detector unanchored common words to
mismatch across the whole document. An editorial-markup solution beats a clever heuristic here because the
information (this is front matter) genuinely lives with the editor, not in the text.

**Weaknesses.**

1. **Scriptio continua (backlog B6, the last open tokeniser gap).** The scanner is space-delimited. Verified on
   Latin, Greek, French, and Cyrillic (conformance cases 14/21/24), but **CJK has no inter-word spaces**, so a
   Chinese or Japanese line collapses into a single token and collation degenerates entirely. This is a hard
   blocker for any non-alphabetic script, not a quality issue.
2. **The spelling table is a fixed GB↔US list**, so it generalises to no other orthographic tradition (historic
   spelling, editorial conventions, `ſ`/`s`).
3. **No morphological awareness.** `walked`/`walks` are unrelated keys.

**Improvement paths.** For (1), Unicode/ICU word segmentation (UAX #29) is the standard answer and Foundation
exposes it on Apple platforms — but note the port constraint: `ALGORITHMS.md §11.1` requires a port to *lock
parity*, so switching to a platform segmenter must not change existing goldens for space-delimited scripts.
Dictionary-based (MeCab/Jieba-style) or CRF/neural segmentation is stronger for CJK but introduces exactly the
determinism and dependency questions the project is careful about — a pinned, versioned dictionary is
acceptable; a learned segmenter needs the Appendix A argument answered. For (2), the spelling table should
become a *declared, user-owned artifact* like the `TranslationLexicon` already is — that is the project's
established pattern for editorial knowledge, and it is a clean, small contribution.

---

### 2. Needleman–Wunsch global alignment (the core)

**Role.** The comparison primitive, and the single most important reason this is not a `diff`. Applied to
inter-anchor regions, to the interior of moved blocks, and as the no-anchor fallback.

**How it works.** Classic dynamic programming over two key sequences (`Alignment.swift`), scoring
`MATCH=+2, MISMATCH=−1, GAP=−2` by default, with a **fixed traceback preference — diagonal > up > left** — which
is a determinism requirement (`§9.1`), not an implementation detail.

**Why NW and not LCS/Myers diff.** This is the load-bearing algorithmic choice, and the scoring encodes it:

- `MISMATCH > 2·GAP` (−1 > −4) ⇒ a one-token change scores better as **one SUBSTITUTE** than as DELETE+INSERT.
  This is exactly what LCS-based diff cannot express: `diff` has no substitution operation, so a reworded clause
  necessarily emerges as a deleted block plus an inserted block. Coalescing (§12) then makes a reworded clause
  *one* substitution rather than a scatter of word-level ones.
- `GAP < MISMATCH` ⇒ no spurious indels when a real substitution is available.

Only the *ratio* matters, which is what makes the verse preset possible: `+2/−3/−1` sets `MISMATCH < 2·GAP`, so
a rewritten line aligns as whole-line delete+insert (right for verse, where a rewritten line is a *new line*)
rather than as word-against-word substitutions.

**Complexity.** `O(n·m)` time and space. The engine's whole move architecture exists partly to keep `n` and `m`
small here: in practice NW runs on inter-anchor regions of a few dozen tokens, so the real cost is
`Σ O(rᵢ²)` over regions, which for realistic anchor density is near-linear in document length.

**Weaknesses.**

1. **Quadratic space** in the un-chunked case. Full NW is capped at `fullNWCellCap = 1_000_000` cells for this
   reason.
2. **Linear gap penalty.** Every gap position costs the same, so a 30-token omission costs 30× a 1-token
   omission. Real texts do not behave that way: an editor cutting a sentence performs *one* act. This is a real
   and well-understood modelling weakness — see the affine-gap proposal in Part II.
3. **Substitution cost is binary.** `cold`→`bitter` and `cold`→`colder` score identically. All lexical
   knowledge is confined to the normaliser's exact-match key.
4. **Monotonic by construction** — cannot represent a move at all, which is why §4–§13 exist.

**Improvement paths.** Affine gaps (Gotoh) and graded substitution costs are the two highest-value changes, both
in Part II. Hirschberg is the space fix if exactness on large arbitrary pairs ever matters.

---

### 3. Banded Needleman–Wunsch with auto-widening (the bounded fallback)

**Role.** Bounds the worst case. Without it, adversarially repetitive input (no anchors, so no chunking) would
put the full `O(n·m)` matrix on the critical path.

**How it works.** Compute only DP cells within `band` of the length-rescaled diagonal, `O((n+m)·band)`. Detect
whether the optimal traceback rides an *interior* band edge (corners are forced endpoints and don't count); if
so, double the band and retry, up to `maxBand = 256`. Globally optimal whenever the true path stays inside the
band; explicitly *approximate* once the cap binds.

**Why this and not the alternative.** The honest framing in `PAPER_NOTES §6` is worth preserving: on genuinely
structureless input every path scores alike, so there is *no meaningful optimal alignment to forfeit* — the cap
costs nothing real. And banding beat the earlier positional chunker (which cut both witnesses at the same
offset) because it is **seam-free**: a chunker produces artifacts at every cut, a band does not.

**Complexity.** `O((n+m)·w)` per attempt; with doubling from 64 to a 256 cap, at most 3 attempts, so the
constant is small and the total stays `O((n+m)·maxBand)`.

**Weaknesses.** The cap makes the result approximate on the pathological case, and — noted honestly in the
benchmark's own limitations — this regime is **characterised but never measured**: `collate-bench` floors anchor
density above zero, so the cliff the fallback exists to cap is not a recorded number. That is backlog **B19**,
and it is the single cheapest open item in the project.

**Improvement paths.** B19 first (measure it). Hirschberg would give exact alignment in `O(min(n,m))` space if
a case ever demands exactness where the band currently binds.

---

### 4. Unique-common n-gram anchoring (patience-style)

**Role.** The engine's central performance *and* structure mechanism. Anchors chunk the quadratic NW into small
regions, and simultaneously provide the landmarks that make move detection possible at all.

**How it works.** Index every n-gram of normalised keys in each witness; keep n-grams occurring **exactly once
in each** (`grams_a[g] == [i] && grams_b[g] == [j]`); drop overlaps keeping earliest-in-A. This is Bram Cohen's
patience-diff idea generalised from lines to token n-grams: uniqueness in *both* sequences is what makes a
correspondence trustworthy without any alignment work.

**Complexity.** `O(n + m)` expected with hashing.

**Weaknesses.** Two, and they are the deep ones:

1. **Anchors need n ≥ 2**, so anything moving alone forms no shared bigram and is structurally invisible here.
   That gap is exactly what §13's displaced-reading recovery exists to fill.
2. **Uniqueness is not distinctiveness.** On two long *independent* witnesses (two translations of the same
   novel), a short phrase can be unique in each by pure coincidence and sit at unrelated positions. Accepted
   uncritically it produces a nonsense document-spanning transposition *and* corrupts the surrounding region
   alignment. This one weakness generated three separate gates (§10) over about two and a half weeks, and its
   residual is provably irreducible on geometry alone.

**Improvement paths.** Suffix automata / suffix arrays would give maximal-unique-match extraction directly
(Part II), replacing fixed-n scanning with "longest unique match at each position" — a better-founded anchor set.

---

### 5. Adaptive anchor-length retry

**Role.** Mitigates low lexical diversity: at a fixed n, repetitive text yields too few unique n-grams to chunk
usefully, and cost collapses to the fallback.

**How it works.** Target `clamp(min(n,m)/50, 1, 8)` anchors. Try n = `anchorLen` (3) downward to
`minAnchorLen` (2); return the **longest** n that clears the bar (longer anchors are more reliable), else the
best found. Distinctive prose keeps trigrams; repetitive text degrades gracefully to bigrams.

**Complexity.** `O(L·(n+m))` for L ≤ 2 attempts — effectively free.

**Weaknesses.** A **global** choice of n for the whole document. A novel with dense dialogue in one chapter and
descriptive prose in another gets one compromise value. The floor of 2 is also a hard structural limit, and
lowering it to 1 was **considered and rejected** — single-word anchors are weak, brittle spine landmarks that
produce spurious transpositions and churn. That rejection is why the token-graph merge (§15/§16) is the
principled answer: moves should be read off *structure*, not off an ever-lower anchor floor.

**Improvement paths.** Locally-adaptive n (per region rather than per document), or — better — variable-length
maximal unique matches from a suffix automaton, which dissolves the "pick an n" problem entirely.

---

### 6. Maximum-weight increasing subsequence (the stable spine)

**Role.** Decides *which* anchors form the in-order backbone and which are therefore **moved**. This is the
algorithmic heart of transposition detection: the spine is the text's stable order, and everything off it moved.

**How it works.** Anchors sorted by A-position; an `O(k²)` DP over B-positions finds the maximum-weight
increasing chain (`Transposition.swift:709–716` — a genuine nested loop, `for j in 0..<i where bs[j] < bs[i]`).
With equal weights this is exactly a longest-increasing-subsequence; the weights (§7) break ties meaningfully.
Ties resolve to the earliest maximal chain (`§9.3`).

**Complexity.** **`O(k²)`** — and this is the one place where the engine's asymptotics are visibly worse than
necessary. Classic LIS is `O(k log k)` via patience sorting with binary search; the *weighted* variant is
`O(k log k)` with a max-prefix Fenwick tree (BIT) over B-positions.

**Is it a real problem?** Honestly: not yet, but it is the clearest asymptotic wart in the codebase. Anchor
density targets ≈ one anchor per 50 tokens capped at 8 for the *adaptive* decision, but the returned anchor set
on a full novel is far larger — on a 60k-token witness `k` can reach the thousands, making `k²` millions of
iterations. It has not shown up as a bottleneck because the constant is tiny and NW dominates. Still, it is a
textbook, low-risk, well-specified improvement with an exact determinism requirement to preserve — which makes
it an *excellent* first substantial contribution for a new student. See Part II, item 1.

**Weaknesses beyond cost.** The spine is a single global chain, so the model is "one stable order plus
excursions." A text that genuinely restructures (two chapters swapped *and* revised) is squeezed into that
frame.

---

### 7. Page-aware tie-breaking

**Role.** Resolves a genuine ambiguity that pure sequence alignment cannot: in a clean two-block swap, which
block *moved*? Mathematically symmetric — either answer yields the same alignment.

**How it works.** Weight an anchor `2` if its page is the same on both sides, `1` otherwise, then maximise
weight rather than length. The spine prefers page-stable anchors, so the block left off it — the reported move —
is the one that **changed page**.

**Why it is a genuine contribution.** This is one of the few places where the engine imports *domain* knowledge
into an alignment decision, and it is the right kind: a scholar cares which passage moved *relative to the
physical page*, because that is how the witness is cited. `COMPARISON.md` positions located page-aware
transposition as a real departure from CollateX/Juxta, and this weighting is the mechanism.

**Complexity.** `O(k)` to assign weights; the DP is unchanged.

**Weaknesses.** Only helps when a page model exists (with none, all weights are 1 and it degrades to plain LIS),
and `2:1` is an unmotivated magic ratio — no ablation has been run to justify it against, say, 3:1.

---

### 8. Block growth and bounded bridging

**Role.** An anchor pin is only ~2–3 tokens. The *actual* moved passage is usually a whole sentence. Growth
recovers its true extent — which matters enormously, because block length is the discriminating signal the
distinctiveness gate (§10) depends on.

**How it works.** Grow each moved block outward on both ends, never onto a spine token, in two modes: absorb
identical neighbours; or, on a mismatch, look for a **resync** within `bridgeGap = 4` tokens and absorb the
mismatched run between. `resync` minimises `stepsA + stepsB + |stepsA − stepsB|`, which prefers *near and
balanced* resyncs — the asymmetry term is what stops it bridging to unrelated text.

**Complexity.** `O(g²)` per edge with `g = bridgeGap = 4` — trivial.

**Why it matters more than it looks.** Bridging is what pulls an edit *inside* a moved sentence into the block,
so "moved and revised" is one transposition plus its internal edits rather than churn. And the note in
`ALGORITHMS.md §5.6` is important: the discriminating length **does not exist at pin time**, which is precisely
why the distinctiveness gate must run *post-growth*.

**Weaknesses.** `bridgeGap = 4` is a fixed constant, not adaptive — a moved sentence with a 6-token internal
revision will not bridge. This is a stated residual in `PAPER_NOTES §11`.

---

### 9. Recursive anchoring (edits inside a move)

**Role.** Handles the case that most distinguishes this engine from a diff: a passage that both **moved** and
was **revised**.

**How it works.** A moved block is internally order-preserving, so its two sub-spans are aligned with ordinary
NW (§2), offset back to real indices, and classified normally but tagged `withinTransposition`.

**Complexity.** `O(b²)` per block for block length `b` — small, since blocks are sentence-scale.

**Weaknesses.** **Single-level**: a move nested inside a move is not recovered (backlog **B18**, correctly rated
low priority — vanishingly rare in prose). The peer merge is identified as the natural home for a structural,
depth-recovering version if a real case ever demands it.

---

### 10. The three false-move gates (the project's hardest-won algorithms)

**Role.** Suppress coincidental matches misreported as transpositions. These are not incidental cleanup — they
are, in the project's own assessment, the most instructive work in it, and each one was found by *hand-inspecting
the viewer on a real novel*, not by a failing unit test.

The unifying insight, established over three attempts: **two aligned witnesses are globally co-linear**, so a
genuine move is a *local excursion* from the diagonal `bExpected(i) = round(i·m/n)`, while a coincidence lands
far from it. All three gates are pure functions of positions and lengths — no state, no learning, fully
deterministic (`§9.8`).

**(a) Displacement gate (2026-07-08).** Accept an off-spine pin only if
`|bStart − expected| ≤ moveTolerance(n,m)`, where tolerance is `clamp(0.03·max(n,m), 200, 6000)`. Deliberately
measured against the **whole-document diagonal, not the spine** — because with two long independent witnesses
the spine is *itself* partly built from coincidental anchors, so a spine-relative expectation is unreliable.
Result: ~825 book-spanning false transpositions eliminated; max diagonal deviation 722k → 28k chars.

**(b) Rarity/locality gate (2026-07-15, §6.1 path).** A word *common* in a witness but matched everywhere except
once is left unmatched exactly once, so it passes the 1:1-among-unmatched test, and on parallel translations its
leftover routinely lands *near* the diagonal by chance. Fix: require **corroboration** — global uniqueness, OR a
multi-word block, OR genuine locality (`localMoveTokens = 80`). Equivalently: drop only a *lone, globally common,
non-local* word. On the Verne pair the two populations separated cleanly — the one genuine local hop at deviation
46, all 26 coincidences at ≥141 — so 80 sits in the gap with ~1.7×/1.8× margins. Removed all 26, kept the genuine
hop, left all 106 `certain` moves intact.

**(c) Distinctiveness gate (2026-07-16, recalibrated 2026-07-24, anchor path).** The proportional tolerance in
(a) is ≈1800 tokens on a 60k-token novel — far too loose for a *short* coincidental phrase ("off the rocks",
"we ought always to"). Fix: a second, tighter gate run **after growth**, with tolerance scaling in block length:
`base + perToken · max(0, len − freeLength)`. A short block earns almost no distance credit; a long distinctive
block earns room to have genuinely moved far.

**The recalibration is the most important methodological episode in the project.** The 2026-07-16 constants
(base 80, free 4, per 40) were fit on **one** corpus (earth-to-moon), where phantoms sat *far* off the diagonal.
A 2026-07-24 audit across **four** independent-translation novel pairs showed that tuning admitted **all 48**
detected moves — every one false — because on *tightly-parallel* translations the coincidences sit only 5–100
tokens off the diagonal, comfortably inside the old flat base of 80. Recalibrated to base 10 / free 14 / per 18
(decoupling the base from `localMoveTokens`, which stays 80 for its own gate): **false moves 48 → 11**, every
conformance golden and the genuine 19-token Whitman *Calamus* relocation kept.

The calibration set is worth recording as a template for this kind of work: genuine moves that must survive span
a 1-token golden move (dev 1), an 11-token sentence swap (dev 9), and the Calamus relocation (dev 84); false
blocks span length 3–14 at deviation 5–508.

**(d) Scale-relative confidence (2026-07-24b).** The residual ~11 are **provably irreducible on geometry
alone**: a short block almost *on* the diagonal is indistinguishable from a genuine short local hop. No length
floor is admissible (the corpus contains a legitimate 1-token move) and context corroboration is ≈0 for genuine
relocations too (they land among different neighbours). So the honest treatment is *confidence, not
suppression*: `anchorMoveIsCertain` asserts `certain` for a distinctive-length block, or for a short block in a
witness ≤ `confidentMoveWitnessFloor = 4000` tokens (a real swap in a short text); otherwise `likely`. Asserted
false moves on the four pairs: **0**. No move added or removed, no golden changed.

**Complexity.** All `O(1)` per pin or block.

**Weaknesses.** These are **fitted constants** — six of them, calibrated on four Verne pairs plus the crafted
corpus. They are documented, deterministic, and inspectable, but there is no guarantee they transfer to a
different genre, period, or language pair. A medieval charter tradition or a modernist poem sequence could
behave quite differently. Nobody has tested that.

**Improvement paths.** Two honest directions. (i) **Widen the calibration set** — more authors, genres,
languages; report per-corpus sensitivity. Unglamorous, valuable, and directly strengthens the paper. (ii)
**Attack the residual with a non-geometric signal** — the open question in Part II, item 9, and the one place a
learned component has a genuinely defensible role.

---

### 11. Expanding-window pairing search

**Role.** A fixed cutoff rejects a *genuinely large but singular* move. This makes the accept/reject decision a
search rather than a threshold — but only on the displaced-word path (§13), where multiple candidates exist. The
anchor path needs no search: an anchor is unique-in-both by construction, so there is exactly one candidate.

**How it works.** Enumerate candidate (deletion, insertion) pairs within `maxMoveTokens`, sort by
`(distance, delTok, insTok)` — nearest first, ties by position for determinism — and consume greedily. Accept
immediately if within the near window; beyond it, accept only if **unambiguous**: no rival candidate sharing an
endpoint is within `1/ambiguityRatio` = 2× the distance. A near pairing of a globally unique word is `certain`;
a widened one is `likely`.

**Complexity.** `O(d·i)` candidates plus sorting, with `d`, `i` = unmatched deletion/insertion word counts.
Bounded in practice by the `maxMoveTokens` filter.

**Why it is well-designed.** "Prefer the nearest; widen only when the neighbourhood is unambiguous" is a sound
general pattern for correspondence under uncertainty, and the ambiguity test is what prevents the widening from
becoming a licence to pair anything. It is also the *only* legitimate memory-shaped idea Appendix A endorses:
local, bounded, per-run state derived solely from current inputs.

**Weaknesses.** Greedy consumption is order-dependent by construction — a globally optimal assignment (Hungarian
algorithm on the distance matrix) would be principled but slower and arguably less predictable. `ambiguityRatio
= 0.5` is another fitted constant.

---

### 12. Run-coalescing classification

**Role.** Turns raw alignment operations into the typed variants a scholar reads. Small, but it is what makes
the output *scholarly* rather than mechanical.

**How it works.** Walk the ops accumulating runs of DELETE and INSERT; flush on MATCH or end. Both non-empty →
**SUBSTITUTION**; only inserts → **INSERTION**; only deletes → **DELETION**. On a MATCH with differing surfaces
but equal keys, and only when requested → **VARIANT_SPELLING**.

**Why it matters.** This is why a reworded clause is *one* substitution rather than five word-level ones — the
single most visible quality difference between this engine's apparatus and a diff's output.

**Complexity.** `O(n+m)`, single pass.

**Weaknesses.** Coalescing is purely positional — adjacency in the op stream. It has no notion of syntactic or
semantic unit, so it will merge two genuinely unrelated adjacent edits into one substitution, and will split one
conceptual revision that happens to straddle a match. A known consequence appears in the peer merge, whose
apparatus is token-granular: an unequal-length local rewrite may render as substitution + insertion where the
base-anchored lift coalesced a single entry.

---

### 13. Displaced-reading recovery

**Role.** Fills the structural gap in anchoring (§4): a token that moves **alone** forms no shared bigram, so
monotonic NW reports it as DELETION + INSERTION — precisely the diff artifact the engine exists to avoid. The
motivating real case was a reported one: `the well-known author` → `the author is well known`, where `author`
*moved*.

**How it works.** Collect candidate words under DELETIONs (base) and INSERTIONs (compared), skipping anything
already `withinTransposition`. Key by normalised surface. Accept a key that is **unique among unmatched** on
both sides — a meaningful 1:1 correspondence. Hand the distance question to the expanding-window search (§11).
Carve accepted words out of their DELETION and INSERTION into a TRANSPOSITION; coalesce words contiguous in both
witnesses into one block (`certain` only if *every* word in it is certain); apply the rarity/locality gate
(§10b); leave the remainder as smaller DELETIONs/INSERTIONs.

**Complexity.** `O(V·log V)` over candidate words (sorted-key processing for determinism), plus the search.

**Conservatism — the key safety property.** A genuine lone delete or insert has no counterpart, so this pass
**can never fabricate a move**. Its failure mode is bounded to mis-pairing things that were already reported as
changes.

**Weaknesses.** "Unique among unmatched" turned out to be a much weaker guarantee than it appears — a common
word matched everywhere except once satisfies it trivially. That realisation is what produced gate (b). The pass
is also purely lexical (exact normalised key), so a word that moved *and* was inflected is invisible to it.

---

### 14. Diplomatic punctuation overlay

**Role.** Supports diplomatic transcription, where punctuation is editorially significant, without compromising
substantive collation, where it is noise.

**How it works.** At each MATCH, compare the punctuation surfaces sitting between the two previous matched
words on each side; differences emit a `variantSpelling`. State is carried *across* regions so a split doesn't
double-count, and reset across a transposition (a move breaks linear punctuation flow).

**Why the design is good.** It is a genuine **pure overlay**: alignment is untouched and the substantive
apparatus is byte-identical with it off — every default golden is unaffected. This "additive layer, zero effect
when off" pattern is the project's house style for optional features, and it is worth copying (the translation
lexicon follows it; a future semantic layer should too).

**Complexity.** `O(n+m)`.

**Weaknesses.** Only compares punctuation *between aligned words*, so punctuation inside an unaligned region is
not reported. Whitespace/line-break differences are not covered at all.

---

### 15. Base-anchored token-graph lift

**Role.** The default N-witness merge. Merges N−1 pairwise results into one DAG: spine nodes = aligned base
tokens, `isMove` edges = transpositions, off-spine nodes = insertions; then *projects* onto the apparatus-facing
`VariantGraph` so all renderers are unchanged.

**How it works.** Seed a reading map from the base's tokens; fold each pairwise collation in (deletions add
`∅`, substitutions record the compared surface, insertions become off-spine nodes keyed by anchor); unchanged
positions inherit the base reading. Node readings key on the **normalised** form, so witnesses that
substantively agree group into one reading instead of splitting on an accidental.

**Complexity.** `O(N·P)` for `P` base positions, plus the `N−1` pairwise collations that dominate. Measured
~linear in N (2→8 witnesses: 10.6→59.3 ms, ≈5.6× for 4×; slightly super-linear from growing reading sets).

**Weaknesses.** Structurally base-privileged: every witness is seen only *through* the copy-text. Variance
shared between two non-base witnesses but absent from the base cannot group properly, because they were never
compared to each other. That limitation is exactly what motivated §16.

**Improvement paths.** Embarrassingly parallel — the `N−1` pairwise collations are independent, and the porting
plan already names `rayon` for this in a Rust build.

---

### 16. Peer-MSA consensus merge

**Role.** Removes base-privilege from *alignment* (rendering still needs a copy-text lemma). Correct choice when
no witness is privileged: competing translations, base-free traditions, cross-language sets.

**How it works.** A spine of slots, one per base comparable token. For each witness in **sorted-id order**
(not input order — this is what makes the graph byte-stable under witness reordering), compute a **consensus
key** per slot (majority non-∅ reading, ties keeping the incumbent so a 1–1 tie never flips the consensus), then
align the witness against that consensus with the *unchanged* §4–§13 aligner. Deletions read `∅`; insertions
queue and are then **spliced in as new slots**, so text the base lacks becomes alignable by *later* witnesses.
A displaced-run recovery pass inside the merge pairs a deleted slot with a same-key queued insert within
`displacedWindow = 12`, marking it a move with `certain` confidence — because every other occurrence is matched
in place, so the pairing is structurally forced.

**Why it earns its complexity.** Three properties the lift cannot provide: recurring-word moves are `certain`
*from structure* (where the pairwise post-pass can only say `likely`); partially-shared insertions group across
non-base witnesses; and the lexicon's cross-language anchors attach here.

**Complexity.** `O(N·P)` merge plus N alignments against a spine that grows with splicing.

**Weaknesses (stated honestly in the docs, and worth preserving).** Alignment is against the **linear consensus
spine** — an approximation of true graph alignment; CollateX's A*/beam search over the decision graph remains
the more exhaustive form. Base privilege persists in *rendering*. Nested moves stay single-level. And the peer
apparatus is token-granular, so an unequal-length rewrite may render as substitution + insertion where the lift
coalesced one entry.

**Improvement paths.** True progressive MSA with a guide tree, or alignment against the *graph* rather than a
linearised consensus — Part II, item 6.

---

### 17. Translation-lexicon pivoting

**Role.** Cross-language collation. Alignment anchors on shared word-forms; across a language boundary there are
almost none, so the graph degraded to purely *positional* alignment — surfaced concretely by the trilingual
Verne case.

**How it works.** Equivalence groups (`{année, year}`) each map to a **pivot** — the lexicographically smallest
member, so the mapping is deterministic and input-order-independent. Applied to **alignment keys only**, so NW
and the anchor pass treat translation pairs as equal while readings and surfaces stay untouched and the
apparatus shows each witness's own words (`marquée | signalised | marked`).

**Why the design is exemplary.** A nil/empty lexicon is the **byte-for-byte identity** — every unpinned golden
is unaffected. Two consequences a port must honour: a matched pair whose normalised forms differ (possible only
under a lexicon) is structural agreement, *not* an accidental; and displaced-reading recovery pairs on pivoted
keys, so a moved translation pair is recovered as a move. This is the model for how *any* future knowledge
source — including a semantic layer — should enter this engine: additive, alignment-only, identity when absent,
and a **declared, user-owned, versionable artifact** rather than opaque learned state.

**Complexity.** `O(n)` hash lookups.

**Weaknesses.** Single-token equivalences only, so noun–adjective inversion across the boundary
(`phénomène inexpliqué` vs `mysterious phenomenon`) is an NW tie that can pair one slot off. Lexicons are
hand-authored, so coverage is a manual cost. No sense disambiguation — a polysemous word maps to one pivot
regardless of context.

**Improvement paths.** Backlog **B17**: sentence-aligned parallel-text anchors as the richer successor. Part II,
item 7.

---

### 18. Location and citation mapping

**Role.** Turns a token range into a scholarly citation. `COMPARISON.md` names citation-as-a-first-class-model
one of the genuine departures from prior art, so this small algorithm carries real weight.

**How it works.** Take first and last token of a range; emit page, line, end-line, first/last word-on-line, and
the exact character range for highlighting. Render 1-based with the right grammatical form: a single word cites
a *position* ("p.1 · line 2 · word 3"), a multi-word variant a *range* ("words 3–4"), a cross-line reading a
*line range*.

**Complexity.** `O(1)` per variation — coordinates were computed during tokenisation.

**Why it matters.** The `PaginationModel` makes the page/line convention an **explicit input** rather than an
inference: `.markers`, `.linesPerPage(N)`, or `.explicit(offsets)`, crossed with `.perPage` or `.continuous`
numbering. Two scholars citing the same text by different conventions get different, equally correct citations
from the same engine — which is the correct treatment of a genuinely conventional matter.

**Weaknesses.** `.explicit` requires the edition's page offsets to *exist* — imported, never inferred. Readings
are reconstructed by joining token surfaces with spaces, so original spacing/punctuation is not preserved in the
reading string (a host application can slice the source by char range for exact surface).

---

## Part II — Candidate algorithms and improvements

Ranked by **value ÷ effort**, with the risk to the project's invariants stated for each. The overriding
constraint for every item: the engine must stay a **pure, deterministic function of (witnesses + declared
configuration)** — see [`PAPER_NOTES.md` Appendix A](PAPER_NOTES.md). An improvement that costs reproducibility
is not an improvement here.

Legend: **Effort** S/M/L · **Risk** to goldens and invariants.

---

### Tier 1 — clear wins, low risk

#### 1. Fenwick-tree weighted LIS for the spine · Effort S · Risk: none if determinism preserved

**Replaces:** §6's `O(k²)` DP (`Transposition.swift:709–716`).

The weighted maximum increasing subsequence is computable in `O(k log k)` with a max-prefix Fenwick tree indexed
by B-position: for each pin in A-order, query the max weighted chain over all smaller B-positions, add this pin's
weight, and update. This is the same transformation that turns naive LIS into patience-sorting LIS.

**Why it is the ideal first substantial contribution:** self-contained (one function), textbook algorithm,
enormous existing test coverage to protect you, and a crisp success criterion — **every one of the 222 tests and
29 goldens must be byte-identical**. The subtlety, and the reason it is not trivial, is `§9.3`: ties must still
resolve to the **earliest maximal chain**. A Fenwick tree returning "a" maximum is not enough; it must return the
*same* maximum the `O(k²)` scan would. Get that right and you have learned the project's whole engineering
culture in one change.

**Payoff:** thousands of anchors on a full novel means millions of DP iterations removed. Not currently the
bottleneck, but it removes the only asymptotic wart in the engine.

#### 2. Adversarial benchmark point (backlog B19) · Effort S · Risk: none

`collate-bench` floors anchor density above zero, so the near-zero-anchor regime the banded fallback exists to
cap is **characterised but never measured**. Add an explicit all-repetition point. Closes the one gap the
benchmark notes call out themselves, gives the paper a real number where it currently has an argument, and
touches only the harness. Genuinely the cheapest open item in the project.

#### 3. Witness-profile artifact (backlog B15) · Effort S–M · Risk: none (additive)

Compute each witness's word-frequency map and unique-n-gram profile **once**, then (a) reuse across all pairings
in an N-witness or whole-author run — a clean performance win orthogonal to correctness — and (b) **export it as
an inspectable audit artifact**, so a user can check *why* the engine treated a phrase as an anchor. That is
exactly the hand-check that found the earth-to-moon phantom, built into the tool.

**Read the scope note in the backlog before starting.** This is audit + performance, explicitly **not** a
stop-word blocklist. Suppressing common tokens up front would blind the aligner to real moves anchored by common
words (the genuine local move "he continued with an amiable smile"). The engine keeps every token and judges
moves by position and structure, not vocabulary.

#### 4. Affine gap penalties (Gotoh's algorithm) · Effort M · Risk: **changes goldens** — needs opt-in

**Replaces:** §2's linear gap model.

Currently a 30-token omission costs 30× a 1-token omission. Real editing does not work that way: cutting a
sentence is *one* act. Gotoh (1982) models this with `gapOpen` + `k·gapExtend` using three DP matrices, in the
same `O(n·m)` time and space.

This is the most **linguistically principled** improvement available to the aligner, and it should measurably
reduce fragmentation on witnesses with large structural cuts — a common real case (an editor deleting a whole
paragraph). It is standard in bioinformatics for precisely this reason.

**The constraint that shapes the work:** it *will* change alignments and therefore goldens. So it must land as
the project lands everything — as an **opt-in preset alongside prose/verse** (`--scoring affine`, or new
parameters within a preset), with the existing prose default byte-identical. `TOKEN_GRAPH_PLAN.md` documents the
migration discipline; `ScoringPresetTests` is the pattern to copy. Then *evaluate*: does it actually reduce
fragmentation on the Verne corpus? That evaluation is publishable in itself.

---

### Tier 2 — substantial engine work

#### 5. Suffix automaton / suffix array anchoring · Effort M–L · Risk: high (reshapes anchor set)

**Replaces or augments:** §4's fixed-n scanning and §5's adaptive retry.

A suffix automaton or enhanced suffix array yields **maximal unique matches** directly — the longest unique-in-
both match at each position — in `O(n+m)`. This dissolves the "pick an n" problem: instead of trying n=3 then
n=2 globally, you get variable-length anchors, naturally longer in distinctive passages and shorter in
repetitive ones.

Potential second-order benefit: because MUM length is a *measured distinctiveness* signal available at anchor
time, it might partially subsume the distinctiveness gate (§10c) — which currently has to run post-growth
precisely because pins carry no length information. That is speculative and worth testing, not assuming.

**Risk is real.** This changes the anchor set, so it changes the spine, so it changes moves and goldens. It
needs the full migration treatment: build behind the existing interface, prove on the Verne corpus and the
conformance suite, and only then consider flipping a default. Do not start here.

#### 6. True progressive MSA with a guide tree · Effort L · Risk: contained (new strategy)

**Extends:** §16's peer merge.

The peer merge aligns each witness against a *linear consensus spine* — a documented approximation. The
standard bioinformatics answer is progressive alignment guided by a **similarity tree**: compute pairwise
distances, build a guide tree (neighbour-joining), and merge most-similar-first, aligning profile-to-profile
rather than sequence-to-consensus.

For textual scholarship this is unusually well-motivated: a guide tree is approximately a **stemma**, the
manuscript family tree that is a central object of textual criticism in its own right. A merge order derived
from measured similarity is more defensible than sorted-id order, *and* the tree is a publishable artifact.

The clean way to land it is as a **third strategy** behind the existing `CollationStrategy` seam — `.baseAnchored`
and `.peerMSA` are untouched, so no golden moves, and the new one is pinned by its own strategy-tagged
conformance cases. That seam existing is exactly why this is contained rather than dangerous. (Note the
determinism requirement: a neighbour-joining tie must break deterministically.)

#### 7. Sentence-aligned parallel-text anchors (backlog B17) · Effort L · Risk: contained (additive layer)

**Extends:** §17's word-level lexicon.

Align at **sentence** granularity first, then within sentences. Classical approaches are length-based
(Gale–Church, using the observation that translated sentences correlate in length) and lexical (Hunalign) — both
deterministic, both citable, neither requiring learned components. Modern multilingual sentence embeddings
(LaBSE, SBERT) are stronger but bring the Appendix A questions with them, so the honest framing is: **do the
classical version first, measure it, and only then ask whether embeddings buy enough to justify a pinned model
dependency.**

This directly addresses the lexicon's documented residual (noun–adjective inversion across the boundary), and
the Verne corpus — French originals plus rival English translations, already collected with a bibliography — is
sitting there as evaluation data. Attaches to the peer merge as additional seeding anchors, the same shape as
B10, so it stays additive.

#### 8. TEI critical-apparatus I/O (backlog B12) · Effort M–L · Risk: none (new renderer)

Not an algorithm improvement but the **biggest interoperability win available**, and it is what makes the engine
usable by the actual DH community (CollateX, Versioning Machine, TEI Publisher all consume TEI P5). Output
first — render the N-witness graph as `<app><lem><rdg>` parallel segmentation, a new render model beside
`Apparatus`/`Synopsis`. Input later — parse TEI parallel segmentation into `[Witness]`. Validate against the TEI
schema.

Pure addition: no existing algorithm changes, no golden moves. It pairs with the HTML viewer as the "scholarly
export formats" track.

---

### Tier 3 — research-grade, high value, needs care

#### 9. The irreducible residual: a non-geometric move signal · Effort L · Risk: **must not compromise determinism**

The most interesting open question in the project, and the one place a learned component has a genuinely
defensible role.

The residual false-move class is **provably irreducible on geometry alone** (§10d): a short block sitting almost
on the diagonal is indistinguishable from a genuine short local hop; no length floor is admissible (the corpus
has a legitimate 1-token move) and context corroboration is ≈0 for genuine relocations too. Current treatment:
report as `likely`.

**Is there a signal that separates these where geometry cannot?** Candidates, cheapest first:

- **Syntactic role.** A genuine move usually relocates a *constituent* — a clause or phrase — whereas a
  coincidence pairs fragments that cross constituent boundaries. A dependency parse would test this, and parsers
  are deterministic and pinnable.
- **Semantic context similarity.** Do the *surroundings* of the two positions resemble each other? A genuine
  relocation lands in a related context; a coincidence does not. The docs record that lexical context
  corroboration is ≈0 — but *semantic* context similarity is a different measurement and has not been tried.
- **Discourse position.** Paragraph and sentence boundaries carry structure the token-index diagonal discards.

**The bar any of these must clear** (from Appendix A, and non-negotiable): deterministic given pinned model
versions; auditable — a scholar must see *why*; opt-in and clearly labelled, so the apparatus distinguishes
"the engine measured this" from "a model judged this"; and byte-identical output when disabled.

This has everything a good research project needs: a clean baseline, a real corpus, an existing metric (asserted
false moves, currently 0 with 11 unasserted residuals), and a **documented negative result to beat** (neither
word- nor phrase-rarity separates the populations — the phantoms were the *rarest* phrases). That last point is
worth dwelling on: it is a genuine, recorded empirical finding that killed the intuitive hypothesis.

#### 10. Semantic / paraphrase layer · Effort L · Risk: **high — read Appendix A first**

The specced-but-unbuilt flagship. The engine is a *substantive* collator: it reports that `cold wind` became
`bitter wind`, but cannot say whether a substitution is a **paraphrase** (same meaning, reworded) or a genuine
change of sense. Distinguishing them is a sentence-embedding / lexical-semantics problem on a clean seam — the
engine hands you typed, located, aligned substitution spans, and the layer *classifies* them.

**Design constraints, all non-negotiable, and all satisfiable:**
- **Additive layer** — never alters alignment, so the substantive apparatus stays byte-identical. Copy the
  `TranslationLexicon` pattern exactly (§17): alignment-only, identity when absent.
- **Deterministic** — pinned model version, recorded in the run manifest, reproducible output.
- **Inspectable** — a similarity score the scholar sees and can overrule, never a hidden reclassification.
- **Opt-in and labelled** — the apparatus must distinguish measured from judged.

**The hard part is evaluation, and that is also the paper.** What *is* ground truth for "paraphrase" in a
critical edition? Scholarly judgement varies. Designing that evaluation — inter-annotator agreement on a real
witness set, then measuring against it — is the genuine research contribution; the embedding lookup is the easy
half.

#### 11. Graded substitution cost · Effort M · Risk: **changes goldens** — needs opt-in

**Extends:** §2's binary substitution cost.

Currently `cold`→`bitter` and `cold`→`colder` score identically at MISMATCH. A graded cost — edit distance for
orthographic near-misses, or lemma identity for inflectional variants — would let the aligner prefer the
correspondence a human would.

The **conservative version is much more attractive** than the general one: a *morphological* variant is arguably
an accidental of inflection, not a substantive difference, which puts it in the normaliser's territory (§1)
rather than the scorer's — and the normaliser already owns exactly this kind of judgement with the GB/US table.
A lemmatiser (deterministic, pinnable, or a declared table) fits the existing architecture with far less risk
than a continuous similarity function inside the DP.

Either way it changes alignments, so: opt-in preset, existing default byte-identical, then evaluate.

#### 12. Hirschberg linear-space alignment · Effort M · Risk: none if exactness preserved

Exact full NW in `O(n·m)` time but `O(min(n,m))` space, via divide-and-conquer on the optimal midpoint. Already
named in `PAPER_NOTES §6` as the exact alternative to banding.

**Be clear about what it does and does not buy.** It cures the *memory* cliff for a fully-arbitrary large pair,
not the time cost — and the realistic worst case here is a long but *loosely co-linear* pair, where a small band
is both correct and far cheaper. So this is worth doing only if a real case appears where the band cap binds and
the approximation is unacceptable. Do B19 (item 2) first: measure the regime before optimising for it.

---

### Tier 4 — performance engineering (correctness-neutral)

These change no output. All are `O(1)`-risk to goldens, and each can be validated by "all 222 tests still pass,
byte-identical."

| # | Change | Where | Expected gain |
|---|---|---|---|
| 13 | **Parallelise the N−1 pairwise collations** | §15 lift | Near-linear speedup in N — the pairs are genuinely independent. Already named for `rayon` in the Rust plan; Swift Concurrency (`TaskGroup`) is the in-package route. Determinism is preserved as long as results are *reduced in fixed order*. |
| 14 | **SIMD the NW inner loop** | §2 | The DP row update vectorises. The porting plan rates it "diminishing returns, do only if benchmarks demand" — that judgement should be respected: profile first. |
| 15 | **Interned token keys** | §1 → all | Replace string keys with integer ids from a global intern table. Turns every comparison into an integer compare and shrinks the hashing cost in anchoring. Broad, mechanical, low-risk, and probably the largest constant-factor win available. |
| 16 | **Rust port** | whole engine | `RUST_STANDALONE_PLAN.md` expects an order-of-magnitude on large corpora before any SIMD, plus a WASM path for browser-based collation. The conformance corpus (29 goldens + JSON Schema) is what makes this verifiable rather than hopeful. |

---

## Part III — What to work on, by interest

| If you want to… | Start with |
|---|---|
| Learn the codebase safely | **1** (Fenwick LIS) or **2** (B19 benchmark) |
| Do algorithms + measurable results | **4** (affine gaps) then **5** (suffix automaton) |
| Do ML/AI within the project's constraints | **9** (residual signal) — read Appendix A first; then **10** (semantic layer) |
| Do cross-language / NLP | **7** (sentence alignment) — the Verne corpus is ready |
| Make the project *used* by others | **8** (TEI I/O) |
| Do performance engineering | **15** (interning) → **13** (parallel) → **16** (Rust) |
| Contribute to textual scholarship as such | **6** (guide tree ≈ stemma) |

**Whatever you pick, the workflow is the same** — it is the project's culture, and it is what makes changes here
land safely:

1. `swift test` (222 green) before you start.
2. Build behind existing types (`TOKEN_GRAPH_PLAN.md`); leave the old path byte-identical.
3. `swift test` after — investigate **every** diff. A changed golden is a deliberate, documented decision, never
   a way to get green.
4. Run the release binary on a real novel and **open the viewer**. Several defects in this project's history
   were invisible in unit tests and obvious within thirty seconds of looking at `collation.html`.
5. Dated entry in `DEVELOPMENT_LOG.md`; update **both** `ALGORITHMS.md` (normative spec) and `PAPER_NOTES.md`
   (rationale); tick `BACKLOG.md`.

---

## References

Algorithms cited above, with their role here:

- **Needleman & Wunsch (1970)**, *J. Mol. Biol.* 48(3):443–453 — global alignment; the engine's core (§2).
- **Gotoh (1982)**, *J. Mol. Biol.* 162(3):705–708 — affine gap penalties in `O(n·m)` (Part II, 4).
- **Hirschberg (1975)**, *CACM* 18(6):341–343 — linear-space alignment (§3 alternative; Part II, 12).
- **Smith & Waterman (1981)**, *J. Mol. Biol.* 147(1):195–197 — local alignment; context, not used.
- **Myers (1986)**, *Algorithmica* 1:251–266 — the O(ND) LCS/diff baseline this engine departs from (§2).
- **Cohen**, *patience diff* — unique-common-element anchoring, generalised to n-grams (§4).
- **Gale & Church (1993)**, *Computational Linguistics* 19(1):75–102 — length-based sentence alignment
  (Part II, 7).
- **Ukkonen (1995)**, *Algorithmica* 14(3):249–260 — suffix-tree construction; the MUM route (Part II, 5).
- **Saitou & Nei (1987)**, *Mol. Biol. Evol.* 4(4):406–425 — neighbour-joining guide trees (Part II, 6).
- **Fenwick (1994)**, *Software: Practice and Experience* 24(3):327–336 — the BIT for weighted LIS
  (Part II, 1).
- **Greg (1950–51)**, *Studies in Bibliography* 3:19–36 — substantives vs. accidentals; the normaliser's
  conceptual basis (§1).
- **Haentjens Dekker et al. (2015)**, *DSH/LLC* — CollateX and the variant graph; the merge prior art
  (§15–§16).

> Reference details should be verified against primary sources before publication — they are recorded here as
> the intended bibliography, consistent with the note in `PAPER_NOTES.md`.

## See also

- [`ALGORITHMS.md`](ALGORITHMS.md) — the normative port spec (pseudocode, invariants, determinism rules §9,
  parameter defaults §10).
- [`PAPER_NOTES.md`](PAPER_NOTES.md) — Swift-grounded reference; **Appendix A** on memory and learning is
  required reading before any ML proposal.
- [`../development/BENCHMARKS.md`](../development/BENCHMARKS.md) — measured cost and its honest limitations.
- [`../development/BACKLOG.md`](../development/BACKLOG.md) — the ranked open items (B6, B12, B15–B19).
- [`../development/DEVELOPMENT_LOG.md`](../development/DEVELOPMENT_LOG.md) — how each algorithm arrived, and
  what was rejected on the way.
- [`COMPARISON.md`](COMPARISON.md) — what is inherited from CollateX/Juxta vs. genuinely new.
- [`../ONBOARDING.md`](../ONBOARDING.md) — new-contributor orientation.
