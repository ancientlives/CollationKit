import XCTest
@testable import CollationKit

// Stage-1 tests: tokenization, normalization (substantive vs accidental), and PAGE tracking — the
// foundation that lets later stages report variation "across pages".

final class TokenizerTests: XCTestCase {

    func testWordsAndPunctuationSeparated() {
        let toks = Tokenizer.tokenize("Hello, world!", with: .diplomatic)
        XCTAssertEqual(toks.map { $0.surface }, ["Hello", ",", "world", "!"])
        XCTAssertEqual(toks.map { $0.kind }, [.word, .punctuation, .word, .punctuation])
    }

    func testSubstantiveNormalizationFoldsCaseAndPunctuation() {
        let toks = Tokenizer.tokenize("The Quick, BROWN fox.", with: .substantive)
        let comparable = toks.filter { $0.isComparable }.map { $0.normalized }
        XCTAssertEqual(comparable, ["the", "quick", "brown", "fox"])
        // Punctuation tokens normalize away (not comparable).
        XCTAssertFalse(toks.filter { $0.kind == .punctuation }.contains { $0.isComparable })
    }

    func testParagraphIndexAdvancesOnBlankLine() {
        let toks = Tokenizer.tokenize("first para here\n\nsecond para now", with: .substantive)
        XCTAssertEqual(toks.first { $0.surface == "first" }?.paragraph, 0)
        XCTAssertEqual(toks.first { $0.surface == "second" }?.paragraph, 1)
    }

    func testPageIndexAdvancesAcrossPageBreakMarkers() {
        // Form feed, an HTML page-break comment, and a stand-alone --- all bump the page.
        let text = "page zero text\n\u{0C}\npage one text\n\n<!-- page break -->\npage two text\n\n---\npage three"
        let toks = Tokenizer.tokenize(text, with: .substantive)
        XCTAssertEqual(toks.first { $0.surface == "zero" }?.page, 0)
        XCTAssertEqual(toks.first { $0.surface == "one" }?.page, 1)
        XCTAssertEqual(toks.first { $0.surface == "two" }?.page, 2)
        XCTAssertEqual(toks.first { $0.surface == "three" }?.page, 3)
    }

