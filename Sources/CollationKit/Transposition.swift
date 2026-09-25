import Foundation

// MARK: - Transposition-aware alignment (stage 2 — the non-diff part)
//
// A plain global alignment treats a MOVED passage as "deleted here" + "inserted there" — exactly the
// failure mode the original engine specification calls out (changes across pages must not read as simplistic diff churn). This
// layer recovers moves:
//
//   1. Find ANCHORS — n-grams that occur EXACTLY ONCE in each witness (unique, unambiguous landmarks).
//      This is the "patience" idea (as in patience-diff): unique common subsequence points pin the texts.
//   2. The anchors common to both witnesses, taken in A's order, give a sequence of (posA, posB) pins.
//      A pin whose B-order is OUT of step with its A-order marks a block that moved → a TRANSPOSITION.
//   3. Between consecutive in-order anchors, align the gap regions with Needleman–Wunsch (this is where
//      ordinary insert/delete/substitute within a stable passage is resolved).
//
// The output is a `SegmentAlignment`: a list of aligned segments, each either an in-order region (with its
// fine-grained `AlignOp`s) or a transposed block (matched A-range ↔ B-range that appear in different
// positions). The classifier turns this into typed `Variation`s.

public struct AnchorPin: Equatable {
    public let aStart: Int   // token index in A where the anchor n-gram begins
    public let bStart: Int   // token index in B
    public let length: Int   // n-gram length (in comparable tokens)
}

public enum SegmentKind: Equatable {
    case region(ops: [AlignOp])                       // an in-order region aligned token-by-token
    /// A block that MOVED. `aRange`/`bRange` are its spans in each witness. `innerOps` is the alignment of
    /// the moved block against itself across the two witnesses (in original token indices), so edits made
    /// *inside* the move — "they were tired" → "they were weary" — are recovered and attributed to the
    /// moved passage, rather than leaking out as delete+insert churn around it. For a pure move (no internal
    /// edit) `innerOps` is all `.match`.
    case transposition(aRange: Range<Int>, bRange: Range<Int>, innerOps: [AlignOp])
}

public struct SegmentAlignment: Equatable {
    public let segments: [SegmentKind]
}

public enum Transposition {

