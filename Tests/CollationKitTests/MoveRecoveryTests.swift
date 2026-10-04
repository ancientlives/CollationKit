import XCTest
@testable import CollationKit

// MARK: - Single/short-word move recovery (the displaced-reading post-pass)
//
// The anchor pass needs unique n-gram (n ≥ 2) landmarks, so a word (or short phrase) that moves ALONE has no
// shared bigram anchor and the monotonic NW reports it as a deletion + an insertion — the diff artifact the
// engine exists to avoid. A post-classification pass recovers these: a base word under a deletion whose
// normalised key matches a compared word under an insertion, unique on each side, is reclassified as one
// `.transposition` (confidence = .certain). These tests pin that it fires when it should and — critically —
// does NOT fabricate moves when it shouldn't.

final class MoveRecoveryTests: XCTestCase {

    private func w(_ id: String, _ t: String) -> Witness { Witness(id: id, text: t) }
    private func collate(_ a: String, _ b: String) -> CollationResult {
        Collation.collate(base: w("A", a), compared: w("B", b))
    }

    func testSingleWordMoveIsTranspositionNotDeleteInsert() {
        // The motivating case: `author` MOVED; `is` was added. Must NOT be delete(author)+insert(author).
        let r = collate("the well-known author", "the author is well known")
        let trans = r.variations.filter { $0.type == .transposition }
        XCTAssertEqual(trans.count, 1, "the moved word must be one transposition")
        XCTAssertEqual(trans.first?.baseReading, "author")
        XCTAssertEqual(trans.first?.comparedReading, "author")
        XCTAssertEqual(trans.first?.confidence, .certain)
        // The genuinely new word stays an insertion; nothing is a deletion (author wasn't deleted).
        XCTAssertEqual(r.insertions, 1)
        XCTAssertEqual(r.deletions, 0, "`author` moved — it was NOT deleted")
        XCTAssertTrue(r.variations.contains { $0.type == .insertion && $0.comparedReading == "is" })
    }

    func testMovedPhraseStaysOneBlock() {
        // A two-word phrase that moves together is ONE transposition (block-coalesced), not two.
        let r = collate("she opened the door at last", "at last she opened the door")
        let trans = r.variations.filter { $0.type == .transposition }
        XCTAssertEqual(trans.count, 1, "`at last` moved as a unit → one transposition")
        XCTAssertEqual(trans.first?.baseReading, "at last")
        XCTAssertEqual(trans.first?.comparedReading, "at last")
    }

    func testGenuineDeletionIsNotTurnedIntoAMove() {
        // `black` is deleted and appears nowhere in the compared text → must stay a deletion, not become a move.
        let r = collate("the big black cat sat", "the big cat sat")
        XCTAssertEqual(r.deletions, 1)
        XCTAssertEqual(r.transpositions, 0, "a word that truly vanished is a deletion, not a move")
        XCTAssertTrue(r.variations.contains { $0.type == .deletion && $0.baseReading == "black" })
    }

    func testGenuineInsertionIsNotTurnedIntoAMove() {
        let r = collate("the cat sat", "the black cat sat")
        XCTAssertEqual(r.insertions, 1)
        XCTAssertEqual(r.transpositions, 0, "a genuinely new word is an insertion, not a move")
    }

    func testRepeatedWordMoveIsMarkedLikelyNotCertain() {
        // When the displaced word RECURS (not globally unique), the deleted/inserted occurrences were paired
        // by elimination — plausible but not guaranteed. The pass may report it, but MUST mark it `.likely`
        // (surfaced as a "possible move"), never assert it as `.certain`. This is the confidence design at work.
        let r = collate("the red cat and the blue cat", "the red the blue cat and cat")
        for v in r.variations where v.type == .transposition {
            let recurs = ["the", "cat"].contains(v.baseReading)
            if recurs {
                XCTAssertEqual(v.confidence, .likely,
                    "a move of a recurring word must be reported as possible (.likely), not asserted")
            }
        }
    }

