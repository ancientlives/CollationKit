import Foundation

// MARK: - Pairwise alignment (stage 2)
//
// Global sequence alignment via Needleman–Wunsch — the standard for collation, chosen over an LCS/`diff`
// because it SCORES substitutions and gaps (a reworded clause becomes a run of substitutions, not a
// delete-block + insert-block). It operates on the *comparable* tokens (punctuation folded out), so it
// aligns prose to prose. The result is a list of `AlignOp`s over token INDICES in each side.
//
// On its own NW does not model TRANSPOSITION (a passage that moved). That's added on top in
// `Transposition.swift` via an anchor pass; this file is the within-segment aligner it calls.

/// One aligned step between two token sequences A (base) and B (compared).
public enum AlignOp: Equatable {
    case match(a: Int, b: Int)         // A[a] ~ B[b], same normalized reading
    case substitute(a: Int, b: Int)    // A[a] ≠ B[b], both present (different reading)
    case delete(a: Int)                // A[a] has no counterpart in B (omitted in B)
    case insert(b: Int)                // B[b] has no counterpart in A (added in B)
}

public struct AlignmentScores: Equatable {
    public var match: Int
    public var mismatch: Int           // substitution penalty (negative)
    public var gap: Int                // insert/delete penalty (negative)
    public init(match: Int = 2, mismatch: Int = -1, gap: Int = -2) {
        self.match = match; self.mismatch = mismatch; self.gap = gap
    }

    // MARK: - Scoring presets (B7): verse vs prose
    //
    // The NW scores are a genre knob. Only the *ratio* between them matters (NW picks the max-scoring path),
    // so a preset is a point in the (match : mismatch : gap) trade space. Two named presets ship; a caller may
    // still pass a hand-tuned `AlignmentScores`.

    /// The default, prose-tuned scores: `+2 / −1 / −2`. A single substitution (−1 relative to a match's +2, a
    /// swing of 3) is cheaper than a delete+insert (2·−2 = −4, a swing of 6), so a reworded word aligns as one
    /// SUBSTITUTION rather than a delete-block + insert-block — the behaviour prose collation wants. This is the
    /// historical default and what every conformance golden is recorded under.
    public static let prose = AlignmentScores(match: 2, mismatch: -1, gap: -2)

    /// Verse-tuned scores: `+2 / −3 / −1`. In verse the meaningful unit of change is often a whole *line*
    /// added, dropped, or rewritten, and repeated line-initial words (anaphora) recur; forcing a reworded line
    /// into position-by-position SUBSTITUTIONS misreads the variation (a rewritten line is a *new* line, not N
    /// coincidental word-swaps). The condition for the aligner to prefer delete+insert over substitution across
    /// a disjoint run is `mismatch < 2·gap`; prose (`−1 vs 2·−2 = −4`) fails it, so prose substitutes. Verse
    /// sets `mismatch = −3 < 2·−1 = −2`, so a run with no shared words aligns as a clean **deletion + insertion**
    /// (the old line dropped, the new line added) rather than word-against-word substitutions — and an added or
    /// dropped line surfaces whole. Matches (`+2`) still dominate, so genuinely co-linear text aligns unchanged;
    /// the knob only bites in gap regions where the aligner must trade a mismatch against a gap.
    ///
    /// NOT the default and NOT used by any conformance golden (those are pinned to `.prose`); opt in per run
    /// (`--scoring verse`). See `docs/reference/ALGORITHMS.md §10` and `docs/development/CASE_STUDY.md` (Whitman).
    public static let verse = AlignmentScores(match: 2, mismatch: -3, gap: -1)
}

/// A named genre preset selecting an `AlignmentScores` — the user-facing form of the scoring knob (B7). Kept
/// beside the engine (not in the CLI) so the CLI, tests, and any app share one vocabulary and one mapping.
public enum ScoringPreset: String, Equatable, CaseIterable {
    case prose
    case verse

    /// The scores this preset selects.
    public var scores: AlignmentScores {
        switch self {
        case .prose: return .prose
        case .verse: return .verse
        }
    }

    /// A short, plain-language label for a CLI/help affordance.
    public var label: String {
        switch self {
        case .prose: return "Prose — reworded text aligns as substitutions (default)"
        case .verse: return "Verse — added/dropped lines align as whole insertions/deletions"
        }
    }
}

public enum Alignment {