    /// Align two comparable-token key sequences with transposition detection. `n` is the anchor n-gram
    /// length (3 is a good default for prose — long enough to be distinctive, short enough to survive small
    /// edits around it).
    ///
    /// `aPages`/`bPages` (optional) give the page index of each comparable token. When supplied, the stable
    /// "spine" is chosen with a PAGE-AWARE tie-break: among equally-long candidate spines, the one made of
    /// **page-stable** anchors (same page in both witnesses) is preferred, so the block reported as *moved*
    /// is the one that actually changed page. Without pages, plain LIS is used (count only).
    public static func align(_ a: [String], _ b: [String], anchorLength n: Int = 3,
                             scores: AlignmentScores = AlignmentScores(),
                             aPages: [Int]? = nil, bPages: [Int]? = nil) -> SegmentAlignment {
        // ADAPTIVE ANCHORING (lexical-diversity mitigation, DEVELOPMENT_LOG 2026-06-27): the anchor pass
        // chunks the O(n·m) matrix only when unique shared n-grams exist. Low-diversity text (few unique
        // n-grams) finds none and degrades to one huge NW. Before giving up, retry with successively SHORTER
        // n-grams (down to a floor of 2): shorter grams are likelier to be unique-in-common, so a repetitive
        // witness still gets *some* anchoring rather than a full matrix. We accept the longest n that yields
        // a useful anchor density.
        let anchors = adaptiveAnchors(a, b, startN: n)
        guard !anchors.isEmpty else {
            // Still no reliable landmarks → fall back to NW, but BAND it so a pathological low-diversity pair
            // can't cost O(n·m) on a multi-thousand-token input (the worst case the characterization names).
            return SegmentAlignment(segments: [.region(ops: boundedNW(a, b, scores: scores))])
        }

        // Order anchors by position in A. A maximum-weight strictly-increasing subsequence (by B position)
        // is the "stable" spine we keep in order; anchors NOT on it correspond to moved material. Weighting
        // page-stable anchors above page-crossing ones makes the MOVED block the one that crossed a page,
        // breaking the otherwise-arbitrary symmetry of a two-block swap. (DEVELOPMENT_LOG 2026-06-27.)
        let byA = anchors.sorted { $0.aStart < $1.aStart }
        let weights = byA.map { pin -> Int in
            // Base weight 1 per anchor (so longer spines still win); +1 bonus when the anchor stays on the
            // same page in both witnesses, so a tie in length is decided in favour of keeping page-stable
            // anchors (⇒ the page-crossing block is the one left off the spine and reported as the move).
            guard let aPages, let bPages,
                  pin.aStart < aPages.count, pin.bStart < bPages.count else { return 1 }
            return aPages[pin.aStart] == bPages[pin.bStart] ? 2 : 1
        }
        let stableIdx = maxWeightIncreasingByB(byA, weights: weights)
        let stableSet = Set(stableIdx)

        // A transposed anchor's tokens occupy spans in BOTH witnesses. Those spans must be EXCLUDED from the
        // surrounding in-order region alignment — otherwise the moved sentence is reported a SECOND time as
        // an insertion (where it landed) plus a deletion (where it used to be), i.e. the very diff churn this
        // layer exists to avoid. Mask them out first, then align regions over only the unconsumed tokens.
        //
        // DISPLACEMENT GATE (fixes the full-novel "wild transposition" defect): a unique-in-both n-gram is only
        // an ANCHOR by coincidence when the two witnesses are long and independent — e.g. two separate
        // translations of a novel share a rare phrase ("of the Aleutian") at positions hundreds of thousands of
        // tokens apart. Accepted as a move, it (a) reports a nonsense transposition spanning most of the book and
        // (b) corrupts the surrounding alignment. A GENUINE move stays local: the rest of the text is co-linear,
        // so a moved block sits near the position the stable spine predicts for it. We therefore drop any
        // off-spine anchor whose B position is implausibly far from the spine-interpolated expectation; its
        // tokens fall back into ordinary region alignment (where a coincidental phrase is correctly a
        // substitution, not a move). See DEVELOPMENT_LOG 2026-07-08.
        let stablePinsByA = stableIdx.map { byA[$0] }
        let movedPins = byA.enumerated()
            .filter { !stableSet.contains($0.offset) }
            .map { $0.element }
            .filter { displacementIsPlausible($0, spine: stablePinsByA, aCount: a.count, bCount: b.count) }
        // Coalesce moved anchors that are contiguous (or adjacent) in BOTH witnesses into one block, so a
        // moved sentence reads as a single transposition rather than several length-n fragments. Anchors are
        // already in A-order and non-overlapping.
        var transpositions: [(aRange: Range<Int>, bRange: Range<Int>)] = []
        for pin in movedPins {
            let aR = pin.aStart..<(pin.aStart + pin.length)
            let bR = pin.bStart..<(pin.bStart + pin.length)
            if var last = transpositions.last,
               aR.lowerBound <= last.aRange.upperBound,         // contiguous/adjacent in A
               bR.lowerBound <= last.bRange.upperBound,         // …and in B
               bR.lowerBound >= last.bRange.lowerBound {        // …same direction (still a single move)
                last.aRange = last.aRange.lowerBound..<max(last.aRange.upperBound, aR.upperBound)
                last.bRange = last.bRange.lowerBound..<max(last.bRange.upperBound, bR.upperBound)
                transpositions[transpositions.count - 1] = last
            } else {
                transpositions.append((aR, bR))
            }
        }
        // Tokens belonging to the stable spine — a block must never grow into these (they're the in-order
        // backbone, not part of any move).
        var onSpine = [Bool](repeating: false, count: max(a.count, b.count))
        var onSpineB = [Bool](repeating: false, count: b.count)
        for idx in stableIdx {
            let pin = byA[idx]
            for k in 0..<pin.length {
                if pin.aStart + k < onSpine.count { onSpine[pin.aStart + k] = true }
                if pin.bStart + k < onSpineB.count { onSpineB[pin.bStart + k] = true }
            }
        }

        // Grow each moved block to match the real passage boundary. Two growth modes:
        //   1. Absorb identical tokens immediately adjacent (a repeated word like "…one by one").
        //   2. BRIDGE a bounded run of MISMATCHED tokens (recursive anchoring) when identical content resumes
        //      just past it on both sides — this pulls an edit made INSIDE a moved sentence ("they were
        //      *tired*" → "*weary*") into the transposition, instead of leaving the head as delete+insert
        //      churn outside it. The bridged tokens become internal edits, recovered by `innerAlignment`.
        let bridgeGap = 4   // max mismatched tokens to bridge on one side (keeps unrelated text out)
        for i in transpositions.indices {
            var (aR, bR) = transpositions[i]

            func canTake(_ ai: Int, _ bi: Int) -> Bool {
                ai >= 0 && bi >= 0 && ai < a.count && bi < b.count && !onSpine[ai] && !onSpineB[bi]
            }
            // Extend backward: identical step, else bridge up to `bridgeGap` mismatches to a resync point.
            var changed = true
            while changed {
                changed = false
                let la = aR.lowerBound - 1, lb = bR.lowerBound - 1
                if canTake(la, lb) {
                    if a[la] == b[lb] {                                  // mode 1: identical
                        aR = la..<aR.upperBound; bR = lb..<bR.upperBound; changed = true
                    } else if let (na, nb) = resync(a, b, beforeA: la, beforeB: lb,
                                                    gap: bridgeGap, onSpine: onSpine, onSpineB: onSpineB) {
                        aR = na..<aR.upperBound; bR = nb..<bR.upperBound; changed = true   // mode 2: bridge
                    }
                }
            }
            // Extend forward: identical step, else bridge to a resync point.
            changed = true
            while changed {
                changed = false
                let ua = aR.upperBound, ub = bR.upperBound
                if canTake(ua, ub) {
                    if a[ua] == b[ub] {
                        aR = aR.lowerBound..<(ua + 1); bR = bR.lowerBound..<(ub + 1); changed = true
                    } else if let (na, nb) = resyncForward(a, b, fromA: ua, fromB: ub,
                                                           gap: bridgeGap, onSpine: onSpine, onSpineB: onSpineB) {
                        aR = aR.lowerBound..<na; bR = bR.lowerBound..<nb; changed = true
                    }
                }
            }
            transpositions[i] = (aR, bR)
        }

        // DISTINCTIVENESS GATE (post-growth): now that each block has absorbed its surrounding identical run, we
        // know its true LENGTH — and can reject a SHORT block that "moved" implausibly far. A short common-word
        // n-gram is unique-in-both by coincidence, not by relocation (the ≈90 Verne phantoms: "we ought always
        // to", "I tell you", "in cast-iron"); a genuine long-range move is a long distinctive passage. Drop any
        // block whose diagonal deviation exceeds the distinctiveness-scaled tolerance for its length. Dropped
        // blocks are simply not added to `consumedA/B` below, so their tokens fall back into ordinary region
        // alignment (a coincidental phrase becomes a substitution/insertion/deletion — never a fabricated move).
        // See `anchorMoveTolerance` for the corpus calibration.
        transpositions = transpositions.filter { t in
            anchorBlockIsPlausible(aStart: t.aRange.lowerBound, bStart: t.bRange.lowerBound,
                                   blockLength: t.aRange.count, aCount: a.count, bCount: b.count)
        }

        var consumedA = [Bool](repeating: false, count: a.count)
        var consumedB = [Bool](repeating: false, count: b.count)
        for t in transpositions {
            for k in t.aRange { consumedA[k] = true }
            for k in t.bRange { consumedB[k] = true }
        }

        var segments: [SegmentKind] = []
        // Emit the moved blocks (in A order) first; the classifier reports them as transpositions. Each
        // moved block is RECURSIVELY aligned against itself across the two witnesses (`innerOps`), so edits
        // made inside the move are recovered as part of the transposition rather than as churn around it. A
        // transposed block is internally order-preserving (it moved as a unit), so a single NW over the two
        // sub-spans is the right inner alignment; ops are mapped back to original token indices.
        for t in transpositions {
            let innerOps = innerAlignment(a, b, aRange: t.aRange, bRange: t.bRange, scores: scores)
            segments.append(.transposition(aRange: t.aRange, bRange: t.bRange, innerOps: innerOps))
        }

        // Walk the stable anchors in order, aligning each gap region over the UNCONSUMED tokens between them.
        let stablePins = stableIdx.map { byA[$0] }
        var prevAEnd = 0, prevBEnd = 0
        for pin in stablePins {
            appendRegion(&segments, a: a, b: b, aFrom: prevAEnd, aTo: pin.aStart, bFrom: prevBEnd, bTo: pin.bStart,
                         consumedA: consumedA, consumedB: consumedB, scores: scores)
            // The anchor itself is a run of matches.
            var anchorOps: [AlignOp] = []
            for k in 0..<pin.length { anchorOps.append(.match(a: pin.aStart + k, b: pin.bStart + k)) }
            segments.append(.region(ops: anchorOps))
            prevAEnd = pin.aStart + pin.length
            prevBEnd = pin.bStart + pin.length
        }
        // Tail region after the last stable anchor.
        appendRegion(&segments, a: a, b: b, aFrom: prevAEnd, aTo: a.count, bFrom: prevBEnd, bTo: b.count,
                     consumedA: consumedA, consumedB: consumedB, scores: scores)
        return SegmentAlignment(segments: segments)
    }