    // MARK: rarity / locality gate — a lone leftover of a COMMON word, far off the diagonal, is not a move
    //
    // The 1:1 test above is over the UNMATCHED words only. A word that is common in a witness but matched at all but
    // one of its occurrences is left unmatched exactly once, so it PASSES the 1:1 test; the §5.6 displacement gate
    // then only rejects pairings FAR from the co-linear diagonal, and two parallel translations put a common word's
    // stray leftover NEAR the diagonal by coincidence. Result: a phantom move. The real Verne case: Towle uses
    // "quietly" 5×; moonvoyage deletes the one clause containing its single "quietly"; the leftovers pair thousands
    // of tokens apart (diagonal deviation 5375) as a phantom `.likely` transposition to an unrelated sentence.
    //
    // The rarity/locality gate (Option 1, DEVELOPMENT_LOG 2026-07-15) keeps a recovered move only if it is
    // corroborated: globally unique (unambiguous), OR a multi-word block (a phrase corroborates itself), OR a
    // genuinely LOCAL single-word hop (diagonal deviation ≤ Transposition.localMoveTokens). A lone, common,
    // NON-local word — the coincidence signature — is dropped, reverting to the plain deletion + insertion the
    // aligner already found. Genuine unique-word moves, phrase moves, and short repeated-word hops are unaffected.
    // On the Verne full-novel pair this dropped all 26 far coincidences and kept the one genuine local hop
    // ("firearms", deviation 46) — `certain` moves (106) untouched.

    func testCommonWordFarCoincidenceIsNotAMove() {
        // The Verne "quietly" shape, distilled. "flag" occurs twice on each side. One occurrence sits in a SHARED
        // anchor context ("keep the flag flying high always here now") the aligner matches; the OTHER is a lone
        // stray — at the very start of the base, the very end of the compared, ~600 tokens apart with all-distinct
        // filler between, so it never shares an anchor and stays unmatched. The 1:1-among-unmatched test pairs the
        // two strays (one each), and their diagonal deviation is enormous (≫ localMoveTokens) — a coincidence, not
        // a move. Before the locality gate this surfaced as a phantom `.likely` transposition; it must now stay a
        // deletion + an insertion.
        let uniqueA = (0..<300).map { "alpha\($0)" }.joined(separator: " ")
        let uniqueB = (0..<300).map { "beta\($0)" }.joined(separator: " ")
        let shared = "keep the flag flying high always here now"
        let r = collate("flag \(uniqueA) \(shared)", "\(shared) \(uniqueB) flag")
        XCTAssertTrue(r.variations.filter { $0.type == .transposition }.isEmpty,
            "a lone leftover of a common word, far off the diagonal, is a coincidence, not a move")
        // And the strays survive as the plain deletion + insertion the aligner found (never silently dropped).
        XCTAssertTrue(r.variations.contains { $0.type == .deletion && $0.baseReading.contains("flag") })
        XCTAssertTrue(r.variations.contains { $0.type == .insertion && $0.comparedReading.contains("flag") })
    }

    func testGloballyUniqueSingleWordMoveSurvivesTheGate() {
        // A genuinely displaced word that is globally unique on BOTH sides must still be recovered as a `.certain`
        // move, however far it travelled — its uniqueness is the corroboration. The gate must not suppress it.
        let r = collate("the well-known author", "the author is well known")
        let trans = r.variations.filter { $0.type == .transposition }
        XCTAssertEqual(trans.count, 1)
        XCTAssertEqual(trans.first?.baseReading, "author")
        XCTAssertEqual(trans.first?.confidence, .certain)
    }

    func testLocalHopOfARecurringWordSurvivesTheGate() {
        // The locality escape (source 3): a RECURRING word (not globally unique) that hops a SHORT distance is a
        // real move and must be kept. "author" recurs twice on each side; the first occurrence swaps a couple of
        // positions with its neighbours — a small diagonal deviation, well within localMoveTokens.
        let r = collate("the author wrote well and the author was famous end",
                        "the wrote well author and the author was famous end")
        let trans = r.variations.filter { $0.type == .transposition && $0.baseReading == "author" }
        XCTAssertEqual(trans.count, 1, "a short local hop of a recurring word is still recovered")
        XCTAssertEqual(trans.first?.confidence, .likely, "recurring ⇒ paired by elimination ⇒ likely, but kept")
    }

