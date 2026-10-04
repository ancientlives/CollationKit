# CollationKit engine review — `Sources/CollationKit/` (October 2026)

Read-only review. All 16 engine files were read in full, then checked against `docs/reference/ALGORITHMS.md` and `PAPER_NOTES.md`.
Reproductions were run with the `collate` CLI (debug and release builds) and with a small probe package that links
the library. `$C` below means a debug build of `collate`.

Fuzzing: 3 seeds × 3000 random small witness triples (substantive and diplomatic, both strategies, debug build
with overflow traps on). The engine had **no crashes**. The fuzzing did surface the overlap bugs A1 and A6.

---

## (A) Confirmed bugs

### A1. HIGH — Compared tokens get matched twice; real differences are silently lost (anchors de-overlapped in A only)
`Transposition.swift:654-666` (`uniqueCommonAnchors` de-overlaps in A only), `:207-218` (each spine pin emits
`.match` for its whole span), `:96-118` (moved pins are never checked against spine pins' B spans), `:329-330` (the
clamp hides the overlap instead of resolving it).

When two kept anchors overlap in B, every B token in the overlap is matched twice. A moved block whose B span
overlaps a spine pin has the same problem. The base tokens on the other end of the duplicate match are never
reported. The earlier "inverted Range" fix only clamped the region, so this case no longer crashes, but it now
produces a wrong answer with no warning.

- Repro 1:
  `printf 'alpha beta gamma delta epsilon beta gamma zeta\n' > a.txt; printf 'alpha beta gamma zeta\n' > b.txt; $C run a.txt b.txt --format json`
  - Observed: a single deletion "delta epsilon". The graph shows the second `beta gamma` (base positions 5–6) as agreement.
  - Expected: four base words deleted (for example "delta epsilon beta gamma"). Compared tokens 1–2 are used twice.
- Repro 2 (a moved pin overlapping a spine pin):
  - `a = "x y z s1…s30 z w1…w20 end1 end2 end3"`
  - `b = "x y z w1…w20 s1…s30 end1 end2 end3"`
  - Files: `t1/mv1.txt`, `t1/mv2.txt`.
  - Observed: a single transposition with `comparedTokens 2..<23`. Compared token 2 (`z`) is also matched by the spine anchor `x y z`.
  - Expected: the base's second `z` should be reported as a deletion. It is not reported at all.
- Fix direction: de-overlap pins in B as well, at least between spine pins. Drop or trim any moved pin whose B span intersects a spine pin.

### A2. HIGH — Base-anchored N-witness graph and apparatus drop or misattribute compared text on substitutions
`TokenGraph.swift:163-177`. The same logic is in `Collation.legacyVariantGraph` (`Collation.swift:278-293`), and the
spec itself says to do this (§7b: "map each base token to the compared token at the same offset").

The k-th full base token is mapped to the k-th full compared token. Both ranges include punctuation tokens.
Compared tokens beyond the length of the base range are discarded.

- Repro (a punctuation offset):
  `printf 'I saw red green things today\n' > s1.txt; printf 'I saw blue, yellow things today\n' > s2.txt; $C run s1.txt s2.txt`
  - Observed apparatus: `2 red] blue s2`, `3 green] , s2`. Synopsis: `green | ,`. The word "yellow" is gone and the reading "," is invented.
  - Expected: `green] yellow`, or a single `red green] blue, yellow` entry.
- Repro (a longer compared side):
  `printf 'I saw the red things today at noon\n' > u1.txt; printf 'I saw the very bright blue things today at noon\n' > u2.txt; $C run u1.txt u2.txt`
  - Observed with the default `baseAnchored` strategy: `3 red] very u2`. "bright blue" is lost from the graph, apparatus, synopsis and JSON.
  - `--strategy peer-msa` handles it correctly: `∅] very bright` plus `red] blue`.
- Fix direction: map comparable tokens only. Put any surplus compared tokens on an inserted node after the last base position, or keep the whole phrase on the first node.