    /// Backward bridge: tokens `a[la]` / `b[lb]` (just before a block) MISMATCH. Look back up to `gap`
    /// tokens on each side for an identical "resync" pair `a[na']==b[nb']` (na' < la, nb' < lb), then return
    /// the new lower bounds `(na', nb')` so the block absorbs the mismatched run as an internal edit. Returns
    /// nil if no resync within the gap, or if any token in the bridged span is on the spine. Requires the
    /// counts removed from each side to be roughly balanced (so we bridge an edit, not unrelated text).
    static func resync(_ a: [String], _ b: [String], beforeA la: Int, beforeB lb: Int,
                       gap: Int, onSpine: [Bool], onSpineB: [Bool]) -> (Int, Int)? {
        var bestPenalty = Int.max
        var best: (Int, Int)? = nil
        var ai = la
        var stepsA = 0
        while ai >= 0 && stepsA <= gap {
            if onSpine[ai] { break }
            var bi = lb
            var stepsB = 0
            while bi >= 0 && stepsB <= gap {
                if onSpineB[bi] { break }
                if a[ai] == b[bi] {
                    let penalty = stepsA + stepsB + abs(stepsA - stepsB)   // prefer near, balanced resyncs
                    if penalty < bestPenalty { bestPenalty = penalty; best = (ai, bi) }
                }
                bi -= 1; stepsB += 1
            }
            ai -= 1; stepsA += 1
        }
        return best
    }

    /// Forward counterpart of `resync`: from the mismatching pair at `(ua, ub)` just past a block, find an
    /// identical resync pair within `gap` and return the new UPPER bounds (exclusive) so the block extends
    /// past the bridged edit.
    static func resyncForward(_ a: [String], _ b: [String], fromA ua: Int, fromB ub: Int,
                              gap: Int, onSpine: [Bool], onSpineB: [Bool]) -> (Int, Int)? {
        var bestPenalty = Int.max
        var best: (Int, Int)? = nil
        var ai = ua, stepsA = 0
        while ai < a.count && stepsA <= gap {
            if onSpine[ai] { break }
            var bi = ub, stepsB = 0
            while bi < b.count && stepsB <= gap {
                if onSpineB[bi] { break }
                if a[ai] == b[bi] {
                    let penalty = stepsA + stepsB + abs(stepsA - stepsB)
                    if penalty < bestPenalty { bestPenalty = penalty; best = (ai + 1, bi + 1) }
                }
                bi += 1; stepsB += 1
            }
            ai += 1; stepsA += 1
        }
        return best
    }

    /// The no-anchor fallback, bounded so a pathological low-diversity pair can't cost O(n·m). Below
    /// `fullNWCellCap` cells it is exact Needleman–Wunsch; above it it uses a BANDED NW (only the DP cells
    /// within a widening band of the diagonal), which is `O((n+m)·band)` and — unlike the old positional
    /// chunker — stays *globally optimal* whenever the witnesses are loosely co-linear (no chunk seams, so no
    /// spurious indels where cuts fell). The band auto-widens while the optimal path rides its edge, so it
    /// converges to full NW for drifting input while staying cheap when drift is small. Engaged only when
    /// adaptive anchoring already found nothing — the cost the lexical-diversity characterization warns about.
    static let fullNWCellCap = 1_000_000     // ~1000×1000; above this, band
    static let initialBand = 64              // tolerates ±64 tokens of drift before widening
    // Cap the band so the O((n+m)·band) bound is real. On genuinely structureless input (a tiny lexicon) the
    // optimal path rides the edge everywhere — not because the true alignment is clipped, but because every
    // path scores alike — so widening would chase to O(n·m). We cap low and accept an approximate alignment
    // there (there is no meaningful "correct" alignment of near-random tokens to lose).
    static let maxBand = 256
    static func boundedNW(_ a: [String], _ b: [String], scores: AlignmentScores) -> [AlignOp] {
        if a.count * b.count <= fullNWCellCap {
            return Alignment.needlemanWunsch(a, b, scores: scores)
        }
        return Alignment.bandedAutoWidening(a, b, initialBand: initialBand, maxBand: maxBand, scores: scores)
    }

