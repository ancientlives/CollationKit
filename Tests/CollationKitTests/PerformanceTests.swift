import XCTest
@testable import CollationKit

// Scale / performance: the original acceptance criterion is "determinism + performance on a multi-thousand-word
// document". The anchor pass chunks the O(n·m) Needleman–Wunsch between unique landmarks, so a lightly-edited
// long document aligns in small regions rather than one giant matrix — these tests guard that.

final class PerformanceTests: XCTestCase {

    /// A deterministic pseudo-prose generator (no randomness → reproducible) of `wordCount` words across
    /// `pages` pages, with sentence/paragraph structure so the tokenizer's boundaries are exercised.
    ///
    /// IMPORTANT: real prose has a *distinctive* vocabulary, so unique anchor n-grams are plentiful and the
    /// anchor pass chunks NW into small regions. To represent that honestly (and not the pathological
    /// low-diversity case — see DEVELOPMENT_LOG 2026-06-27), each word is made distinctive by appending its
    /// running index, mimicking the local uniqueness of natural language.
    private func makeText(wordCount: Int, pages: Int) -> String {
        let lexicon = ["the", "ship", "moved", "slowly", "across", "a", "grey", "and", "restless", "sea",
                       "while", "gulls", "wheeled", "above", "the", "harbour", "in", "the", "fading", "light"]
        var words: [String] = []
        words.reserveCapacity(wordCount)
        for i in 0..<wordCount {
            // Distinctive every few words so unique n-grams exist (as in real prose), while keeping common
            // function words repeated.
            let base = lexicon[i % lexicon.count]
            words.append(i % 3 == 0 ? "\(base)\(i)" : base)
        }
        // Insert paragraph breaks every ~40 words and a page break at each page boundary.
        let perPage = max(1, wordCount / pages)
        var out = ""
        for (i, word) in words.enumerated() {
            out += word
            if (i + 1) % perPage == 0 && i + 1 < wordCount { out += "\n\n<!-- page break -->\n\n" }
            else if (i + 1) % 12 == 0 { out += ".\n\n" }
            else { out += " " }
        }
        return out
    }

    func testCollatesAFewThousandWordsWithLightEditsQuickly() {
        let base = makeText(wordCount: 4000, pages: 20)
        // Compared: same text with a handful of single-word substitutions scattered through it (the
        // distinctive indexed tokens make reliable, locatable edit sites).
        // Edit sites: indices divisible by 3 carry a distinctive suffixed token "<word><idx>".
        var compared = base
        let lexicon = ["the", "ship", "moved", "slowly", "across", "a", "grey", "and", "restless", "sea",
                       "while", "gulls", "wheeled", "above", "the", "harbour", "in", "the", "fading", "light"]
        for idx in [300, 1500, 2700, 3600] {
            let token = "\(lexicon[idx % lexicon.count])\(idx)"
            compared = compared.replacingOccurrences(of: token, with: "REVISED\(idx)")
        }
        let a = Witness(id: "base", text: base)
        let b = Witness(id: "rev", text: compared)

        let start = Date()
        let result = Collation.collate(base: a, compared: b)
        let elapsed = Date().timeIntervalSince(start)

        // The anchor pass chunks NW into small regions for distinctive prose, so a 4k-word lightly-edited
        // collation is near-instant. A generous ceiling guards against a regression to full-matrix behaviour.
        XCTAssertGreaterThan(result.variations.count, 0)
        XCTAssertLessThan(elapsed, 1.0, "4k-word collation of distinctive prose should be well under a second; took \(elapsed)s")
    }

    func testIdenticalLongDocumentsHaveNoVariants() {
        let text = makeText(wordCount: 3000, pages: 15)
        let r = Collation.collate(base: Witness(id: "a", text: text), compared: Witness(id: "b", text: text))
        XCTAssertTrue(r.variations.isEmpty, "a document collated against itself has no variants")
    }

    func testLongCollationIsDeterministic() {
        let base = makeText(wordCount: 2000, pages: 10)
        // `ship621` is a real token (word 621: lexicon index 1, distinctive because 621 % 3 == 0). An earlier version
        // replaced `ship600`, which never occurs, so the two witnesses were identical.
        XCTAssertTrue(base.contains("ship621 "))
        let compared = base.replacingOccurrences(of: "ship621 ", with: "vessel621 ")
        let a = Witness(id: "a", text: base), b = Witness(id: "b", text: compared)
        let first = Collation.collate(base: a, compared: b)
        XCTAssertFalse(first.variations.isEmpty, "the substitution is detected")
        XCTAssertEqual(first, Collation.collate(base: a, compared: b))
    }
}