### A3. HIGH — Translation lexicon never matches accented forms under the default normaliser
`TranslationLexicon.swift:44` (forms are only lower-cased) and `:61` (lookup is `normalizedForm.lowercased()`).

Token keys are already accent-stripped by `Normalizer.substantive` (for example `année` becomes `annee`). Lexicon
forms are not normalised, so any lexicon entry that contains a diacritic is never found. This includes the
documented example `année, year` (CLI help, ALGORITHMS §7d) and most French entries.

- Repro:
  `printf 'le phénomène était grand et rouge\n' > fr.txt; printf 'le phenomenon était grand et rouge\n' > en.txt; printf 'phénomène, phenomenon\n' > lex.txt; $C run fr.txt en.txt --format json --lexicon lex.txt`
  - Observed: a substitution `phénomène` → `phenomenon`. Writing the lexicon entry as `phenomene, phenomenon` gives 0 variants.
- `LexiconTests.testTrilingualVerneGraphPairsTheRightWords` still passes because the slots line up by position. It never checks that `année` or `phénomène` actually pivot.
- Fix direction: build the lexicon with the run's `Normalizer` (expose `normalize(word:)`, or take a normaliser in `init`/`parse`).

### A4. HIGH — Common punctuation is tokenised as substantive words: `'` quotes, `--` dashes, straight vs curly apostrophes
`Tokenizer.swift:233-236`. `isWordScalar` accepts `'`, `’` and `-` anywhere, not just inside a word.
`:195-196`. Only a run of exactly one `-` is classed as punctuation.

These marks therefore become WORD tokens and survive `dropPunctuation`. This breaks spec §2 ("intra-word `'` `’` `-`";
punctuation normalises to "").

- British single-quote style:
  `printf "'Hello,' she said to me.\n" > gb.txt; printf '"Hello," she said to me.\n' > us.txt; $C run gb.txt us.txt --format json`
  - Observed: a substitution `'Hello , '` → `Hello`.
  - Expected under substantive collation: no variant. GB and US editions differ exactly in this way.
- Apostrophe form: `don't` vs `don’t` gives a substantive substitution. The normaliser does not fold U+2019 to `'`.
- Dashes:
  - `He paused -- then` vs `He paused — then` gives a deletion of `--`.
  - `paused--then` vs `paused — then` gives the same result: an interior run of two or more hyphens is emitted as `.word` with normalised value `"--"`.

### A5. MEDIUM-HIGH — Characters outside the BMP (emoji, CJK Ext-B, math letters) are silently dropped
`Tokenizer.swift:160-161,181-183,209-211,226`. The tokenizer walks UTF-16 code units and calls `UnicodeScalar(UInt16)`,
which returns nil for each surrogate half. The "safety: never stall" branch then skips it.

Such characters never become tokens, and a word that contains one is split around it.

- Repro:
  - `alpha 𠀀𠀁 beta gamma` vs `alpha 𠀂𠀃 beta gamma`: **0 variants**.
  - `b𝐀c` vs `b𝐁c`: **0 variants**.
  - Emoji 😀 vs 😡 under `--diplomatic`: **0 variants**.
- Expected: a substitution in each case.
- Fix direction: iterate `text.unicodeScalars` while tracking UTF-16 offsets, or decode surrogate pairs.

### A6. MEDIUM — A recovered single-word move stays inside its deletion or insertion (reported twice)
`Variation.swift:340-356`. `remnant` rebuilds the range as `kept.min()…kept.max()`. When the carved word sits in the
middle of the range, the new range still covers it.

- Repro:
  - `a = 'one two three alpha zebra beta four five six seven eight nine'`
  - `b = 'one two three four five six zebra seven eight nine'`
  - Files: `t1/rc1.txt`, `t1/rc2.txt`.
  - Observed: a deletion "alpha zebra beta" (tokens 3..<6) **and** a transposition "zebra" (4..<5).
  - Expected: deletions "alpha" and "beta" (or one deletion that excludes zebra), plus the transposition.
- This is the most frequent overlap in the fuzzer (for example insertion `. -- a` 20..<23 overlapping transposition `--` 21..<22).
- Fix: split the remnant into contiguous runs.