    func testGBUSSpellingFoldsToSameReading() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        let gb = Tokenizer.tokenize("the colour of the theatre", with: norm).filter { $0.isComparable }.map { $0.normalized }
        let us = Tokenizer.tokenize("the color of the theater", with: norm).filter { $0.isComparable }.map { $0.normalized }
        XCTAssertEqual(gb, us, "GB and US spellings normalize to the same comparison keys")
    }

    func testApostrophesAndHyphensKeptInsideWords() {
        // Diplomatic mode does NOT split hyphenated compounds (exact comparison); apostrophes never split.
        let toks = Tokenizer.tokenize("don't well-being", with: .diplomatic).filter { $0.kind == .word }
        XCTAssertEqual(toks.map { $0.surface }, ["don't", "well-being"])
    }

    func testSubstantiveSplitsHyphenatedCompoundsIntoWords() {
        // BACKLOG B6: under substantive normalization, an intra-word hyphen is an accidental of word-division
        // — the compound splits into component WORD tokens with the hyphen as a foldable punctuation unit.
        let toks = Tokenizer.tokenize("the mother-in-law", with: .substantive)
        XCTAssertEqual(toks.filter { $0.kind == .word }.map { $0.surface }, ["the", "mother", "in", "law"])
        // The hyphens are emitted as (foldable) punctuation, so they carry no comparison weight.
        XCTAssertEqual(toks.filter { $0.kind == .punctuation }.map { $0.surface }, ["-", "-"])
        XCTAssertTrue(toks.filter { $0.kind == .punctuation }.allSatisfy { !$0.isComparable })
        // Apostrophes still do not split.
        let appos = Tokenizer.tokenize("couldn't", with: .substantive).filter { $0.kind == .word }
        XCTAssertEqual(appos.map { $0.surface }, ["couldn't"])
    }

    func testHyphenatedCompoundAlignsWithSpacedForm() {
        // The point of the split: `dun-white` and `dun white` must read as the SAME substantive text, not a
        // 2-tokens-vs-1-token substitution (the Frankenstein 1818→1831 real case, CASE_STUDY Case 1).
        let r = Collation.collate(base: Witness(id: "A", text: "the dun white sockets"),
                                  compared: Witness(id: "B", text: "the dun-white sockets"))
        XCTAssertTrue(r.variations.isEmpty, "hyphenation is an accidental; the two should collate as identical")
        // A leading/trailing hyphen (a dash abutting the word) must NOT split — only interior hyphens do, so
        // the run stays a single word token.
        let lead = Tokenizer.tokenize("-dash", with: .substantive).filter { $0.kind == .word }
        XCTAssertEqual(lead.map { $0.surface }, ["-dash"])
    }

    func testHyphenationIsOrthogonalToWordReordering() {
        // Splitting hyphenated compounds folds the ORTHOGRAPHIC axis (hyphen vs space) — but it is independent
        // of the SUBSTANTIVE axis (whether the words are reordered/rephrased). Pinning both directions makes
        // the distinction explicit (it is the answer to "what about `the well-known author` →
        // `the author is well known`?").

        // (a) Pure orthographic change — same word order, hyphen ⇄ space → NO variant (an accidental).
        let ortho = Collation.collate(base: Witness(id: "A", text: "the well-known author"),
                                      compared: Witness(id: "B", text: "the well known author"))
        XCTAssertTrue(ortho.variations.isEmpty,
            "`well-known` vs `well known` in the same position is orthographic; it must fold to no variant")

        // (b) Syntactic rephrase that also moves the words → a REAL variant, NOT suppressed by the hyphen fold.
        // `the well-known author` → `the author is well known`: shared spine `the … well known`; `author`
        // relocates and `is` is added → reported as an insertion + a deletion (a substantive change).
        let rephrase = Collation.collate(base: Witness(id: "A", text: "the well-known author"),
                                         compared: Witness(id: "B", text: "the author is well known"))
        XCTAssertFalse(rephrase.variations.isEmpty,
            "a reordering/rephrase is substantive; folding the hyphen must NOT hide it")
        XCTAssertGreaterThan(rephrase.insertions + rephrase.deletions, 0,
            "the moved/added words surface as insertion/deletion, not as nothing")

        // (c) A real word change INSIDE the compound is still a substitution (not folded).
        let inner = Collation.collate(base: Witness(id: "A", text: "a well-known fact"),
                                      compared: Witness(id: "B", text: "a widely-known fact"))
        XCTAssertEqual(inner.substitutions, 1, "`well`→`widely` inside the compound is a real substitution")
    }

    // MARK: no-collate regions (editorial exclusion of front/back matter)
    //
    // An editor wraps edition-specific matter that shouldn't be aligned — front matter, a translator's note, a
    // list of illustrations — in a `<!-- no_collate --> … <!-- /no_collate -->` region (or the minimal
    // single-comment form `<!-- no_collate … -->`). The whole span emits NO tokens, so it never reaches the
    // aligner. This is what stops two witnesses' unrelated front matter being force-aligned into junk variants.

    func testNoCollateRegionEmitsNoTokens() {
        // The single-comment form (open marker, content, the comment's own `-->` close): everything inside is
        // dropped; prose before and after tokenises normally.
        let text = "alpha beta\n<!-- no_collate\nSKIP every WORD in here\n-->\ngamma delta"
        let comparable = Tokenizer.tokenize(text, with: .substantive).filter { $0.isComparable }.map { $0.normalized }
        XCTAssertEqual(comparable, ["alpha", "beta", "gamma", "delta"],
            "the excluded region contributes no tokens; surrounding prose is untouched")
        XCTAssertFalse(comparable.contains("skip"), "not a single word of the region leaks through")
    }

    func testNoCollateRangesPairOpenToItsCommentClose() {
        // Two independent regions; each open pairs with the NEXT `-->`, not a later one.
        let text = "<!-- no_collate\nfront\n-->\nbody one\n<!-- no_collate\nback\n-->\nbody two"
        let ranges = Tokenizer.noCollateRanges(in: text)
        XCTAssertEqual(ranges.count, 2, "each open marker pairs with its own close")
        let toks = Tokenizer.tokenize(text, with: .substantive).filter { $0.isComparable }.map { $0.normalized }
        XCTAssertEqual(toks, ["body", "one", "body", "two"], "only the collatable prose survives")
    }

    func testNoCollateExcludesMatterFromCollation() {
        // The point of the feature: unrelated front matter in two witnesses must NOT generate variants. Without
        // the region it would collate into a pile of substitutions; wrapped, only the shared prose is compared.
        let a = "<!-- no_collate\nTranslated by A. One. Copyright 1999.\n-->\nthe ship sailed at dawn"
        let b = "<!-- no_collate\nList of Illustrations: a gunner; a reef.\n-->\nthe ship sailed at dusk"
        let r = Collation.collate(base: Witness(id: "A", text: a), compared: Witness(id: "B", text: b))
        XCTAssertEqual(r.substitutions, 1, "only `dawn`→`dusk` in the shared prose — the front matter is excluded")
        XCTAssertEqual(r.insertions + r.deletions, 0, "the differing front matter produces no spurious ins/del")
    }

    func testUnclosedNoCollateRunsToEndOfText() {
        // "everything after here is back matter" — an open with no close excludes the rest of the witness.
        let text = "keep this line\n<!-- no_collate\nappendix\nnotes\nindex"
        let toks = Tokenizer.tokenize(text, with: .substantive).filter { $0.isComparable }.map { $0.normalized }
        XCTAssertEqual(toks, ["keep", "this", "line"], "an unclosed region swallows everything after it")
    }
}
