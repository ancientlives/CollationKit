import XCTest
@testable import CollationKit
@testable import CollateCLI

// MARK: - Configurable scoring presets (BACKLOG B7) — verse vs prose
//
// B7 makes the NW scoring a named genre knob. `.prose` is the historical default (`+2 / −1 / −2`, every
// conformance golden is pinned to it); `.verse` (`+2 / −2 / −1`) makes a gap cheaper than a mismatch so an
// added/dropped whole line surfaces as one insertion/deletion instead of being shredded into word-against-word
// substitutions across a line boundary. These tests lock: the preset→scores mapping, that `.prose` is a
// no-op default (goldens hold — also covered structurally by ConformanceTests), that `.verse` genuinely
// changes the alignment on a whole-line insertion, that the scores thread through the N-witness graph and the
// JSON, and the CLI `--scoring` flag + manifest.

final class ScoringPresetTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    // MARK: the preset → scores mapping

    func testPresetScoresAreTheDocumentedPoints() {
        XCTAssertEqual(AlignmentScores.prose, AlignmentScores(match: 2, mismatch: -1, gap: -2))
        XCTAssertEqual(AlignmentScores.verse, AlignmentScores(match: 2, mismatch: -3, gap: -1))
        XCTAssertEqual(ScoringPreset.prose.scores, .prose)
        XCTAssertEqual(ScoringPreset.verse.scores, .verse)
    }

    /// The default is prose, and prose IS the historical default `AlignmentScores()` — so passing no `scores`
    /// and passing `.prose` are the same run (this is why no golden changes: the default is preserved).
    func testProseIsTheHistoricalDefault() {
        XCTAssertEqual(AlignmentScores.prose, AlignmentScores(), "prose preset == the historical default scores")
        let ws = [w("A", "alpha beta gamma"), w("B", "alpha delta gamma")]
        XCTAssertEqual(CollationJSON.outputString(witnesses: ws),
                       CollationJSON.outputString(witnesses: ws, scores: .prose),
                       "default scoring is prose — byte-identical to the pinned goldens")
    }

    func testLabelsAreUserFacingPlainLanguage() {
        XCTAssertTrue(ScoringPreset.prose.label.lowercased().contains("default"))
        XCTAssertTrue(ScoringPreset.verse.label.lowercased().contains("line"),
                      "the verse label explains WHAT it does (whole-line insert/delete) in plain language")
    }

    // MARK: the behaviour that motivates B7

    /// A reworded span whose replacement text happens to REUSE a word from the original ("the" appears in both
    /// `the quick fox the` and `a slow the bear`). Prose (cheap mismatch) latches onto that coincidental `the`
    /// as an alignment anchor and folds the whole rewrite into a single substitution around it; verse (cheap
    /// gap, so `mismatch < 2·gap`) does NOT treat the recurring function word as a real anchor and reports the
    /// wholesale replacement — a different, and for verse more faithful, apparatus. This is the observable B7
    /// effect: the scoring knob changes how a recurring word inside a rewrite is handled.
    func testVerseAndProseDifferOnARecurringWordInsideARewrite() {
        let base = w("A", "alpha the quick fox the omega")
        let comp = w("B", "alpha a slow the bear omega")

        let prose = Collation.collate(base: base, compared: comp, scores: .prose)
        let verse = Collation.collate(base: base, compared: comp, scores: .verse)

        XCTAssertNotEqual(prose.variations, verse.variations,
                          "verse vs prose scoring produces a different apparatus on a recurring word inside a rewrite")
        // Both keep the shared outer anchors (alpha … omega) — the difference is confined to the reworded span.
        XCTAssertEqual(prose.substitutions, 1, "prose folds the rewrite into one substitution around the recurring 'the'")
        XCTAssertGreaterThan(verse.insertions + verse.deletions, 0,
                             "verse does not anchor on the coincidental 'the' — it reports the wholesale change")
    }

    /// The `mismatch < 2·gap` inequality that defines the verse preset: on a disjoint reworded run (no shared
    /// words), prose prefers word-against-word SUBSTITUTIONS while verse prefers a clean DELETE + INSERT (the
    /// old line dropped, the new line added) — the verse reading of a rewritten line. Asserted at the raw
    /// aligner so it's independent of the classifier's coalescing.
    func testVerseAlignsADisjointRunAsDeleteInsertWhereProseSubstitutes() {
        let base = ["k", "a", "b", "c", "k"]        // k…k anchors; inner a b c fully reworded
        let comp = ["k", "x", "y", "z", "k"]

        let prose = Alignment.needlemanWunsch(base, comp, scores: .prose)
        let verse = Alignment.needlemanWunsch(base, comp, scores: .verse)

        func count(_ ops: [AlignOp], _ pick: (AlignOp) -> Bool) -> Int { ops.filter(pick).count }
        let proseSubs = count(prose) { if case .substitute = $0 { return true }; return false }
        let verseSubs = count(verse) { if case .substitute = $0 { return true }; return false }
        let verseGaps = count(verse) { switch $0 { case .insert, .delete: return true; default: return false } }

        XCTAssertEqual(proseSubs, 3, "prose aligns the reworded run as three substitutions")
        XCTAssertEqual(verseSubs, 0, "verse takes no substitutions in the reworded run")
        XCTAssertEqual(verseGaps, 6, "verse aligns it as 3 deletions + 3 insertions (line dropped, line added)")
    }

    /// Genuinely co-linear text (no added/dropped lines) aligns the same under both presets — matches dominate,
    /// so the knob only bites where the aligner must trade a mismatch against a gap.
    func testColinearTextIsUnaffectedByThePreset() {
        let base = w("A", "the cat sat on the mat")
        let comp = w("B", "the cat sat on a mat")   // one substitution, no length change
        let prose = Collation.collate(base: base, compared: comp, scores: .prose)
        let verse = Collation.collate(base: base, compared: comp, scores: .verse)
        XCTAssertEqual(prose.variations, verse.variations, "co-linear text is scored the same either way")
    }

    // MARK: the scores thread through the N-witness graph and JSON

    /// `variantGraph`/`CollationJSON` accept `scores` and actually use them (the N-witness path went through
    /// `TokenGraph.build`, which previously dropped `scores` — B7 threads it). On the verse-insertion case the
    /// verse-scored graph differs from the prose-scored one.
    func testScoresThreadThroughVariantGraphAndJSON() {
        let ws = [
            w("A", "alpha the quick fox the omega"),
            w("B", "alpha a slow the bear omega"),
        ]
        let proseGraph = Collation.variantGraph(witnesses: ws, scores: .prose)
        let verseGraph = Collation.variantGraph(witnesses: ws, scores: .verse)
        XCTAssertNotEqual(proseGraph, verseGraph, "the scoring preset reaches the N-witness graph")

        XCTAssertNotEqual(CollationJSON.outputString(witnesses: ws, scores: .prose),
                          CollationJSON.outputString(witnesses: ws, scores: .verse),
                          "the scoring preset reaches the JSON interchange")
    }

    // MARK: the CLI flag

    func testCLIParsesScoringPreset() throws {
        let prose = try CLIParser.parseRun(["a.txt", "b.txt", "--scoring", "prose"])
        XCTAssertEqual(prose.scoring, .prose)
        let verse = try CLIParser.parseRun(["a.txt", "b.txt", "--scoring", "verse"])
        XCTAssertEqual(verse.scoring, .verse)
        // Case-insensitive, matching the other flags.
        let upper = try CLIParser.parseRun(["a.txt", "b.txt", "--scoring", "VERSE"])
        XCTAssertEqual(upper.scoring, .verse)
    }

    func testCLIDefaultScoringIsProse() throws {
        let opts = try CLIParser.parseRun(["a.txt", "b.txt"])
        XCTAssertEqual(opts.scoring, .prose, "no --scoring → prose (the non-breaking default)")
    }

    func testCLIUnknownScoringIsUsageError() {
        XCTAssertThrowsError(try CLIParser.parseRun(["a.txt", "b.txt", "--scoring", "haiku"])) { err in
            XCTAssertEqual((err as? CLIError)?.kind, .usage)
        }
    }

    /// The run manifest records the scoring preset used, so an exported result set is self-describing.
    func testManifestRecordsScoring() {
        let ws = [w("A", "alpha beta"), w("B", "alpha gamma")]
        var opts = CLIOptions(explicitFiles: ["a.txt", "b.txt"], scoring: .verse)
        opts.format = .json
        let run = CollationRun(baseID: "A", witnessOrder: ["A", "B"], witnesses: ws,
                               pairs: [], graph: Collation.variantGraph(witnesses: ws), options: opts)
        let manifest = Exporter.manifest(run, timestamp: nil)
        XCTAssertTrue(manifest.contains("scoring: verse"), "the manifest records the scoring preset")
    }
}