### A7. MEDIUM — Moved blocks can grow into each other, so one passage is reported in two transpositions
`Transposition.swift:138-173`. Growth (`canTake`) checks only the spine. It does not check tokens already claimed by
another moved block. Coalescing at `:105-118` runs **before** growth, so blocks that later overlap are never merged.

- Repro (found by the fuzzer; files `t1/g1.txt`, `t1/g2.txt`):
  - `A = "sat — -- on well-known the -- ---\n ' sat , — . mat don't well-known ran the cat"`
  - `B = "sat — -- — well-known ran the . mat don't well-known mat the -- ---\n ' sat ran , cat"`
  - Observed: transposition base 15..<20 ("mat don't well - known") and transposition base 11..<22 ("sat , — . mat don't well - known ran the"). Base tokens 15–19 are in both.
- Fix direction: re-coalesce after growth, or stop growth at tokens that are already consumed.

### A8. MEDIUM — `no_collate` regions leak excluded text and shift page numbers (three separate defects)
1. **The two-comment form documented in the source does not work.** `Tokenizer.swift:117` documents
   `<!-- no_collate --> … <!-- /no_collate -->`. The close pattern (`:317`) accepts a bare `-->`, so the opener's own
   `-->` closes the region at once.
   - Repro: `<!-- no_collate -->\nPreface by the translator here\n<!-- /no_collate -->\nthe cat sat on the mat`
   - Observed: insertion "Preface by the translator here <! -- / no _ collate --".
2. **A page-break comment inside a region ends the region.** The page-break marker's own `-->` is the first close,
   and multi-page front matter almost always contains such markers.
   - Repro: `<!-- no_collate\nPreface page one\n<!-- page break -->\nPreface page two words\n-->\n…`
   - Observed: "Preface page two words --" is collated, and the body is cited from p.2.
3. **A `---` (or form-feed) page break inside a region moves the scanner backwards.** After the jump past the
   region (`:141-145`), the marker check at `:148-152` still fires because `i >= marker.lowerBound`, and it sets
   `i = marker.upperBound`, which is *inside* the region. The rest of the excluded text is then tokenised.
   - Repro: `<!-- no_collate\nfront matter alpha\n---\nmore front matter beta\n-->\nthe cat sat on the mat`
   - Observed: insertion "more front matter beta --" and page p.2.
   - This breaks the spec invariant "no token's range intersects a no-collate region" (§2).

### A9. MEDIUM — Under `--diplomatic` (the `Normalizer.diplomatic` normaliser plus `recordPunctuation`), every punctuation change is reported twice
`Variation.swift:427-442`. The overlay compares punctuation even when it is already comparable
(`dropPunctuation == false`), so the aligner has already reported it as a substitution.

- Repro: `Hello, world and friends` vs `Hello; world and friends` with `--diplomatic`.
- Observed: a substitution `,`→`;` **and** a variantSpelling `,`→`;`.
- Related: under `Normalizer.diplomatic`, `recordAccidentals` can never fire because keys equal surfaces. A case change
  (`End`/`end`) is a *substitution*, while `--accidentals` reports it as variantSpelling. The CLI help says
  diplomatic "also report[s] spelling/case accidentals".

### A10. MEDIUM — Translation-lexicon files with CRLF line endings fail silently
`TranslationLexicon.swift:81`. `text.split(separator: "\n")` splits on Swift *Characters*, and `"\r\n"` is a single
Character that is not equal to `"\n"`. A CRLF file is therefore read as one line, and forms run across the line
breaks. The file still parses to a non-empty lexicon, so the CLI's empty-lexicon check does not catch it.

- Repro (probe `lexcrlf`): `parse("annee, year\r\nmer, sea\r\n")` gives `pivot("sea") == "sea"` and `pivot("year") == "year"`. LF input gives `mer` and `annee`.
- Fix: split with `components(separatedBy: .newlines)`, or on `\.isNewline`.