    /// Needleman–Wunsch global alignment of two `String` key sequences (the tokens' `normalized` values).
    /// Returns ops over indices into `a` and `b`. Deterministic tie-breaking (diagonal > up > left) keeps
    /// output stable for tests.
    public static func needlemanWunsch(_ a: [String], _ b: [String],
                                       scores: AlignmentScores = AlignmentScores()) -> [AlignOp] {
        let n = a.count, m = b.count
        if n == 0 { return (0..<m).map { .insert(b: $0) } }
        if m == 0 { return (0..<n).map { .delete(a: $0) } }

        // Score matrix (n+1) x (m+1).
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { dp[i][0] = i * scores.gap }
        for j in 1...m { dp[0][j] = j * scores.gap }
        for i in 1...n {
            for j in 1...m {
                let s = (a[i - 1] == b[j - 1]) ? scores.match : scores.mismatch
                let diag = dp[i - 1][j - 1] + s
                let up   = dp[i - 1][j] + scores.gap     // delete a[i-1]
                let left = dp[i][j - 1] + scores.gap     // insert b[j-1]
                dp[i][j] = max(diag, max(up, left))
            }
        }

        // Traceback with stable preference: diagonal, then up (delete), then left (insert).
        var ops: [AlignOp] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 {
                let s = (a[i - 1] == b[j - 1]) ? scores.match : scores.mismatch
                if dp[i][j] == dp[i - 1][j - 1] + s {
                    ops.append(a[i - 1] == b[j - 1] ? .match(a: i - 1, b: j - 1)
                                                    : .substitute(a: i - 1, b: j - 1))
                    i -= 1; j -= 1; continue
                }
            }
            if i > 0 && dp[i][j] == dp[i - 1][j] + scores.gap {
                ops.append(.delete(a: i - 1)); i -= 1; continue
            }
            // else insert
            ops.append(.insert(b: j - 1)); j -= 1
        }
        return ops.reversed()
    }

    /// Banded Needleman–Wunsch: computes only the DP cells within `band` of the (rescaled) main diagonal,
    /// giving `O((n+m)·band)` time/space instead of `O(n·m)`. The band is anchored to the diagonal that runs
    /// to the far corner, so it tolerates up to `band` tokens of cumulative drift between the witnesses.
    ///
    /// `hitEdge` reports whether the optimal traceback ever rode the band boundary — if true the band was too
    /// narrow and the result may be sub-optimal, so a caller can widen and retry (see `bandedAutoWidening`).
    /// Returns the same `[AlignOp]` shape as full NW; within the band the alignment is globally optimal.
    static func banded(_ a: [String], _ b: [String], band: Int,
                       scores: AlignmentScores = AlignmentScores()) -> (ops: [AlignOp], hitEdge: Bool) {
        let n = a.count, m = b.count
        if n == 0 { return ((0..<m).map { .insert(b: $0) }, false) }
        if m == 0 { return ((0..<n).map { .delete(a: $0) }, false) }
        let w = max(band, abs(n - m) + 1)        // band must at least span the length difference
        let NEG = Int.min / 4                      // -inf sentinel (room so additions don't overflow)

        // For each row i (0…n), valid columns j lie in [lo(i), hi(i)] = [i*m/n ± w], clamped to [0, m].
        func lo(_ i: Int) -> Int { max(0, (i * m) / n - w) }
        func hi(_ i: Int) -> Int { min(m, (i * m) / n + w) }

        var dp = [[Int]](repeating: [], count: n + 1)
        for i in 0...n {
            let l = lo(i), h = hi(i)
            dp[i] = [Int](repeating: NEG, count: h - l + 1)
        }
        func get(_ i: Int, _ j: Int) -> Int {
            let l = lo(i); let h = hi(i)
            if j < l || j > h { return NEG }
            return dp[i][j - l]
        }
        func set(_ i: Int, _ j: Int, _ v: Int) { dp[i][j - lo(i)] = v }

        set(0, 0, 0)
        for j in max(1, lo(0))...max(lo(0), hi(0)) where j >= 1 { set(0, j, j * scores.gap) }
        for i in 1...n {
            let l = lo(i), h = hi(i)
            for j in l...h {
                var best = NEG
                if j == 0 { best = i * scores.gap }
                let diag = (j >= 1) ? get(i - 1, j - 1) : NEG
                if diag > NEG {
                    let s = (a[i - 1] == b[j - 1]) ? scores.match : scores.mismatch
                    best = max(best, diag + s)
                }
                let up = get(i - 1, j)               // delete a[i-1]
                if up > NEG { best = max(best, up + scores.gap) }
                let left = (j >= 1) ? get(i, j - 1) : NEG   // insert b[j-1]
                if left > NEG { best = max(best, left + scores.gap) }
                set(i, j, best)
            }
        }

        // Traceback, noting if we ever sit on the band edge (→ possibly clipped, widen & retry).
        var ops: [AlignOp] = []
        var i = n, j = m
        var hitEdge = false
        while i > 0 || j > 0 {
            // Flag only INTERIOR band-edge contact: the corners (0,0) and (n,m) are forced endpoints, and a
            // band that already spans the length difference legitimately sits at the boundary there.
            let interior = (i > 0 && i < n)
            if interior && (j <= lo(i) || j >= hi(i)) { hitEdge = true }
            if i > 0 && j > 0 {
                let s = (a[i - 1] == b[j - 1]) ? scores.match : scores.mismatch
                if get(i, j) == get(i - 1, j - 1) + s {
                    ops.append(a[i - 1] == b[j - 1] ? .match(a: i - 1, b: j - 1)
                                                    : .substitute(a: i - 1, b: j - 1))
                    i -= 1; j -= 1; continue
                }
            }
            if i > 0 && get(i, j) == get(i - 1, j) + scores.gap {
                ops.append(.delete(a: i - 1)); i -= 1; continue
            }
            ops.append(.insert(b: j - 1)); j -= 1
        }
        return (ops.reversed(), hitEdge)
    }

    /// Banded NW that widens the band and retries while the optimal path keeps hitting the edge, doubling up
    /// to a cap. Converges to the full-NW result once the band covers the true drift; cheap when drift is
    /// small. (Hirschberg's algorithm is the alternative if EXACT alignment of a fully-arbitrary pair ever
    /// matters: it gives full NW in O(n·m) time but only O(min(n,m)) space — better memory, same time. Banding
    /// is preferred here because the realistic worst case is a long but loosely co-linear pair, where a small
    /// band is both correct and far cheaper.)
    static func bandedAutoWidening(_ a: [String], _ b: [String], initialBand: Int, maxBand: Int,
                                   scores: AlignmentScores = AlignmentScores()) -> [AlignOp] {
        var band = max(1, initialBand)
        while true {
            let (ops, hitEdge) = banded(a, b, band: band, scores: scores)
            if !hitEdge || band >= maxBand { return ops }
            band = min(band * 2, maxBand)
        }
    }
}