    /// Align a moved block against itself across the two witnesses, to recover edits made INSIDE the move.
    /// The block is internally order-preserving, so a single Needleman–Wunsch over the two sub-spans suffices;
    /// ops are offset back to the original token indices. (This is the "recursive anchoring" step — the move
    /// is collated as its own little pair, so "they were tired" → "they were weary" surfaces as a
    /// substitution within the transposition rather than as delete+insert churn outside it.)
    static func innerAlignment(_ a: [String], _ b: [String],
                               aRange: Range<Int>, bRange: Range<Int>,
                               scores: AlignmentScores) -> [AlignOp] {
        let aSub = Array(a[aRange]), bSub = Array(b[bRange])
        return Alignment.needlemanWunsch(aSub, bSub, scores: scores).map { op in
            switch op {
            case .match(let i, let j):      return .match(a: aRange.lowerBound + i, b: bRange.lowerBound + j)
            case .substitute(let i, let j): return .substitute(a: aRange.lowerBound + i, b: bRange.lowerBound + j)
            case .delete(let i):            return .delete(a: aRange.lowerBound + i)
            case .insert(let j):            return .insert(b: bRange.lowerBound + j)
            }
        }
    }

    /// Align one gap region, but only over the tokens NOT already consumed by a transposition. Filtered
    /// sub-sequences are aligned with NW, then the ops are mapped back to the original token indices so the
    /// classifier still references real positions.
    private static func appendRegion(_ segments: inout [SegmentKind], a: [String], b: [String],
                                     aFrom: Int, aTo: Int, bFrom: Int, bTo: Int,
                                     consumedA: [Bool], consumedB: [Bool], scores: AlignmentScores) {
        // Take BOUNDS, not pre-built ranges, and clamp here — because two spine anchors can overlap in B (B
        // positions aren't monotonic in A-order; anchors are de-overlapped in A only), so `bFrom` can exceed
        // `bTo`. Constructing `bFrom..<bTo` at the call site would trap (`Range requires lowerBound <=
        // upperBound`) BEFORE this function runs; building the range here, clamped to empty, avoids that. An
        // overlap simply means there's no gap region between the anchors. (Found via the Verne full-novel
        // corpus: large, repetitive real translations produce B-overlapping unique anchors.)
        let aSpan = min(aFrom, aTo)..<aTo
        let bSpan = min(bFrom, bTo)..<bTo
        var aKeys: [String] = [], aIdx: [Int] = []
        for k in aSpan where !consumedA[k] { aKeys.append(a[k]); aIdx.append(k) }
        var bKeys: [String] = [], bIdx: [Int] = []
        for k in bSpan where !consumedB[k] { bKeys.append(b[k]); bIdx.append(k) }
        guard !aKeys.isEmpty || !bKeys.isEmpty else { return }
        let ops = Alignment.needlemanWunsch(aKeys, bKeys, scores: scores).map { op -> AlignOp in
            switch op {
            case .match(let i, let j):      return .match(a: aIdx[i], b: bIdx[j])
            case .substitute(let i, let j): return .substitute(a: aIdx[i], b: bIdx[j])
            case .delete(let i):            return .delete(a: aIdx[i])
            case .insert(let j):            return .insert(b: bIdx[j])
            }
        }
        segments.append(.region(ops: ops))
    }

    // MARK: displacement gate

    /// The maximum plausible move distance as a FRACTION of the witness length. A genuine transposition is
    /// LOCAL — a sentence/paragraph hops a few paragraphs — so it stays within a few percent of the length even
    /// on a novel. A coincidental unique-phrase match between two independent witnesses lands anywhere (observed
    /// at 15–60% of the book on the Verne pair), so the fraction must be small: 0.03 admits a genuinely large
    /// local rearrangement while rejecting the cross-book coincidences.
    static let maxMoveFraction = 0.03
    /// A floor so short inputs (where 3% is only a token or two) still tolerate a legitimate local swap.
    static let minMoveTokens = 200
    /// An absolute ceiling so even a very long witness can't admit an implausibly distant "move" just because a
    /// small fraction of a huge document is still large. ~a chapter's worth of tokens.
    static let maxMoveTokens = 6_000

    /// Tolerance (in comparable tokens) for how far a move may deviate from the co-linear diagonal, given the
    /// two witness lengths. Shared by both move-detection paths (anchor spine + displaced-word recovery) so they
    /// judge "is this a real move or a far coincidence" identically.
    static func moveTolerance(aCount: Int, bCount: Int) -> Int {
        let frac = Int(maxMoveFraction * Double(max(aCount, bCount)))
        return min(maxMoveTokens, max(minMoveTokens, frac))
    }