    func testDiagonalDeviationMeasuresOffDiagonalDistance() {
        // The metric the locality gate reads: deviation of the actual B position from the diagonal expectation
        // round(delTok · |B|/|A|). On equal-length witnesses the diagonal is the identity, so deviation = |ins−del|.
        XCTAssertEqual(Transposition.diagonalDeviation(delTok: 100, insTok: 100, aCount: 1000, bCount: 1000), 0)
        XCTAssertEqual(Transposition.diagonalDeviation(delTok: 100, insTok: 260, aCount: 1000, bCount: 1000), 160)
        // Unequal lengths: expected(100) = round(100 · 500/1000) = 50, so |70 − 50| = 20.
        XCTAssertEqual(Transposition.diagonalDeviation(delTok: 100, insTok: 70, aCount: 1000, bCount: 500), 20)
        // Degenerate lengths are safe (no move context) → 0, not a crash.
        XCTAssertEqual(Transposition.diagonalDeviation(delTok: 5, insTok: 9, aCount: 0, bCount: 0), 0)
    }

    func testLocalMoveTokensSeparatesTheVerneObservedPopulations() {
        // Guard the calibration itself: the bound must sit strictly between the observed genuine-local single-word
        // move ("firearms", deviation 46) and the nearest observed coincidence ("p", deviation 141). If someone
        // retunes localMoveTokens outside this window they will re-admit coincidences or drop the real hop — this
        // fails loudly and points at the corpus evidence in `Transposition.localMoveTokens`.
        XCTAssertGreaterThan(Transposition.localMoveTokens, 46, "must keep the genuine local hop (firearms, dev 46)")
        XCTAssertLessThan(Transposition.localMoveTokens, 141, "must drop the nearest coincidence (p, dev 141)")
    }

    // MARK: anchor-path distinctiveness gate — a SHORT anchor block that is not truly local is not a move
    //
    // The §6.1 gate above hardens the DISPLACED-READING recovery path. The ANCHOR-spine path (`Transposition.align`)
    // has its own coincidence class: a short common-word phrase ("off the rocks", "I look at", "we ought always to")
    // is unique as a joined n-gram yet recurs by coincidence in two unrelated sentences of two independent
    // translations, so it becomes an off-spine anchor and is reported as a move. The distinctiveness-scaled gate
    // (`anchorMoveTolerance`) rejects a SHORT block that is not truly local while still admitting a LONG distinctive
    // passage that legitimately relocated.
    //
    // RECALIBRATED 2026-07-24: the original tuning (base 80 / free 4 / per 40) was fit only on earth-to-moon, where
    // the phantoms sat FAR off the diagonal (dev 249–1962), and it did NOT generalise — a four-pair audit
    // (journey-to-the-centre, earth-to-moon, 20,000-leagues, mysterious-island) showed it admitted ALL 48 detected
    // "moves", every one false, because on tightly-parallel translations a coincidental short phrase lands only
    // 5–100 tokens off the diagonal, inside the flat-80 base. The new base 10 / free 14 / per 18 requires a short
    // block to be genuinely LOCAL: 48 → 11 false positives across the four pairs, every conformance golden + the
    // Calamus relocation preserved. See DEVELOPMENT_LOG 2026-07-24, PAPER_NOTES §4.5.2, ALGORITHMS §5.6.

    func testAnchorMoveToleranceScalesWithBlockLength() {
        // RECALIBRATED 2026-07-24 (four-pair audit): a block up to the free length earns only the small absolute
        // base bound (`anchorBlockBaseTolerance`, distinct from `localMoveTokens`); each token PAST the free length
        // buys `distinctivenessPerToken` more. The free length is now 14 (was 4) and the base 10 (was 80) — so a
        // short block must be genuinely LOCAL, closing the near-diagonal coincidence class the old flat-80 base let
        // through ("off the rocks", "I look at"). See `Transposition.anchorMoveTolerance`.
        XCTAssertEqual(Transposition.anchorMoveTolerance(blockLength: 3), Transposition.anchorBlockBaseTolerance,
            "a 3-gram (≤ free length) earns only the base bound — it must be genuinely local")
        XCTAssertEqual(Transposition.anchorMoveTolerance(blockLength: Transposition.distinctivenessFreeLength),
            Transposition.anchorBlockBaseTolerance,
            "at exactly the free length the block still earns only the base bound")
        XCTAssertEqual(Transposition.anchorMoveTolerance(blockLength: Transposition.distinctivenessFreeLength + 1),
            Transposition.anchorBlockBaseTolerance + Transposition.distinctivenessPerToken,
            "one token past free length buys one per-token increment")
        XCTAssertEqual(Transposition.anchorMoveTolerance(blockLength: Transposition.distinctivenessFreeLength + 5),
            Transposition.anchorBlockBaseTolerance + Transposition.distinctivenessPerToken * 5,
            "a long distinctive passage earns a large tolerance (the Calamus-scale move)")
    }

