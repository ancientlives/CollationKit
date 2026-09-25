import XCTest
@testable import CollationKit
@testable import CollateCLI

// MARK: - Selectable merge strategy (BACKLOG B13) — the seam, both strategies live since B14
//
// These lock the *architectural seam* that lets a caller choose the N-witness merge strategy
// (`CollationStrategy`). Since B14 landed, `.peerMSA` runs as itself (the peer merge in `PeerMSA.swift`);
// its behavioural acceptance tests live in `PeerMSATests`. Here we pin the enum/policy, the default staying
// non-breaking, and the CLI flag.

final class CollationStrategyTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    // MARK: the enum + policy

    func testAvailability() {
        XCTAssertTrue(CollationStrategy.baseAnchored.isAvailable, "base-anchored is the shipping default")
        XCTAssertTrue(CollationStrategy.peerMSA.isAvailable, "peer MSA runs as itself since B14")
    }

    /// The context-aware default policy (PAPER_NOTES §5.4): a copy-text present → base-privileged; no privileged
    /// witness → peer MSA (available since B14).
    func testContextualDefault() {
        XCTAssertEqual(CollationStrategy.contextualDefault(hasCopyText: true), .baseAnchored)
        XCTAssertEqual(CollationStrategy.contextualDefault(hasCopyText: false), .peerMSA,
                       "no privileged witness → peer MSA now that it is available")
    }

    func testLabelsAreUserFacingPlainLanguage() {
        XCTAssertFalse(CollationStrategy.baseAnchored.label.contains("MSA"), "no jargon in the user label")
        XCTAssertTrue(CollationStrategy.peerMSA.label.lowercased().contains("no base text"),
                      "the peer-MSA label explains WHEN to use it in plain language")
    }

    // MARK: the engine seam

    /// `variantGraph(strategy:)` defaults to `.baseAnchored` and produces the same graph as the no-strategy call
    /// (non-breaking); `.peerMSA` runs as itself and, on a simple substitution-only set where no multi-witness
    /// context is needed, agrees with the lift (parity where nothing peer-specific is at stake).
    func testVariantGraphStrategySeamIsNonBreakingAndPeerAgreesOnSimpleSets() {
        let ws = [w("A", "the cat sat on the mat"), w("B", "the cat sat on a mat"), w("C", "the dog sat on the mat")]
        let defaulted = Collation.variantGraph(witnesses: ws)
        let explicitBase = Collation.variantGraph(witnesses: ws, strategy: .baseAnchored)
        let peer = Collation.variantGraph(witnesses: ws, strategy: .peerMSA)
        XCTAssertEqual(defaulted, explicitBase, "the default IS base-anchored — no behaviour change")
        XCTAssertEqual(peer, explicitBase, "on a simple in-order set the peer merge agrees with the lift")
    }

    /// The JSON interchange threads the strategy too, and the default stays byte-identical (so goldens hold).
    func testJSONOutputStrategyDefaultIsUnchanged() {
        let ws = [w("A", "alpha beta gamma"), w("B", "alpha delta gamma")]
        let defaulted = CollationJSON.outputString(witnesses: ws)
        let explicitBase = CollationJSON.outputString(witnesses: ws, strategy: .baseAnchored)
        XCTAssertEqual(defaulted, explicitBase, "default strategy keeps JSON byte-identical to the goldens")
    }

    // MARK: the CLI flag

    func testCLIParsesStrategyAliases() throws {
        for alias in ["base-anchored", "base", "baseanchored"] {
            let opts = try CLIParser.parseRun(["a.txt", "b.txt", "--strategy", alias])
            XCTAssertEqual(opts.strategy, .baseAnchored, "alias '\(alias)' → base-anchored")
        }
        for alias in ["peer-msa", "peer", "msa"] {
            let opts = try CLIParser.parseRun(["a.txt", "b.txt", "--strategy", alias])
            XCTAssertEqual(opts.strategy, .peerMSA, "alias '\(alias)' → peer-msa")
        }
    }

    func testCLIUnknownStrategyIsUsageError() {
        XCTAssertThrowsError(try CLIParser.parseRun(["a.txt", "b.txt", "--strategy", "bogus"])) { err in
            XCTAssertEqual((err as? CLIError)?.kind, .usage)
        }
    }

    /// Since B14 the CLI ACCEPTS `--strategy peer-msa` (it runs as itself). The old rejection guard remains in
    /// `validate` for any future reserved strategy, but no current strategy trips it.
    func testCLIAcceptsPeerMSA() throws {
        let opts = try CLIParser.parseRun(["a.txt", "b.txt", "--strategy", "peer-msa"])
        XCTAssertNoThrow(try CLIParser.validate(opts))
        XCTAssertEqual(opts.strategy, .peerMSA)
    }

    /// A base-anchored run validates fine (the default path is unaffected).
    func testCLIBaseAnchoredValidates() throws {
        let opts = try CLIParser.parseRun(["a.txt", "b.txt", "--strategy", "base-anchored"])
        XCTAssertNoThrow(try CLIParser.validate(opts))
    }
}