    /// The SCALE-INDEPENDENT locality bound (in comparable tokens) used by the displaced-reading recovery's rarity
    /// gate (§6.1) to decide whether a **lone, non-globally-unique** recovered word is a genuine LOCAL move or a
    /// coincidence. See `recoverDisplacedReadings` for the full rationale; in short:
    ///
    /// `moveTolerance` (above) scales with the witness length, so on this ~60k-comparable-token novel its NEAR
    /// window is ~1785 tokens. That is the right bound for admitting a genuinely LARGE singular move of a
    /// *distinctive* (globally unique) word, but it is far too loose to vouch for a *common* word that the aligner
    /// merely left unmatched once: two independent translations run in parallel, so a common word's stray leftover
    /// routinely lands within ~1785 tokens of the diagonal purely by coincidence. A GENUINE local move of a
    /// repeated word, by contrast, is a *short* hop — the word swapped a few positions with a neighbour within the
    /// same clause. So a small ABSOLUTE bound distinguishes the two where the proportional `moveTolerance` cannot.
    /// For a non-unique single word we therefore require the pairing's diagonal deviation ≤ this bound; a
    /// globally-unique word (its uniqueness IS the corroboration) and a multi-word block (the phrase moving
    /// together IS the corroboration) are exempt.
    ///
    /// CALIBRATION (engine-measured diagonal deviations on the Verne *De la Terre à la Lune* full-novel pair —
    /// moonvoyage base vs. Towle's translation — the corpus where the phantom moves were found by hand):
    ///   • the ONE genuine local single-word move — "firearms" ("ancient or modern firearms" → "firearms, ancient
    ///     and modern", a within-clause reordering) — has deviation **46**; a synthetic short swap
    ///     (`the author wrote` → `the wrote … author`) is ≈2.
    ///   • the 26 coincidences (a common word left unmatched once, paired by elimination to an unrelated
    ///     occurrence — "p" 141, "level" 195, "board" 533, … up to "quietly" 5375, "along" 5536) all have
    ///     deviation **≥ 141**.
    /// The populations are cleanly separated by the gap **46 → 141**. Chosen at **80** — the midpoint of that gap:
    /// ≈1.7× above the true-positive ceiling (46) and ≈1.8× below the false-positive floor (141), so it is fragile
    /// to neither. If a future corpus shows a genuine repeated-word move with a larger local deviation (or a
    /// coincidence nearer the diagonal), raise/lower this — it is the single knob for the local/coincidence
    /// boundary. NOTE this bounds only the *non-unique single-word* case; genuine large moves of unique words are
    /// unaffected (they pass via `globallyUnique`), so changing it does not re-admit the far unique-word
    /// coincidences the §5.6 displacement gate already rejects.
    static let localMoveTokens = 80

    // MARK: anchor-block distinctiveness gate (the anchor-path counterpart of §6.1's locality gate)

    /// How far off the diagonal a MOVED ANCHOR BLOCK may sit, scaled by how DISTINCTIVE the block is (its length
    /// in comparable tokens). The rationale mirrors the §6.1 rarity gate but on the *other* move-detection path:
    ///
    /// A unique-in-both n-gram becomes an anchor, and an off-spine anchor is reported as a MOVE. On two
    /// independent translations of a novel, a SHORT common-word phrase ("we ought always to", "I tell you", "in
    /// cast-iron") is unique as a joined n-gram yet occurs — by coincidence — in two entirely unrelated
    /// sentences hundreds of lines apart. `displacementIsPlausible` alone only rejects pairings beyond the
    /// length-proportional `moveTolerance` (≈1800 on this ~60k-token novel), so these near-but-coincidental
    /// phantoms sail through (found by hand on the Verne pair: ≈90 of 107 "moves" were this shape).
    ///
    /// What separates a genuine long-range move from such a coincidence is the block's LENGTH: a real relocated
    /// passage is a distinctive multi-token run (it grows to 15–24 tokens); a coincidence is a short template. So
    /// the tolerance a block earns is `base + perToken·(len − free)`:
    ///   • a short block (≤ `distinctivenessFreeLength`) earns only the small absolute `anchorBlockBaseTolerance`
    ///     bound — it must be genuinely LOCAL to count, exactly like the §6.1 single-word case;
    ///   • each additional comparable token past the free length buys `distinctivenessPerToken` more tolerance,
    ///     so a long, distinctive passage can still be recognised moving a long way.
    ///
    /// This gate runs AFTER block growth (on the grown span), because the raw anchor is only ~2–3 tokens
    /// regardless — the distinguishing length only exists once the block has absorbed its surrounding identical
    /// run. A rejected block is NOT consumed, so its tokens fall back into ordinary region alignment (a
    /// coincidental phrase is then correctly a substitution/insertion/deletion, never fabricated as a move).
    ///
    /// CALIBRATION — RECALIBRATED 2026-07-24 across FOUR independent-translation full-novel pairs, superseding the
    /// original single-corpus (earth-to-moon) tuning. The first calibration (`base = localMoveTokens = 80`,
    /// `free = 4`, `perToken = 40`) was fit only on earth-to-moon, where the phantom anchor-moves happened to sit
    /// FAR off the diagonal (deviation 249–1962). It did **not generalise**: measured across journey-to-the-centre
    /// (malleson↔ward), earth-to-moon, 20,000-leagues, and mysterious-island, that gate admitted **all 48**
    /// detected "moves" — every one a false positive (two independent translations run in parallel, so a
    /// coincidental short unique-in-both phrase — "off the rocks", "I look at", "upon the sides of" — routinely
    /// lands only 5–100 tokens off the diagonal, well inside the flat 80-token base). Distance alone cannot see
    /// them; the flat base was the leak.
    ///
    /// The fix keeps the length-scaled *shape* but changes the constants so a SHORT block earns almost no distance
    /// credit — it must be genuinely LOCAL (deviation ≤ `anchorBlockBaseTolerance`) to count as a move, while a
    /// LONG distinctive block still earns tolerance to have relocated far. The discriminator is the same one §4.5.2
    /// established (grown-block length), pushed harder:
    ///
    /// CALIBRATION SET (grown span | diagonal deviation), comparable-token space:
    ///   • GENUINE moves that MUST survive (the conformance goldens + a sentence-swap + the one real relocation):
    ///       case 25 "author" 1|1 · case 04/05 "at last" 2|2, 2|5 · case 19 (Whitman line) 8|5 ·
    ///       the recursive-anchoring sentence-swap ("they were tired …" ⇄ "the lamps were lit …") 11|9 ·
    ///       case 27 Whitman *Calamus* poem-cluster (the one real found move) 19|84.
    ///     They span short-and-truly-local (dev ≤ 5), a medium sentence-swap displaced by its own length (11|9),
    ///     and a long relocation (Calamus, 19|84).
    ///   • FALSE moves that MUST drop (48 across the four pairs): short blocks (3–13 tokens) at deviation 5–508,
    ///     e.g. "off the rocks" 3|5, "I look at" 3|12, "our calculation. Here …" 10|217, "…cambridge…" 14|249.
    /// `base (anchorBlockBaseTolerance) = 10` (a genuine short/medium hop is ≤ 9 — the sentence-swap sits at 9; a
    /// coincidence that happens to be ≤ 10 off the diagonal is geometrically indistinguishable from a real local
    /// move and is knowingly kept — see the residual), `free = 14` (only a block longer than this earns *any*
    /// distance credit — every crafted/medium genuine move stays via the small base), `perToken = 18` (Calamus,
    /// 19|84, earns 10+18·5 = 100 ≥ 84, a 16-token margin — not on the boundary). Result on the four-pair audit:
    /// **48 → 5** false positives, every genuine golden + the sentence-swap + the Calamus move preserved.
    ///
    /// RESIDUAL (5 survivors, knowingly accepted): four SHORT blocks sitting almost ON the diagonal (dev 5–9, e.g.
    /// two 3|5 and a 3|9) — geometrically identical to a genuine short local hop, so inseparable on geometry alone —
    /// plus one LONG near-diagonal block (21|63). These are the least misleading false-positive shape (they look
    /// locally plausible and are rare — 5 across ~1M words of text). Tightening `base` below 9 would drop the
    /// genuine sentence-swap; lowering `perToken` would drop genuine long moves — both worse trades. Recorded as
    /// the boundary of the geometric method (PAPER_NOTES §4.5.2, §11).
    ///
    /// This calibration REPLACED the original single-corpus one (base 80 / free 4 / per 40, earth-to-moon only),
    /// which admitted all 48 (see the failure note above). `anchorBlockBaseTolerance` is DISTINCT from
    /// `localMoveTokens` (80): the latter is the §4.5.1 single-word recovery gate's own calibration (the 46 → 141
    /// gap) and is unchanged — the two paths judge locality on the same *metric* (diagonal deviation) but with
    /// independently-calibrated *bounds*.
    static let anchorBlockBaseTolerance = 10
    static let distinctivenessFreeLength = 14
    static let distinctivenessPerToken = 18
    static func anchorMoveTolerance(blockLength: Int) -> Int {
        anchorBlockBaseTolerance + distinctivenessPerToken * max(0, blockLength - distinctivenessFreeLength)
    }