    func testAnchorBlockGateSeparatesTheObservedPopulations() {
        // Guard the RECALIBRATED gate (2026-07-24) on the measured populations from the four independent-translation
        // full-novel pairs (comparable-key space, engine-measured). Same-length witnesses ⇒ diagonal is identity, so
        // dev = |bStart − aStart|.
        let n = 80_000
        // FALSE moves that MUST now be REJECTED — short blocks off the diagonal (the reported class):
        //   "our calculation. Here …" 10|217, the Cambridge phantom 14|249, "we ought always to" 4|1680,
        //   "enfilading, or point-blank firing" 5|37 (near-diagonal aligned text, not a real relocation).
        XCTAssertFalse(Transposition.anchorBlockIsPlausible(aStart: 46_000, bStart: 46_000 + 217,
            blockLength: 10, aCount: n, bCount: n), "a 10-token block 217 off the diagonal is a coincidence")
        XCTAssertFalse(Transposition.anchorBlockIsPlausible(aStart: 19_537, bStart: 19_537 + 249,
            blockLength: 14, aCount: n, bCount: n), "a 14-token block 249 off the diagonal is a coincidence")
        XCTAssertFalse(Transposition.anchorBlockIsPlausible(aStart: 50_000, bStart: 50_000 - 1680,
            blockLength: 4, aCount: n, bCount: n), "short common-phrase anchor 1680 off the diagonal is a coincidence")
        XCTAssertFalse(Transposition.anchorBlockIsPlausible(aStart: 145, bStart: 145 + 37,
            blockLength: 5, aCount: n, bCount: n), "a short block 37 off the diagonal is NOT a real move (near-diagonal artifact)")
        // GENUINE moves that MUST be KEPT:
        //   the recursive-anchoring sentence-swap 11|9 (short but truly local); the "same weather" passage 24|63;
        //   the Whitman Calamus poem-cluster relocation 19|84 — a long distinctive block earns the distance.
        XCTAssertTrue(Transposition.anchorBlockIsPlausible(aStart: 100, bStart: 100 + 9,
            blockLength: 11, aCount: n, bCount: n), "an 11-token sentence-swap only 9 off the diagonal is a real local move")
        XCTAssertTrue(Transposition.anchorBlockIsPlausible(aStart: 50_450, bStart: 50_450 + 63,
            blockLength: 24, aCount: n, bCount: n), "a 24-token passage 63 off the diagonal is a real move")
        XCTAssertTrue(Transposition.anchorBlockIsPlausible(aStart: 60_000, bStart: 60_000 + 84,
            blockLength: 19, aCount: n, bCount: n), "the 19-token Calamus relocation (dev 84) is a real move")
        // Degenerate lengths are safe → treated as plausible, not a crash.
        XCTAssertTrue(Transposition.anchorBlockIsPlausible(aStart: 0, bStart: 0, blockLength: 3, aCount: 0, bCount: 0))
    }