### A11. MEDIUM — Page-break markers become text under `.linesPerPage` / `.throughNumbered`, and leak into a neighbouring punctuation run
1. `Tokenizer.swift:109-111`. Only `.markers` mode skips marker text.
   - Repro: `one two three\n<!-- page break -->\nfour five six` vs the same text without the marker, run with `--lines-per-page 30`.
   - Observed: a deletion "-- page break --".
   - So switching the citation model on marked-up witnesses creates false variants. This breaks the §2 invariant "page-break marker characters never become tokens".
2. A punctuation run that started before a marker swallows part of it.
   - Repro: `three.<!-- page break -->four` with `--diplomatic`.
   - Observed: the token `.<!` (reported as substitution *and* accidental, per A9).

### A12. LOW-MEDIUM — Base-anchored lift groups insertions by raw surface text, so substantively identical insertions split
`TokenGraph.swift:183,287-289`. The insertion key is `lowercased(surface reading)`. Punctuation is included, and
accent and spelling equivalents are not folded.

- Repro (files `t2/A..D.txt`): base "…walked home…"; B "back again"; C "back, again"; D "Back Again".
- Observed: two apparatus entries, `∅] back , again C` and `∅] back again B D`.
- `peerMSA` groups them as one entry.

### A13. LOW-MEDIUM — Move-edge "virtual end" id collides with a real node (base-anchored lift)
`TokenGraph.swift:192,297-301`. The end-of-text sentinel is `nodeReadings.count`, which equals the spine count. That is
exactly the id given to the first inserted node (`:225`). PeerMSA uses `nodes.count` instead (`PeerMSA.swift:319`).

- Repro (probe `edge`):
  - `A = "alpha … kappa lambda mu"`
  - `B = "kappa lambda mu alpha beta gamma INSERTED delta …"`
  - Observed: move edge `8 -> 12`, where node 12 is the inserted node "INSERTED". The viewer's graph (`HTMLExport` uses edges) gets a false edge.

### A14. LOW-MEDIUM — Pairwise apparatus positions mix base and compared coordinates
`Apparatus.swift:37`. For an insertion, `position = comparedTokenRange.lowerBound`. `plainText` then sorts by
position as if every entry were in base coordinates.

- Repro (probe `apppair`): base of 10 words; compared adds 8 words after "two" and an `X` at the end.
- Observed: `2 ∅] NEWA…` (the base anchor is 1) and `18 ∅] X B` (the base has only 10 tokens).
- Fix: use `insertionAnchor + 1`, or similar.

### A15. LOW-MEDIUM — Library API traps on edge-case input
- `CollationJSON.output(witnesses: [])` (and `outputString`) builds `1..<0` and traps with "Range requires lowerBound <= upperBound" (`CollationJSON.swift:150`). Probe `empty` reproduces it.
- `Synopsis.plainText(_, columnWidth: 0)` traps with "Can't take a prefix of negative length" (`Synopsis.swift:64`). Probe `synw` reproduces it.

### A16. LOW — Narrative text depends on locale, and one of its claims is false
- `CollationNarrative.swift:185-188`. `NumberFormatter()` uses `Locale.current`. Probe `narrbig` prints "1,200 points" for en_US, "1.200" for de_DE and "1 200" for fr_FR. The text and HTML exports are therefore not byte-stable across machines. Fix: set `f.locale = Locale(identifier: "en_US_POSIX")`.
- `:96-98`. The narrative says "Spelling and other accidental differences were checked and none were recorded" even when `recordAccidentals` and `recordPunctuation` were off, so nothing was checked. Probe `narr` reproduces it; the default CLI text output shows it too.

### A17. LOW — Citation for a reading that crosses a page is inverted or wrong
`Variation.swift:52-61`, `:523-535`. `TextLocation` has no `endPage`, so a span that crosses a page break renders as a
backwards line range.

- Repro (files `t1/xp1.txt`, `t1/xp2.txt`): a deletion running from p.1 line 3 to p.2 line 1.
- Observed: `"p.1 · lines 3–1 · words 1…3"`.