    /// A grown moved block is a plausible move iff its diagonal deviation is within the distinctiveness-scaled
    /// tolerance for its length. `aStart`/`bStart` are the block's start indices, `blockLength` its comparable-token
    /// span. Reuses `diagonalDeviation` so this path judges locality on the SAME metric as §6.1 and the anchor
    /// pin gate (no drift between the three).
    static func anchorBlockIsPlausible(aStart: Int, bStart: Int, blockLength: Int,
                                       aCount: Int, bCount: Int) -> Bool {
        guard aCount > 0, bCount > 0 else { return true }
        let dev = diagonalDeviation(delTok: aStart, insTok: bStart, aCount: aCount, bCount: bCount)
        return dev <= anchorMoveTolerance(blockLength: blockLength)
    }

    /// Witness size (comparable tokens) above which a SHORT anchor block that merely *passed* the distinctiveness
    /// gate is reported as a *possible* move (`.likely`), not asserted (`.certain`). See `anchorMoveIsCertain`.
    static let confidentMoveWitnessFloor = 4_000

    /// Confidence for an anchor-path move that has ALREADY passed `anchorBlockIsPlausible`. The honest treatment of
    /// the gate's irreducible residual (PAPER_NOTES §4.5.2, §11): a SHORT block (≤ `distinctivenessFreeLength`) sits
    /// close to the diagonal, but on a LONG parallel pair (two independent translations tracking page-for-page) a
    /// small absolute displacement is indistinguishable from a genuine short local hop — e.g. "off the rocks", dev 5,
    /// in an ~86k-token novel. It cannot be *dropped* (a legitimate 1–2-token move — conformance cases 04/05/25 — is
    /// geometrically identical), so it is instead marked **`.likely`** ("possible move"), never asserted. A block is
    /// `.certain` when it is either:
    ///   • DISTINCTIVE — longer than the free length, so its own length corroborates the move (Calamus, len 22); or
    ///   • in a SHORT witness (≤ `confidentMoveWitnessFloor`), where a short block's displacement is a MEANINGFUL
    ///     fraction of the document — a real swap in a crafted/short pair, not alignment noise (cases 04/05, len 2).
    /// Scale-relative by design: the same 3-token block is `.certain` in a 10-token swap and `.likely` in a 90k-token
    /// novel. This only softens confidence on the anchor path; the displaced-word path (§6.1) sets its own confidence
    /// (globally-unique ⇒ certain), and no move is added or removed here.
    static func anchorMoveIsCertain(blockLength: Int, aCount: Int, bCount: Int) -> Bool {
        if blockLength > distinctivenessFreeLength { return true }          // distinctive by length
        return max(aCount, bCount) <= confidentMoveWitnessFloor            // or a real swap in a short witness
    }

    /// The diagonal-predicted B position of base-token `d` and the deviation of an actual B position from it —
    /// `expected(d) = round(d · |B| / |A|)`. This is the SAME quantity `pairByExpandingWindow` measures for its
    /// near/far decision; exposed so the recovery pass's rarity gate (§6.1) judges locality on exactly the metric
    /// the pairing was accepted under (no drift between the two). Returns 0 for degenerate lengths.
    static func diagonalDeviation(delTok: Int, insTok: Int, aCount: Int, bCount: Int) -> Int {
        guard aCount > 0, bCount > 0 else { return 0 }
        let expected = Int((Double(delTok) * Double(bCount) / Double(aCount)).rounded())
        return abs(insTok - expected)
    }