    func testShortCommonPhraseFarOffDiagonalIsNotAnAnchorMove() {
        // End-to-end, the earth-to-moon shape distilled: the SAME short common phrase ("we ought always to") occurs
        // once in each witness in UNRELATED sentences ~600 tokens apart, surrounded by all-distinct filler. It is a
        // unique-in-both n-gram → an anchor → off the spine (far from its diagonal position). Before the gate this
        // was a phantom `.certain` transposition spanning ~600 tokens; it must now revert to deletion + insertion.
        let fillerA = (0..<300).map { "alpha\($0)" }.joined(separator: " ")
        let fillerB = (0..<300).map { "beta\($0)" }.joined(separator: " ")
        let phrase = "we ought always to"
        let a = "\(phrase) treat him well \(fillerA)"          // phrase near the START of A
        let b = "\(fillerB) I think \(phrase) do this"          // phrase near the END of B
        let r = collate(a, b)
        let phantom = r.variations.filter {
            $0.type == .transposition && $0.baseReading.contains("ought")
        }
        XCTAssertTrue(phantom.isEmpty,
            "a short common phrase recurring by coincidence far off the diagonal is NOT a move")
    }

    func testShortCommonPhraseNEARtheDiagonalIsNotAnAnchorMove() {
        // The 2026-07-24 finding (a reported case on Journey to the Centre): the same short phrase occurs once in
        // each witness in UNRELATED sentences that, because two translations run in parallel, land only a little off
        // the diagonal (here ~15 tokens). The OLD gate (flat base 80) admitted this; the recalibrated gate (base 10)
        // requires a short block to be genuinely local, so it must NOT be a move — it reverts to substitution/edit.
        // Distinct filler on both sides keeps every other token from aligning, isolating the phrase as the only
        // unique-in-both anchor.
        let phrase = "off the rocks"
        // A: phrase at ~token 100. B: same phrase at ~token 115 (≈15 off the diagonal), each in unrelated context.
        let a = (0..<100).map { "alpha\($0)" }.joined(separator: " ") + " pull moss \(phrase) below "
              + (0..<100).map { "gamma\($0)" }.joined(separator: " ")
        let b = (0..<115).map { "beta\($0)" }.joined(separator: " ") + " holding myself \(phrase) above "
              + (0..<100).map { "delta\($0)" }.joined(separator: " ")
        let r = collate(a, b)
        let phantom = r.variations.filter { $0.type == .transposition && $0.baseReading.contains("rocks") }
        XCTAssertTrue(phantom.isEmpty,
            "a short common phrase near-but-not-on the diagonal, in unrelated context, is NOT a move (2026-07-24 gate)")
    }

    // (The long-distinctive-passage ESCAPE — a long block off the diagonal is kept where a short one is dropped —
    // is verified directly and precisely at the gate function in `testAnchorBlockGateSeparatesTheObservedPopulations`
    // above, on the engine-measured full-novel numbers; that is the honest layer for the calibration, rather
    // than a fragile synthetic reproduction of a whole-passage relocation.)

    func testUniqueWordMoveIsCertain() {
        // A globally-unique displaced word is an unambiguous move → `.certain`.
        let r = collate("alpha bravo charlie", "charlie alpha bravo")
        let trans = r.variations.filter { $0.type == .transposition }
        XCTAssertFalse(trans.isEmpty)
        XCTAssertTrue(trans.allSatisfy { $0.confidence == .certain })
    }

    func testNonTranspositionVariantsAreAlwaysCertain() {
        let r = collate("the quick brown fox", "the slow brown fox")
        for v in r.variations where v.type != .transposition {
            XCTAssertEqual(v.confidence, .certain, "only transpositions can be less than certain")
        }
    }

    func testRecoveredMoveIsDeterministic() {
        let a = "alpha bravo charlie delta echo", b = "charlie alpha bravo delta echo"
        XCTAssertEqual(collate(a, b), collate(a, b))
    }

    // MARK: anchor-move confidence is scale-relative (2026-07-24 — the gate residual is `.likely`, not asserted)
    //
    // A SHORT anchor block that passes the distinctiveness gate only by sitting near the diagonal is the gate's
    // irreducible residual: it cannot be dropped (a genuine 1–2-token move is geometrically identical), so on a
    // LONG parallel pair it is reported as a *possible* move (`.likely`), never asserted (`.certain`). In a SHORT
    // witness the same block is a real swap and stays `.certain`.