### A18. LOW — Other tokenisation edge cases
- **YAML front matter in markdown** (`---\ntitle: X\n---`): both `---` lines count as page breaks, the front matter is collated (a deletion "title : X"), and the body is cited from p.2 (`Tokenizer.swift:82`). Markdown is the declared host format.
- **CR-only line endings** (classic Mac) are not treated as newlines. All lines merge, so citations become "line 1 · word 6" and paragraphs are never detected (`:165`).
- **`.explicit` page offsets**:
  - Duplicate offsets create empty pages (offsets `[0,4,4,9]` put "two" on p.2).
  - An offset inside a word is applied after the word.
  - Neither case is validated.
- **BOM**: a leading U+FEFF becomes a punctuation token. Under the diplomatic normaliser, the library reports a deletion of the invisible BOM (probe `bom`). The CLI loader appears to strip it.

---

## (B) Suspected bugs (unconfirmed, with reasoning)

- **B1. Region variations can straddle a consumed (moved) block.**
  - `classifyRegion` (`Variation.swift:403-404`) builds `fullRange(first…last)` from the pending comparable indices.
  - `appendRegion` skips consumed tokens, so two deletions on either side of a moved block, with no match between them, would produce one range (and reading) that includes the moved text.
  - In the lift, that range would then mark the moved tokens `∅` (`TokenGraph.swift:156-161`).
  - Not reproduced: my attempts (`t1/sp3/sp4`) always had an intervening anchor match. The fuzz overlaps I saw were all explained by A6 and A7.
- **B2. Non-determinism with duplicate sigla.** The engine never checks that witness ids are unique.
  - With `[A, B, B]`, both "B" witnesses collapse into one id. Probe `dup` shows node readings `cow:{B}`, `dog:{B}`.
  - `Synopsis.table` then fills `readings[s] = reading` while iterating a Dictionary (`Synopsis.swift:46-48`), so the cell shown depends on hash order.
  - `TokenGraph.build(reusing:)` matches precomputed results by id (`:142`) and would reuse the first B's result for the second.
  - Recommendation: reject duplicates with a precondition or an error.
- **B3. `Apparatus.entries(from: graph)` lemma fallback is non-deterministic** (`Apparatus.swift:56`). `readings.max { … }` over a Dictionary has no tie-break. It is unreachable today because every spine node carries the base reading, but it fires for any hand-built `VariantGraph`.
- **B4. `Alignment.banded` flags `hitEdge` at the real matrix border.** When `lo(i)` is clamped to 0 or `hi(i)` to m, a path along the matrix edge (for example deletions at the start) counts as touching the band edge (`Alignment.swift:184`). This forces needless widening up to `maxBand`. It costs time only; the result is unaffected.
- **B5. Unvalidated parameters.**
  - `anchorLength` is not capped. `adaptiveAnchors` loops from `startN` down to 2, rebuilding the n-gram maps with n-token joined strings each time, so `anchorLength: 1000` on a novel is effectively unbounded work.
  - `AlignmentScores` are not validated (a positive gap, or match ≤ mismatch, gives meaningless alignments). `i * scores.gap` can overflow for extreme values.
- **B6. Peer-MSA insertion placement after a transposed block.** `lastConsensusIdx` (`PeerMSA.swift:124-136`) only tracks region ops. An insertion right after a moved block is anchored to the last *region* slot, which can be before the moved slots in consensus order. Not reproduced.

---

## (C) Dead or vestigial code