    /// Is `pin`'s B position a plausible move, or a coincidental far-away unique-phrase match?
    ///
    /// Two aligned witnesses are globally CO-LINEAR: a token a given fraction of the way through A sits at
    /// roughly the same fraction of the way through B. A genuine transposition is a LOCAL excursion off that
    /// diagonal (a sentence hops a few paragraphs); a coincidental unique-phrase match between two independent
    /// witnesses lands anywhere. We reject a candidate move whose B position deviates from the diagonal
    /// expectation by more than `moveTolerance`.
    ///
    /// The diagonal is used deliberately INSTEAD of interpolating the stable spine: with two long, independent
    /// translations the spine itself is partly built from coincidental anchors, so a spine-relative expectation
    /// is unreliable and lets far matches look "plausible" against neighbouring bad anchors. The whole-document
    /// diagonal has no such dependence — it is the one thing that stays true no matter how noisy the anchors are.
    static func displacementIsPlausible(_ pin: AnchorPin, spine: [AnchorPin], aCount: Int, bCount: Int) -> Bool {
        _ = spine   // retained in the signature for callers/tests; the diagonal gate needs only the lengths
        guard aCount > 0, bCount > 0 else { return true }
        let expectedB = Int((Double(pin.aStart) * Double(bCount) / Double(aCount)).rounded())
        return abs(pin.bStart - expectedB) <= moveTolerance(aCount: aCount, bCount: bCount)
    }

    // MARK: expanding-window pairing (refinement of the fixed gate)

    /// A displacement-gate pairing accepted by the expanding-window search: which deletion-occurrence moved to
    /// which insertion-occurrence, and whether it was found within the NEAR tolerance (⇒ eligible for `certain`)
    /// or only by widening the radius (⇒ at best `likely`).
    struct WindowPair: Equatable { let delTok: Int; let insTok: Int; let near: Bool }

    /// How much closer the best candidate must be than the runner-up for a *widened* (beyond-near) pairing to
    /// count as UNAMBIGUOUS. Two roughly-equidistant far occurrences give no basis to say which one moved, so we
    /// refuse to guess; a clearly-closest one is a real move. (Near pairings are accepted without this test —
    /// within the local tolerance a single best candidate is already unambiguous enough.)
    static let ambiguityRatio = 0.5

    /// Pair the occurrences of one displaced key by an EXPANDING-WINDOW search around the co-linear diagonal.
    ///
    /// For each deletion position `d` (base-token index) the diagonal predicts an insertion position
    /// `expected(d) = round(d · |B| / |A|)`. We pair greedily by increasing diagonal distance, consuming each
    /// occurrence once:
    ///   • a pairing within `moveTolerance` (the NEAR window) is accepted as soon as it is the closest available
    ///     — a local move;
    ///   • a pairing only reachable by WIDENING (near tolerance < distance ≤ `maxMoveTokens`) is accepted only
    ///     when it is UNAMBIGUOUS — the next-best alternative for either endpoint is at least `1/ambiguityRatio`×
    ///     farther — so a genuinely large but singular move is admitted while a rare word recurring at several
    ///     unrelated spots is left as plain deletion+insertion;
    ///   • nothing beyond `maxMoveTokens` is ever paired.
    /// Deterministic: candidates are ordered by (distance, delTok, insTok); ties resolve by position.
    static func pairByExpandingWindow(delPositions: [Int], insPositions: [Int],
                                      aCount: Int, bCount: Int) -> [WindowPair] {
        guard aCount > 0, bCount > 0, !delPositions.isEmpty, !insPositions.isEmpty else {
            // Degenerate lengths: fall back to a single pairing only if each side has exactly one occurrence.
            if delPositions.count == 1 && insPositions.count == 1 {
                return [WindowPair(delTok: delPositions[0], insTok: insPositions[0], near: true)]
            }
            return []
        }
        let near = moveTolerance(aCount: aCount, bCount: bCount)
        func expected(_ d: Int) -> Int { Int((Double(d) * Double(bCount) / Double(aCount)).rounded()) }

        // All candidate (d, i) pairs within the FAR ceiling, with their diagonal distance. Sorted for determinism.
        struct Cand { let d: Int; let i: Int; let dist: Int }
        var cands: [Cand] = []
        for d in delPositions {
            let e = expected(d)
            for i in insPositions {
                let dist = abs(i - e)
                if dist <= maxMoveTokens { cands.append(Cand(d: d, i: i, dist: dist)) }
            }
        }
        cands.sort { $0.dist != $1.dist ? $0.dist < $1.dist : ($0.d != $1.d ? $0.d < $1.d : $0.i < $1.i) }

        var usedD = Set<Int>(), usedI = Set<Int>()
        var out: [WindowPair] = []
        for c in cands {
            guard !usedD.contains(c.d), !usedI.contains(c.i) else { continue }
            if c.dist <= near {
                out.append(WindowPair(delTok: c.d, insTok: c.i, near: true))
                usedD.insert(c.d); usedI.insert(c.i)
            } else {
                // Widened (near < dist ≤ far ceiling): accept only if UNAMBIGUOUS. It is contested when some
                // OTHER still-available candidate sharing this deletion or this insertion sits at a comparable
                // distance — i.e. not clearly farther than `dist / ambiguityRatio` (2× when ratio = 0.5). A
                // clearly-closest widened pairing is a real large move; roughly-equidistant rivals mean we
                // cannot say which occurrence moved, so we decline and leave plain deletion + insertion.
                let contested = cands.contains { other in
                    guard other.d == c.d || other.i == c.i else { return false }         // shares an endpoint
                    guard other.d != c.d || other.i != c.i else { return false }         // not the candidate itself
                    guard !usedD.contains(other.d), !usedI.contains(other.i) else { return false }
                    return Double(other.dist) < Double(c.dist) / ambiguityRatio          // a comparably-near rival
                }
                if !contested {
                    out.append(WindowPair(delTok: c.d, insTok: c.i, near: false))
                    usedD.insert(c.d); usedI.insert(c.i)
                }
            }
        }
        // Emit in a stable order (by deletion position) so downstream coalescing/output is deterministic.
        return out.sorted { $0.delTok < $1.delTok }
    }