    func testAnchorMoveConfidenceIsScaleRelative() {
        // Distinctive by length → certain, regardless of witness size.
        XCTAssertTrue(Transposition.anchorMoveIsCertain(
            blockLength: Transposition.distinctivenessFreeLength + 1, aCount: 200_000, bCount: 200_000),
            "a block longer than the free length is corroborated by its own length ⇒ certain")
        // Short block in a SHORT witness → a real swap ⇒ certain (protects crafted goldens 04/05).
        XCTAssertTrue(Transposition.anchorMoveIsCertain(blockLength: 2, aCount: 10, bCount: 6),
            "a short block in a short witness is a meaningful-fraction swap ⇒ certain")
        // Short block in a LONG parallel witness → possible only ⇒ likely (the "off the rocks" residual).
        XCTAssertFalse(Transposition.anchorMoveIsCertain(blockLength: 3, aCount: 86_000, bCount: 100_000),
            "a short block in a long parallel witness is a possible move ⇒ likely")
        // The floor is the boundary.
        XCTAssertTrue(Transposition.anchorMoveIsCertain(
            blockLength: 3, aCount: Transposition.confidentMoveWitnessFloor, bCount: 100),
            "at the witness floor a short block is still certain")
        XCTAssertFalse(Transposition.anchorMoveIsCertain(
            blockLength: 3, aCount: Transposition.confidentMoveWitnessFloor + 1, bCount: 100),
            "just past the floor a short block softens to likely")
    }

    func testShortNearDiagonalMoveOnLongPairIsLikelyNotCertain() {
        // End-to-end: a short phrase displaced by a few tokens on a LONG pair (above the 4,000-token
        // `confidentMoveWitnessFloor`). It passes the gate (near the diagonal) but must be reported as a POSSIBLE
        // move, not asserted. (This is the "off the rocks" reported case.) The witnesses share a backbone so the
        // phrase is genuinely off the spine; an earlier version shared nothing else, so no move was ever produced
        // and the assertion loop never ran.
        let phrase = ["off", "the", "rocks"]
        let backbone = (0..<6000).map { "s\($0)" }
        let a = (Array(backbone[..<3001]) + phrase + Array(backbone[3001...])).joined(separator: " ")
        let b = (Array(backbone[..<3011]) + phrase + Array(backbone[3011...])).joined(separator: " ")
        let moves = collate(a, b).variations.filter { $0.type == .transposition && $0.baseReading.contains("rocks") }
        XCTAssertEqual(moves.count, 1, "the displaced phrase is recovered as one move")
        XCTAssertEqual(moves.first?.confidence, .likely,
            "a short near-diagonal move on a long parallel pair is a possible move (.likely), not asserted")
    }

    // MARK: displacement gate — reject far-apart COINCIDENCES, keep genuine LOCAL moves
    //
    // Two aligned witnesses are globally co-linear. A real transposition is a LOCAL excursion off the diagonal;
    // a rare word/phrase that happens to be unique in each witness but sits a large fraction of the document
    // apart is a COINCIDENCE, not a move. Before the gate, two independent translations of a novel produced
    // hundreds of nonsense "certain" moves spanning most of the book (and they corrupted the surrounding
    // alignment). The gate (a diagonal-deviation bound, shared by the anchor and displaced-word paths) rejects
    // those; a rejected pair stays an ordinary deletion + insertion. See DEVELOPMENT_LOG 2026-07-08.

    func testFarApartCoincidentalWordIsNotAMove() {
        // The SAME rare word appears once early in the base and once LATE in the compared, with unrelated filler
        // between so it never forms a shared phrase-anchor. Co-linearly these are different textual points → it
        // must NOT be reported as a move (which would be a book-spanning transposition), but as del + ins.
        let filler = Array(repeating: "padding", count: 1200)
        // base: rareword near the start; compared: rareword near the very end.
        let a = (["rareword"] + filler.map { $0 + "a" }).joined(separator: " ")
        let b = (filler.map { $0 + "b" } + ["rareword"]).joined(separator: " ")
        let r = collate(a, b)
        XCTAssertTrue(r.variations.filter { $0.type == .transposition }.isEmpty,
            "a unique word at co-linearly distant positions is a coincidence, not a transposition")
    }

    func testLocalMoveStillDetectedDespiteTheGate() {
        // A genuinely LOCAL move (a word hops a few words) is well within the diagonal tolerance and must still
        // be recovered — the gate must not throw the baby out with the bathwater.
        let r = collate("the well-known author of many books",
                        "the author of many books is well known")
        XCTAssertGreaterThanOrEqual(r.variations.filter { $0.type == .transposition }.count, 1,
            "a local move is still recovered — the gate only rejects far coincidences")
    }

