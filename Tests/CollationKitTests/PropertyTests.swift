import XCTest
@testable import CollationKit

// MARK: - Property-based / fuzz tests (BACKLOG B5)
//
// Crafted tests pin specific known cases; these assert INVARIANTS that must hold for *many* pseudo-random
// inputs — catching edge cases hand-written fixtures miss and strengthening the correctness claims. Each
// property runs over a sweep of seeds with a deterministic PRNG (SplitMix64), so a failure is reproducible
// (the failing seed is printed) — no flakiness, matching the determinism ethos of the conformance corpus.
//
// Properties asserted:
//   1. self-collation is empty            — a witness vs. itself has no variants.
//   2. determinism                        — collating the same pair twice is identical.
//   3. bounded substitutions              — K random word-substitutions yield ≤ K substitution variations.
//   4. reading round-trip                 — every reported reading actually occurs in its witness.
//   5. insertion / deletion symmetry      — appended/removed words are typed as insertion/deletion, and the
//                                           two directions mirror.
//   6. well-formed locations              — citations are never out of range or malformed, for any input.

final class PropertyTests: XCTestCase {

    // Deterministic PRNG so failures reproduce; seeded per-property × per-iteration.
    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A pseudo-random witness of `count` words. `distinctiveEvery` controls anchor density: every Nth word is
    /// index-suffixed (globally unique → a reliable anchor), the rest are common function words. Sentence and
    /// paragraph structure is generated so the tokenizer's line/page logic is exercised too.
    private func makeWords(count: Int, distinctiveEvery: Int, rng: inout SplitMix64) -> [String] {
        let common = ["the", "and", "of", "a", "to", "in", "that", "it", "was", "he", "she", "had"]
        var words: [String] = []
        words.reserveCapacity(count)
        for i in 0..<count {
            if distinctiveEvery > 0 && i % distinctiveEvery == 0 { words.append("tok\(i)") }
            else { words.append(common[Int(rng.next() % UInt64(common.count))]) }
        }
        return words
    }

    private func text(_ words: [String]) -> String {
        // Join with sentence/paragraph breaks so structure (lines, paragraphs) is non-trivial.
        var out = ""
        for (i, w) in words.enumerated() {
            out += w
            if (i + 1) % 13 == 0 { out += ".\n\n" } else { out += " " }
        }
        return out
    }

    private func witness(_ id: String, _ words: [String]) -> Witness { Witness(id: id, text: text(words)) }

    // MARK: 1. self-collation is empty

    func testSelfCollationHasNoVariants() {
        for seed in 0..<40 {
            var rng = SplitMix64(seed: 0x5E1F_0000 ^ UInt64(seed))
            let w = makeWords(count: 30 + Int(rng.next() % 120), distinctiveEvery: 3, rng: &rng)
            let wit = witness("X", w)
            let r = Collation.collate(base: wit, compared: wit)
            XCTAssertTrue(r.variations.isEmpty, "seed \(seed): a witness vs itself must have no variants")
        }
    }

    // MARK: 2. determinism

    func testCollationIsDeterministicForRandomPairs() {
        for seed in 0..<40 {
            var rng = SplitMix64(seed: 0xDE7E_0000 ^ UInt64(seed))
            let base = makeWords(count: 40 + Int(rng.next() % 100), distinctiveEvery: 3, rng: &rng)
            var comp = base
            // A few random single-word edits at distinctive sites.
            for _ in 0..<(1 + Int(rng.next() % 5)) {
                let k = Int(rng.next() % UInt64(comp.count))
                comp[k] = "edit\(rng.next() % 9999)"
            }
            let a = witness("A", base), b = witness("B", comp)
            XCTAssertEqual(Collation.collate(base: a, compared: b),
                           Collation.collate(base: a, compared: b),
                           "seed \(seed): identical inputs must give identical results")
        }
    }

    // MARK: 3. bounded substitutions