| Item | Location | Note |
|---|---|---|
| `Normalizer.foldWhitespace` | `Tokenizer.swift:14,29,35` | Never read. The comment admits it is "always effectively true". Remove it, or make it real. |
| `Transposition.longestIncreasingByB` | `Transposition.swift:682-703` | Only tests use it. The doc on `align` (`:46-49`) says "Without pages, plain LIS is used", which is false: the O(k²) weighted DP always runs. |
| `displacementIsPlausible(_:spine:…)` `spine` parameter | `:531-532` | `_ = spine`. A parameter kept only for its signature. |
| `remnant(_:side:…)` `side` parameter | `Variation.swift:340-341, 377, 380` | `_ = side`. Callers pass `base[0]` / `compared[0]` for nothing. |
| `pairByExpandingWindow` multi-candidate search | `:564-615` | The only production caller (`Variation.swift:256`) passes exactly **one** deletion position and **one** insertion position. The sort, the ambiguity ratio and the `contested` scan are never used in production; in practice the function is two thresholds (`≤ moveTolerance` ⇒ near, `≤ maxMoveTokens` ⇒ far). The spec (§5.6, §9.8) describes a search that the engine never actually runs. |
| `Collation.legacyVariantGraph` | `Collation.swift:221-222, 236-347` | Reached only if `TokenGraph.build` returns nil, which only happens for an empty set, and that is already handled at `:208`. About 110 lines of unreachable duplicate logic (it shares bug A2). |
| `CollationStrategy.isAvailable` / `contextualDefault` fallback | `Collation.swift:46-51, 67` | Always true; the fallback branch is dead. |
| `TokenGraph.nearestNodeAtOrAfter` 4096 cap | `TokenGraph.swift:299` | A magic constant with no rationale. Also, the loop body checks `map[p]` after incrementing, so `map[basePos]` is only examined in the return. |
| Duplicate apparatus-substitution fold logic | `Collation.swift:278-293` ≈ `TokenGraph.swift:163-177` | Same algorithm, same bug (A2). |
| Duplicate diagonal formula | `Transposition.swift:513-517` vs `:534` vs `:574` | Three copies of `round(d·|B|/|A|)`. |

---

## (D) Spec ↔ code mismatches

1. **§2 word definition.** The spec says "intra-word `'` `’` `-`". The code accepts them anywhere, and hyphen runs of length ≥ 2 become WORD tokens (A4).
2. **§2 invariants are violated:**
   - "Page-break marker characters never become tokens" (A11).
   - "No token's range intersects a no-collate region" (A8.3).
3. **§2 no-collate syntax is ambiguous.** The spec lists both "the comment's own `-->`" and `<!-- /no_collate -->` as a CLOSE. The source comment (`Tokenizer.swift:117`) says the canonical syntax is `<!-- no_collate --> … <!-- /no_collate -->`, which cannot work under the "first `-->`" rule (A8.1).
4. **§3 "in the full engine [NW] runs only on small inter-anchor regions".** Not guaranteed. `appendRegion` and `innerAlignment` run unbounded full NW. Only the no-anchor path is bounded (F2).
5. **§5.6 / §6.1 / §10 units.**
   - `localMoveTokens` and the §6.1 deviation are documented in *comparable tokens*.
   - The code computes them on **full-token** indices and counts, punctuation included (`Variation.swift:256-263`: `delTok`/`insTok` are full indices, `aCount: base.count`).
   - The anchor path uses comparable indices (`aMap.count`).
   - So the "shared" `moveTolerance` (doc at `Transposition.swift:361-363`: "so they judge … identically") is computed on different scales by the two paths.
6. **§6.1 says `key = normalize(surface)`.** The code uses `lexicon.pivot(normalized.lowercased())` (`Variation.swift:205`). Under the diplomatic (case-sensitive) normaliser, recovery pairs `The`/`the`, which the aligner treats as different keys. That contradicts the code's own comment ("on the same key the ALIGNER used"). `Collation.comparable` pivots without lower-casing.
7. **§9.6 vs §6.1 on confidence.** §9.6 says "`certain` iff globally unique in both". §6.1 and the code also require `near` (`Variation.swift:261`).
8. **§7b substitution mapping** ("same offset") is underspecified: it does not say whether offsets count full or comparable tokens. As implemented it causes A2.
9. **Calibration numbers disagree.**
   - `Transposition.swift:455-462` says "**48 → 5** false positives … RESIDUAL (5 survivors)".
   - ALGORITHMS §5.6 and PAPER_NOTES §4.5.2 say "**48 → 11**".
   - `:498` gives Calamus as "len 22"; elsewhere it is "19|84".