    func testMoveToleranceScalesButIsBounded() {
        // Sanity on the shared bound: proportional for mid-size inputs, floored for tiny, capped for huge.
        XCTAssertEqual(Transposition.moveTolerance(aCount: 100, bCount: 100), Transposition.minMoveTokens,
            "tiny inputs use the floor")
        XCTAssertEqual(Transposition.moveTolerance(aCount: 100_000, bCount: 100_000), 3_000,
            "mid inputs use the fraction (0.03·100k)")
        XCTAssertEqual(Transposition.moveTolerance(aCount: 10_000_000, bCount: 10_000_000),
            Transposition.maxMoveTokens, "huge inputs are capped")
    }

    // MARK: expanding-window search — nearest-first, widen only when unambiguous
    //
    // Refinement of the fixed gate: rather than a hard co-linearity cutoff, prefer the NEAREST candidate and
    // reach further out only when the near neighbourhood has no unambiguous match. This admits a genuinely large
    // but singular move a fixed bound would reject, while still refusing to guess among roughly-equidistant far
    // coincidences. `pairByExpandingWindow` is the unit under test. See DEVELOPMENT_LOG 2026-07-08.

    func testExpandingWindowAcceptsNearPairAsNear() {
        // A single pair right on the diagonal → accepted, flagged `near` (⇒ eligible for `certain`).
        let pairs = Transposition.pairByExpandingWindow(delPositions: [10], insPositions: [10],
                                                        aCount: 1000, bCount: 1000)
        XCTAssertEqual(pairs, [Transposition.WindowPair(delTok: 10, insTok: 10, near: true)])
    }

    func testExpandingWindowAcceptsFarButUnambiguousPairAsNotNear() {
        // One unique pair, far from the diagonal but within the ceiling and with no rival → accepted by WIDENING
        // and flagged NOT near (⇒ at best `likely`). This is the refinement's win over the fixed hard cutoff.
        let a = 100_000, b = 100_000                       // near tolerance = 3000
        let pairs = Transposition.pairByExpandingWindow(delPositions: [1000], insPositions: [5500],
                                                        aCount: a, bCount: b)   // deviation 4500 > 3000, < 6000
        XCTAssertEqual(pairs, [Transposition.WindowPair(delTok: 1000, insTok: 5500, near: false)])
    }

    func testExpandingWindowRejectsBeyondTheCeiling() {
        // Beyond `maxMoveTokens` from the diagonal → never paired, however unambiguous.
        let pairs = Transposition.pairByExpandingWindow(delPositions: [0], insPositions: [50_000],
                                                        aCount: 100_000, bCount: 100_000)
        XCTAssertTrue(pairs.isEmpty, "a candidate past the far ceiling is a coincidence, not a move")
    }

    func testExpandingWindowRefusesAmbiguousFarCandidates() {
        // Two insertion occurrences at comparable FAR distances from the one deletion's diagonal expectation:
        // no basis to say which moved → decline (leave as plain del + ins). (Near pairs would be accepted; these
        // are both in the widen zone and within ~2× of each other.)
        let pairs = Transposition.pairByExpandingWindow(delPositions: [1000], insPositions: [5000, 5800],
                                                        aCount: 100_000, bCount: 100_000)  // exp≈1000; devs 4000,4800
        XCTAssertTrue(pairs.isEmpty, "roughly-equidistant far rivals are ambiguous — refuse to guess")
    }

    func testExpandingWindowPrefersTheNearerOfTwo() {
        // A near candidate and a far candidate for the same deletion: the NEAR one wins (nearest-first).
        let pairs = Transposition.pairByExpandingWindow(delPositions: [1000], insPositions: [1200, 5500],
                                                        aCount: 100_000, bCount: 100_000)  // exp≈1000; devs 200,4500
        XCTAssertEqual(pairs, [Transposition.WindowPair(delTok: 1000, insTok: 1200, near: true)],
            "the nearest (within-tolerance) candidate is chosen")
    }
}