    func testKSubstitutionsYieldAtMostKSubstitutionVariations() {
        for seed in 0..<50 {
            var rng = SplitMix64(seed: 0xB0_0DED ^ UInt64(seed))
            // Use FULLY distinctive words so every edit lands on a unique, anchorable token and reads as a
            // clean substitution (no accidental insert/delete from repeated function words).
            let n = 60 + Int(rng.next() % 80)
            var base: [String] = (0..<n).map { "wd\($0)s\(seed)" }
            var comp = base
            // Pick K distinct positions to substitute (never adjacent, so coalescing can't merge two edits
            // into one and undercount — this makes "≤ K" the tight, meaningful bound).
            let k = 1 + Int(rng.next() % 6)
            var sites = Set<Int>()
            var guardCount = 0
            while sites.count < k && guardCount < 1000 {
                let p = 1 + Int(rng.next() % UInt64(n - 2))
                if !sites.contains(p - 1) && !sites.contains(p + 1) { sites.insert(p) }
                guardCount += 1
            }
            for p in sites { comp[p] = "REV\(p)" }
            let r = Collation.collate(base: witness("A", base), compared: witness("B", comp))
            XCTAssertLessThanOrEqual(r.substitutions, sites.count,
                "seed \(seed): \(sites.count) non-adjacent substitutions must not produce more than \(sites.count) substitution variations (got \(r.substitutions))")
            XCTAssertGreaterThan(r.variations.count, 0, "seed \(seed): edits must surface as variants")
            _ = base  // silence unused-mutation warning path
        }
    }

    // MARK: 4. reading round-trip

    func testReportedReadingsOccurInTheirWitness() {
        for seed in 0..<50 {
            var rng = SplitMix64(seed: 0x4EAD_0000 ^ UInt64(seed))
            let n = 50 + Int(rng.next() % 90)
            // Plain alphanumeric tokens (no '_' or '-', which would split/fold and complicate the round-trip).
            let base: [String] = (0..<n).map { "base\($0)s\(seed)" }
            var comp = base
            for _ in 0..<(1 + Int(rng.next() % 8)) {
                let k = Int(rng.next() % UInt64(comp.count))
                comp[k] = "comp\(rng.next() % 99999)"
            }
            let baseText = text(base), compText = text(comp)
            let r = Collation.collate(base: Witness(id: "A", text: baseText),
                                      compared: Witness(id: "B", text: compText))
            // The normalized base/compared word sets (alignment compares on normalized keys).
            let baseKeys = Set(Tokenizer.tokenize(baseText, with: .substantive).filter { $0.isComparable }.map { $0.normalized })
            let compKeys = Set(Tokenizer.tokenize(compText, with: .substantive).filter { $0.isComparable }.map { $0.normalized })
            // A reading surface joins words AND punctuation (e.g. a span "tok12 ."); only the WORD fragments
            // (those carrying a letter/digit) are comparable keys that must round-trip to a witness token.
            func wordKeys(_ reading: String) -> [String] {
                reading.split(separator: " ")
                    .filter { $0 != "∅" && $0.contains(where: { $0.isLetter || $0.isNumber }) }
                    .map { Normalizer.substantive.normalize(word: String($0)) }
                    .filter { !$0.isEmpty }
            }
            for v in r.variations {
                for key in wordKeys(v.baseReading) {
                    XCTAssertTrue(baseKeys.contains(key),
                        "seed \(seed): base reading word '\(key)' not found in base witness")
                }
                for key in wordKeys(v.comparedReading) {
                    XCTAssertTrue(compKeys.contains(key),
                        "seed \(seed): compared reading word '\(key)' not found in compared witness")
                }
            }
        }
    }

    // MARK: 5. insertion / deletion symmetry

    func testAppendedWordsAreInsertionsAndRemovalIsTheMirror() {
        for seed in 0..<40 {
            var rng = SplitMix64(seed: 0x1_75E47 ^ UInt64(seed))
            let n = 40 + Int(rng.next() % 60)
            let base: [String] = (0..<n).map { "tk\($0)s\(seed)" }
            // Insert a run of distinctive words in the MIDDLE (anchored on both sides so it's a clean insert).
            let insertAt = n / 2
            let added: [String] = (0..<(1 + Int(rng.next() % 4))).map { "NEW\($0)s\(seed)" }
            var comp = base
            comp.insert(contentsOf: added, at: insertAt)

            let fwd = Collation.collate(base: witness("A", base), compared: witness("B", comp))
            XCTAssertGreaterThan(fwd.insertions, 0, "seed \(seed): added words should be reported as insertion(s)")
            XCTAssertEqual(fwd.substitutions, 0, "seed \(seed): a clean middle insertion is not a substitution")

            // The reverse direction must mirror: what was an insertion is now a deletion, none the other way.
            let rev = Collation.collate(base: witness("B", comp), compared: witness("A", base))
            XCTAssertGreaterThan(rev.deletions, 0, "seed \(seed): the reverse of an insertion is a deletion")
            XCTAssertEqual(rev.insertions, 0, "seed \(seed): reverse direction should have no insertions")
        }
    }

    // MARK: 6. well-formed locations