10. **§5.4 "never onto a spine token".** This is the only constraint the spec states. Neither spec nor code forbids growing into another moved block, or a moved pin overlapping a spine pin in B (A1, A7).
11. **§7 location.** The spec uses `charFrom = first.charFrom`, `charTo = last.charTo`; the code uses min/max, which is equivalent on valid input. There is no page-crossing representation (A17).
12. **`Transposition.align` doc comment** says plain LIS is used without pages; the code always runs the O(k²) weighted DP (C).

---

## (E) API and design improvements for 1.0

1. **Collapse the options into a value type.** `collate`, `variantGraph`, `variantGraphWithTokens`, `TokenGraph.build`, `buildPeerMSA` and `CollationJSON.output/outputString` (×2) each repeat 6–9 defaulted parameters, and they are already inconsistent:
   - `collate` uses `AlignmentScores()` where others use `.prose`.
   - The parameter order differs.
   - `CollationJSON.output` has no `anchorLength`.
   - Recommendation: a `CollationOptions` struct (normalizer, pagination, scores, anchorLength, lexicon, overlays, strategy).
2. **Use errors instead of traps and silent garbage.** Validate input with `throws` (or a `precondition` with a clear message):
   - empty witness list (A15)
   - duplicate sigla (B2)
   - `columnWidth < 2`
   - out-of-range or unsorted `.explicit` offsets
   - `anchorLength` bounds
   - invalid `AlignmentScores`
   - a `reusing:` result produced under different options (today this is an unchecked contract; `TokenGraph.swift:93-99`)
3. **Shrink the public surface.** These look accidentally public, or need deliberate design before 1.0:
   - `AlignOp`, `AnchorPin`, `SegmentKind`, `SegmentAlignment`, `Alignment.needlemanWunsch`, `VariationClassifier.classify` (its `aMap`/`bMap` arguments are internal plumbing).
   - `TokenGraph.build` (public through `public extension`).
   - The mutable `public var baseComparablePositions` / `insertedAnchorByNodeID`. These are excluded from `==`, and the first is misnamed: it holds *full*-token positions (`TokenGraph.swift:69`).
   - `CollationStrategy.isAvailable`.
   - The `Samples` fixtures (`Samples.sixEditions`, `gbUSNormalizer`).
4. **Things that should be public but are not.** Consumers need these:
   - `Normalizer.normalize(word:)`, to normalise lexicon or user forms (A3).
   - Public memberwise inits for result types (`CollationResult`, DTOs), for testing and `reusing:`.
   - `Sendable` on all value types. They are pure values, and Swift 6 strict concurrency will require it.
   - `Codable` on the model types, or a documented guarantee that the DTOs are the only wire form.
5. **Sentinel strings.**
   - `"∅"` is used both as an omission marker and as a dictionary key next to real readings. Under `.diplomatic`, a witness that literally contains `∅` collides with it.
   - Use an enum reading (`.omitted` / `.text(String)`) in `GraphNode`, `TokenGraphReading`, `ApparatusEntry` and `SynopticRow`. Map it to "∅" only in the renderers and the JSON.
6. **Variation order.** `Transposition.align` emits **all transpositions first**, then the regions (`:201-204`). As a result, `CollationResult.variations` and `Report.located` numbering are not in text order (see the `t1/st3`/`st4` output: transposition 7..<12 is listed before the insertion at compared index 2). Sort by base position (falling back to the insertion anchor) before returning, or document the order.
7. **Readings join surfaces with spaces** ("blue , yellow", "'Hello , '"). The data to slice the original text is already there (`TextLocation.charRange`). Recommendation: expose an original-text reading, or join using source gaps.
8. **Locations.** Add `endPage` to `TextLocation` (A17).
9. **Normaliser defaults.**
   - Fold `’`/`'` and typographic quotes.
   - Treat leading/trailing `'` and `-` runs as punctuation (A4).
   - Consider Unicode word segmentation (the porting checklist already recommends it; it would also address the CJK case — a whole CJK sentence is one token today, the known open B6 item).
