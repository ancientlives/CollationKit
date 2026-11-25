import XCTest
@testable import CollationKit

// MARK: - Substitutions in the base-anchored graph (release 1 review, blocker B2)
//
// The default N-witness merge folds each pairwise substitution onto the base nodes it covers. It used to pair the
// k-th base token with the k-th compared token over FULL-token ranges (punctuation included) and discard any compared
// tokens past the base range's length, so it invented punctuation readings (`green] ,`), dropped compared words
// (`red] very`, losing "bright blue") and repeated the last compared word on surplus base nodes (`old] young`,
// `grey] young`). These tests pin the corrected fold (`TokenGraph.substitutionReading`).

final class GraphSubstitutionTests: XCTestCase {

    /// The base-anchored graph's readings per base node, as `reading → sigla`, keyed by base position.
    private func readings(_ texts: [(String, String)]) -> [Int: [String: Set<String>]] {
        let graph = Collation.variantGraph(witnesses: texts.map { Witness(id: $0.0, text: $0.1) })
        var out: [Int: [String: Set<String>]] = [:]
        for node in graph.nodes where node.basePosition >= 0 { out[node.basePosition] = node.readings }
        return out
    }

    private func reading(of witness: String, at basePosition: Int, in r: [Int: [String: Set<String>]]) -> String? {
        r[basePosition]?.first { $0.value.contains(witness) }?.key
    }

    func testPunctuationIsNotPairedWithAWord() {
        // "red green" → "blue, yellow": the comma must not become green's reading, and "yellow" must not vanish.
        let r = readings([("A", "I saw red green things today"), ("B", "I saw blue, yellow things today")])
        XCTAssertEqual(reading(of: "B", at: 2, in: r), "blue")
        XCTAssertEqual(reading(of: "B", at: 3, in: r), "yellow")
    }

    func testALongerComparedReadingIsKeptWhole() {
        // "red" → "very bright blue": before the fix only "very" survived.
        let r = readings([("A", "I saw the red things today at noon"), ("B", "I saw the very bright blue things today at noon")])
        XCTAssertEqual(reading(of: "B", at: 3, in: r), "very bright blue")
    }

    func testAShorterComparedReadingOmitsTheSurplusBaseWords() {
        // "old grey" → "young": "young" belongs to one base node; the other is omitted, not a second "young".
        let r = readings([("A", "the old grey wolf ran home"), ("B", "the young wolf ran home")])
        XCTAssertEqual(reading(of: "B", at: 1, in: r), "young")
        XCTAssertEqual(reading(of: "B", at: 2, in: r), "∅")
    }

    func testSubstitutionReadingRule() {
        let tokens = Tokenizer.tokenize("alpha beta gamma", with: .substantive)
        let words = tokens.indices.filter { tokens[$0].isComparable }
        // Equal counts → one-to-one.
        XCTAssertEqual(TokenGraph.substitutionReading(forBaseNode: 1, of: 3, compWords: words, compTokens: tokens).surface, "beta")
        // More compared words than base nodes → the last shared node carries the rest.
        XCTAssertEqual(TokenGraph.substitutionReading(forBaseNode: 0, of: 1, compWords: words, compTokens: tokens).surface,
                       "alpha beta gamma")
        XCTAssertEqual(TokenGraph.substitutionReading(forBaseNode: 1, of: 2, compWords: words, compTokens: tokens).surface,
                       "beta gamma")
        // Fewer compared words than base nodes → the surplus nodes are omitted.
        XCTAssertEqual(TokenGraph.substitutionReading(forBaseNode: 3, of: 4, compWords: words, compTokens: tokens).surface, "∅")
        // No compared words at all → omitted.
        XCTAssertEqual(TokenGraph.substitutionReading(forBaseNode: 0, of: 2, compWords: [], compTokens: tokens).surface, "∅")
    }

    func testNoReadingIsBarePunctuationAcrossTheConformanceCorpus() throws {
        // Every golden is produced by the same code path; none may contain a punctuation-only reading again.
        let goldenDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/conformance/golden")
        let files = try FileManager.default.contentsOfDirectory(at: goldenDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            let graph = try XCTUnwrap(json["graph"] as? [String: Any])
            for node in try XCTUnwrap(graph["nodes"] as? [[String: Any]]) {
                for reading in try XCTUnwrap(node["readings"] as? [[String: Any]]) {
                    let text = try XCTUnwrap(reading["reading"] as? String)
                    let punctuationOnly = text != "∅" && !text.isEmpty
                        && text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) || CharacterSet.whitespaces.contains($0) }
                    XCTAssertFalse(punctuationOnly, "\(file.lastPathComponent): punctuation-only reading '\(text)'")
                }
            }
        }
    }
}