    func testLocationsAreWellFormedForArbitraryInput() {
        for seed in 0..<60 {
            var rng = SplitMix64(seed: 0x10C_0000 ^ UInt64(seed))
            // Mix distinctive and repeated words, varying anchor density (incl. low-diversity inputs).
            let n = 20 + Int(rng.next() % 160)
            let every = 1 + Int(rng.next() % 6)
            let base = makeWords(count: n, distinctiveEvery: every, rng: &rng)
            var comp = base
            for _ in 0..<(Int(rng.next() % 10)) {
                let k = Int(rng.next() % UInt64(max(1, comp.count)))
                comp[k] = "z\(rng.next() % 9999)"
            }
            let baseText = text(base)
            let r = Collation.collate(base: Witness(id: "A", text: baseText), compared: witness("B", comp))
            let baseLen = baseText.utf16.count
            for v in r.variations {
                for loc in [v.baseLocation, v.comparedLocation].compactMap({ $0 }) {
                    XCTAssertGreaterThanOrEqual(loc.page, 0, "seed \(seed): page must be ≥ 0")
                    XCTAssertGreaterThanOrEqual(loc.line, 0, "seed \(seed): line must be ≥ 0")
                    XCTAssertLessThanOrEqual(loc.line, loc.endLine, "seed \(seed): line ≤ endLine")
                    XCTAssertGreaterThanOrEqual(loc.firstWord, 0, "seed \(seed): firstWord must be ≥ 0")
                    XCTAssertLessThanOrEqual(loc.charRange.lowerBound, loc.charRange.upperBound,
                                             "seed \(seed): charRange must be non-decreasing")
                    XCTAssertFalse(loc.human.isEmpty, "seed \(seed): citation string must be non-empty")
                }
                // A base location's char range must lie within the base text.
                if let bl = v.baseLocation {
                    XCTAssertLessThanOrEqual(bl.charRange.upperBound, baseLen,
                                             "seed \(seed): base char range must be within the base text")
                }
            }
        }
    }

    // MARK: 7. large, repetitive, heavily-reordered pairs don't trap (regression: inverted region range)

    /// The Verne full-novel corpus surfaced a `Range requires lowerBound <= upperBound` trap: on large,
    /// repetitive, highly-divergent text, two unique-common anchors can overlap in B (B positions aren't
    /// monotonic in A-order), which the max-weight-increasing-by-B spine can place on the spine with
    /// overlapping B spans — making a between-anchor region span invert. Fixed by clamping the region bounds in
    /// `Transposition.appendRegion` (an anchor overlap ⇒ an empty gap, not an inverted range). This property
    /// asserts the whole pipeline COMPLETES (no trap) on exactly that regime: long inputs, low anchor density
    /// (lots of repeated function words → many colliding grams), and heavy reordering.
    func testLargeRepetitiveReorderedPairsDoNotTrap() {
        for seed in 0..<24 {
            var rng = SplitMix64(seed: 0xC0FFEE ^ UInt64(seed))
            // Long + low diversity: distinctive words only every 5–9 tokens, so common words dominate and
            // many n-grams repeat — the conditions that produce B-overlapping unique anchors at scale.
            let n = 600 + Int(rng.next() % 900)                 // 600–1500 words (past the crash threshold)
            let every = 5 + Int(rng.next() % 5)
            let base = makeWords(count: n, distinctiveEvery: every, rng: &rng)

            // Build the compared witness by SHUFFLING blocks of the base (moves) and peppering edits — the
            // reordering that makes anchors non-monotonic in B.
            var comp = base
            let blocks = 4 + Int(rng.next() % 6)
            let blockLen = max(1, comp.count / (blocks * 2))
            for _ in 0..<blocks {
                let from = Int(rng.next() % UInt64(max(1, comp.count - blockLen)))
                let to = Int(rng.next() % UInt64(max(1, comp.count - blockLen)))
                let moved = Array(comp[from..<from + blockLen])
                comp.removeSubrange(from..<from + blockLen)
                let ins = min(to, comp.count)
                comp.insert(contentsOf: moved, at: ins)
            }
            for _ in 0..<(Int(rng.next() % 20)) {               // scattered edits
                let k = Int(rng.next() % UInt64(max(1, comp.count)))
                comp[k] = "e\(rng.next() % 9999)"
            }

            // The assertion is simply that this returns — pre-fix it trapped and aborted the process.
            let r = Collation.collate(base: witness("A", base), compared: witness("B", comp))
            XCTAssertGreaterThanOrEqual(r.variations.count, 0, "seed \(seed): collation must complete")
        }
    }
}