10. **Diplomatic semantics.** `Normalizer.diplomatic` together with `recordAccidentals` and `recordPunctuation` produces duplicates (A9), and the accidentals option is a no-op under it. Define one coherent model:
    - substantive = the folded keys;
    - every folded difference is reported as an accidental;
    - the diplomatic preset = substantive keys plus all overlays.
11. **Make `Apparatus.entries(from: CollationResult)` use `insertionAnchor`** for insertion positions (A14). `ApparatusEntry.type` for graph nodes is always `.substitution`, even when the only variant is `∅` (an omission).
12. **Error-free degradation is good, but silent.** The engine never tells callers when it fell back to banded or approximate NW (`maxBand` cap), or dropped gated moves. A `diagnostics` field on `CollationResult` (fallbacks taken, moves gated, band used) would help scholars trust the output.

---

## (F) Performance

All timings are release builds on Apple silicon (probe `perf`).

- **F1. `TokenGraph.projectedVariantGraph` is O(N²)** — `nodes.first(where: { $0.id == nodeID })` runs inside the spine loop (`TokenGraph.swift:318`).
  - Measured: **0.86 s of 1.05 s** of the whole graph build on a 73k-node novel pair (Journey, near-identical), and 0.83 s of 1.09 s on the independent malleson↔ward pair.
  - Node ids are 0..<n, in order, by construction, so `nodes[nodeID]` (or a prebuilt index) makes this linear.
  - This is the biggest easy win. It roughly quadruples per doubling of length, so the "three novels" run pays it heavily.
- **F2. `Transposition.maxWeightIncreasingByB` is O(P²)** in anchors (`:709-722`).
  - On near-identical editions (every 400th word changed), `collate` time was 0.82 s, 2.44 s and 4.86 s for 1×, 2× and 3× the novel length — superlinear.
  - `sample` attributes nearly all of it to `Transposition.swift:716-719`.
  - A max-weight LIS can be done in O(P log P) with a Fenwick tree or segment tree over compressed B ranks (keeping the "earliest" tie-break by storing (weight, −index)). This matters most for the main use case: successive editions of one work, which yield the most anchors.
- **F3. Region NW is unbounded once *any* anchor exists.**
  - `appendRegion` (`:336`) and `innerAlignment` (`:307`) call full `needlemanWunsch`, which allocates `[[Int]]` (n+1)×(m+1). Only the anchor-free path goes through `boundedNW`.
  - Repro (`perf/lowA16000` vs `lowB16000`): 32k-token low-diversity texts, identical except that each contains one shared unique trigram.
    - Without the trigram: banded, **1.2 s / 350 MB**.
    - With it: **4.7 s / 2.26 GB RSS**. Memory grows quadratically, so twice the size would need about 9 GB.
  - Sparse anchors are realistic: independent translations, or a witness with a long added or rewritten section.
  - Fix: route `appendRegion` and `innerAlignment` through `boundedNW`. Separately, a flat `[Int]` buffer (or Hirschberg / two-row scoring plus a traceback bit-matrix) would cut constant factors and the 8-byte-per-cell cost.
- **F4. `ngramPositions` builds a joined `String` for every n-gram** (`:669-677`), and `adaptiveAnchors` may do this up to `startN−1` times. Hash n-grams with a rolling hash over interned token ids (map each key to an `Int` once per witness). This also speeds up NW, which compares `String`s per cell.
- **F5. `PeerMSA` splices with `spineOrder.insert(contentsOf:at:)`** once per insertion anchor (`PeerMSA.swift:238-250`), which is O(S) each, so O(S·groups) per witness. Rebuilding the order in one merge pass per witness would make it linear. It is minor at N=2 (peer was 1.38 s on the novel pair) but grows with N and with how far the witnesses diverge.
- **F6. Small items.**
  - `CollationResult`'s count properties each re-filter the whole array; `CollationJSON.dto` calls all five.
  - `CollationNarrative.fmt` allocates a `NumberFormatter` per number.
  - `Tokenizer` does per-UTF-16-unit `CharacterSet` lookups and `NSString.substring` calls.
  - None of these matter next to F1–F3.