    // MARK: anchors

    /// The smallest n-gram length we will fall back to. Below 2, "unique" bigrams degenerate toward single
    /// tokens and stop being distinctive, so 2 is the floor.
    static let minAnchorLength = 2

    /// Try `uniqueCommonAnchors` at `startN`, then progressively shorter n-grams while anchors are too sparse
    /// to chunk the matrix usefully. "Useful" = the anchors cover a reasonable fraction of the shorter
    /// witness; the threshold scales with size so short inputs aren't over-fitted. Returns the anchors at the
    /// largest n that clears the bar (longer anchors are more reliable), or the best non-empty set found.
    static func adaptiveAnchors(_ a: [String], _ b: [String], startN: Int) -> [AnchorPin] {
        let shorter = max(1, min(a.count, b.count))
        // Want anchors to pin at least ~1 in every 50 tokens (cheap, conservative); never demand more than a
        // handful for tiny inputs.
        let wanted = max(1, min(shorter / 50, 8))
        var fallback: [AnchorPin] = []
        var n = max(minAnchorLength, startN)
        while n >= minAnchorLength {
            let anchors = uniqueCommonAnchors(a, b, n: n)
            if anchors.count >= wanted { return anchors }     // enough landmarks at this (largest passing) n
            if anchors.count > fallback.count { fallback = anchors }   // remember the densest seen
            n -= 1
        }
        return fallback
    }

    /// n-grams (joined comparable keys) that appear EXACTLY ONCE in `a` AND exactly once in `b`. These are
    /// unambiguous shared landmarks. Returns one `AnchorPin` per such n-gram.
    static func uniqueCommonAnchors(_ a: [String], _ b: [String], n: Int) -> [AnchorPin] {
        guard n > 0, a.count >= n, b.count >= n else { return [] }
        let aGrams = ngramPositions(a, n: n)
        let bGrams = ngramPositions(b, n: n)
        var pins: [AnchorPin] = []
        for (gram, aPositions) in aGrams where aPositions.count == 1 {
            guard let bPositions = bGrams[gram], bPositions.count == 1 else { continue }
            pins.append(AnchorPin(aStart: aPositions[0], bStart: bPositions[0], length: n))
        }
        // Drop overlapping anchors (keep the earliest in A) so anchor regions don't intersect. NOTE: this
        // dedupes in A only — B positions are intentionally NOT monotonic here (moved blocks run backwards in
        // B), so we must not filter on B or we'd discard legitimate moved-block anchors. Two kept anchors can
        // therefore still overlap in B; the spine builder tolerates that and the region spans are clamped
        // defensively in `appendRegion` so an overlap yields an empty region, never an inverted range.
        let sorted = pins.sorted { $0.aStart < $1.aStart }
        var result: [AnchorPin] = []
        var lastEnd = -1
        for p in sorted where p.aStart > lastEnd {
            result.append(p)
            lastEnd = p.aStart + p.length - 1
        }
        return result
    }

    private static func ngramPositions(_ tokens: [String], n: Int) -> [String: [Int]] {
        var map: [String: [Int]] = [:]
        guard tokens.count >= n else { return map }
        for i in 0...(tokens.count - n) {
            let gram = tokens[i..<(i + n)].joined(separator: "\u{1f}")
            map[gram, default: []].append(i)
        }
        return map
    }

    /// Indices (into `pins`, already sorted by A) forming the longest subsequence whose B positions strictly
    /// increase — the largest set of anchors that keep the same relative order in both witnesses. Anchors
    /// outside this set are the ones that moved.
    static func longestIncreasingByB(_ pins: [AnchorPin]) -> [Int] {
        let bs = pins.map { $0.bStart }
        let nP = bs.count
        guard nP > 0 else { return [] }
        var tails: [Int] = []          // tails[k] = index (into pins) ending an increasing run of length k+1
        var prev = [Int](repeating: -1, count: nP)
        for i in 0..<nP {
            // binary search for first tail whose bStart >= bs[i]
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if bs[tails[mid]] < bs[i] { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { prev[i] = tails[lo - 1] }
            if lo == tails.count { tails.append(i) } else { tails[lo] = i }
        }
        // Reconstruct.
        var seq: [Int] = []
        var k = tails.isEmpty ? -1 : tails[tails.count - 1]
        while k >= 0 { seq.append(k); k = prev[k] }
        return seq.reversed()
    }

    /// Maximum-WEIGHT strictly-increasing-by-B subsequence (O(n²) DP). Generalizes `longestIncreasingByB`:
    /// each anchor contributes `weights[i]` rather than 1, so a page-aware weighting can prefer a spine of
    /// page-stable anchors over an equally-long page-crossing one. With all weights equal this returns a
    /// maximum-cardinality spine (same set the plain LIS would yield, up to ties).
    static func maxWeightIncreasingByB(_ pins: [AnchorPin], weights: [Int]) -> [Int] {
        let nP = pins.count
        guard nP > 0 else { return [] }
        let bs = pins.map { $0.bStart }
        var best = weights                          // best[i] = max weight of a chain ending at i
        var prev = [Int](repeating: -1, count: nP)
        for i in 0..<nP {
            for j in 0..<i where bs[j] < bs[i] {
                if best[j] + weights[i] > best[i] {
                    best[i] = best[j] + weights[i]
                    prev[i] = j
                }
            }
        }
        // End at the highest-weight chain (tie → the one ending earliest, for determinism).
        var endIdx = 0
        for i in 1..<nP where best[i] > best[endIdx] { endIdx = i }
        var seq: [Int] = []
        var k = endIdx
        while k >= 0 { seq.append(k); k = prev[k] }
        return seq.reversed()
    }
}
