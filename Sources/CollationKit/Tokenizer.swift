import Foundation

// MARK: - Normalization (stage 1)
//
// The scholarly distinction between *substantives* (real changes in wording — what an apparatus records)
// and *accidentals* (spelling, punctuation, capitalization, spacing) is configurable here. Folding
// accidentals lets the engine report only meaningful variation; turning the folds off surfaces every
// difference (a diplomatic comparison). This is the lever that makes collation NOT a character diff.

public struct Normalizer {
    public var lowercase: Bool
    public var stripAccents: Bool
    public var dropPunctuation: Bool          // punctuation tokens get normalized "" → ignored in alignment
    public var foldWhitespace: Bool           // collapse internal whitespace runs (always effectively true)
    /// Treat **intra-word hyphenation as an accidental of word-division**: split a hyphenated compound
    /// (`dun-white`, `mother-in-law`) into its component word tokens, emitting the hyphen as a foldable
    /// punctuation unit. So `dun white` and `dun-white` tokenise to the SAME word sequence and align as the
    /// same reading rather than reading as a 2-tokens-vs-1-token substitution. Surfaced by the real-edition
    /// study (Frankenstein 1818→1831 `dun white`→`dun-white`; BACKLOG B6). On for substantive collation;
    /// **off for `.diplomatic`**, which keeps the compound intact for an exact comparison.
    public var splitHyphenatedWords: Bool
    /// Fold typographic apostrophes (`’` U+2019, `‘` U+2018, `ʼ` U+02BC) to the ASCII `'` inside words, so
    /// `don't` and `don’t` are the same reading. A typesetting difference, not a change of wording (release 1
    /// review, B5). On for substantive collation; **off for `.diplomatic`**, which records it.
    public var foldTypographicApostrophes: Bool
    /// Spelling equivalences (e.g. "colour" → "color", "honour" → "honor") to treat GB/US spelling variants
    /// as the SAME reading rather than substitutions. Applied to the lowercased word. Keys are normalized.
    public var spellingEquivalents: [String: String]

    public init(lowercase: Bool = true,
                stripAccents: Bool = true,
                dropPunctuation: Bool = true,
                foldWhitespace: Bool = true,
                splitHyphenatedWords: Bool = true,
                spellingEquivalents: [String: String] = [:],
                foldTypographicApostrophes: Bool = true) {
        self.lowercase = lowercase
        self.stripAccents = stripAccents
        self.dropPunctuation = dropPunctuation
        self.foldWhitespace = foldWhitespace
        self.splitHyphenatedWords = splitHyphenatedWords
        self.spellingEquivalents = spellingEquivalents
        self.foldTypographicApostrophes = foldTypographicApostrophes
    }

    /// Records every difference, including accidentals: nothing folded except whitespace. Use for a
    /// diplomatic (exact) comparison. Hyphenated compounds are kept intact (no splitting).
    public static let diplomatic = Normalizer(lowercase: false, stripAccents: false,
                                              dropPunctuation: false, foldWhitespace: true,
                                              splitHyphenatedWords: false, foldTypographicApostrophes: false)

    /// The default scholarly normalization: case/accents/punctuation folded so only substantives remain.
    public static let substantive = Normalizer()

    static let typographicApostrophes: Set<UnicodeScalar> = ["\u{2019}", "\u{2018}", "\u{02BC}"]

    /// A small GB/US spelling table so the two 1st editions don't read as wall-to-wall substitutions. Not
    /// exhaustive — a prototype seed; a host-app integration would ship a fuller list / user dictionary.
    public static let gbUSSpelling: [String: String] = [
        "colour": "color", "honour": "honor", "favour": "favor", "neighbour": "neighbor",
        "labour": "labor", "rumour": "rumor", "grey": "gray", "theatre": "theater",
        "centre": "center", "metre": "meter", "realise": "realize", "recognise": "recognize",
        "travelling": "traveling", "travelled": "traveled", "defence": "defense", "cheque": "check",
        "harbour": "harbor", "harbours": "harbors", "colours": "colors",
        "traveller": "traveler", "travellers": "travelers",
    ]

    func normalize(word: String) -> String {
        var s = word
        if foldTypographicApostrophes, s.unicodeScalars.contains(where: { Self.typographicApostrophes.contains($0) }) {
            s = String(String.UnicodeScalarView(s.unicodeScalars.map { Self.typographicApostrophes.contains($0) ? "'" : $0 }))
        }
        if lowercase { s = s.lowercased() }
        if stripAccents {
            s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        }
        if let canonical = spellingEquivalents[s] { s = canonical }
        return s
    }
}

// MARK: - Tokenizer (stage 1)
//
// Splits a witness into word + punctuation tokens, tracking paragraph and PAGE indices. Pages are marked
// by an explicit page-break marker so "across pages" variation can be reported; the markers below match
// markdown page-break conventions (`<!-- page break -->` and a stand-alone `---` rule).
// Markdown heading/list markers are emitted as punctuation (foldable) so prose aligns to prose.

public enum Tokenizer {

    /// Page-break markers recognized when splitting a witness into pages. A `\f` form feed (common in
    /// typescripts/proofs), an HTML page-break comment, and a stand-alone `---` thematic break.
    static let pageBreakPattern = #"(\f)|(<!--\s*page\s*break\s*-->)|(^[ \t]*---[ \t]*$)"#

    public static func tokenize(_ text: String, with normalizer: Normalizer,
                                pagination: PaginationModel = .default) -> [Token] {
        let ns = text as NSString
        var tokens: [Token] = []
        var page = 0
        var paragraph = 0
        // Citation coordinates (how a reader/scholar references a spot in a printed witness):
        //  • pageLine — the TEXT line within the current PAGE (counts only lines that actually carry text, so
        //    blank lines and the page-break marker line are NOT numbered — matching critical-edition layout).
        //    Resets per page under `.perPage`; runs continuously under `.continuous`.
        //  • lineWord — the word's position within its text line (resets each new text line).
        // A latch defers committing a new line/page-line until the line is known to bear text, so a trailing
        // blank line never advances the count.
        var pageLine = -1                 // becomes 0 at the first text line of the page
        var lineWord = 0
        var lineHasText = false           // has the current physical line emitted a token yet?
        // `linesThisPage` counts text lines emitted on the current page — drives `.linesPerPage` breaks.
        var linesThisPage = 0

        // Page boundaries depend on the pagination model. Markers contribute spans we both break on AND skip
        // the text of; lines-per-page / explicit offsets break WITHOUT consuming text.
        let markerBreaks: [Range<Int>]
        let explicitStarts: [Int]
        let linesPerPage: Int?
        switch pagination.pages {
        case .markers:            markerBreaks = pageBreakRanges(in: text); explicitStarts = []; linesPerPage = nil
        case .linesPerPage(let n): markerBreaks = []; explicitStarts = []; linesPerPage = max(1, n)
        case .explicit(let offs): markerBreaks = []; explicitStarts = offs.sorted(); linesPerPage = nil
        }
        var nextBreakIdx = 0
        var nextExplicitIdx = 0
        let resetLinesPerPage = (pagination.lineNumbering == .perPage)

        // Editorial exclusion: spans wrapped in `<!-- no_collate --> … <!-- /no_collate -->` emit no tokens at
        // all (front matter, translator notes, etc.). Ascending, non-overlapping; walked in step with `i`.
        let noCollate = noCollateRanges(in: text)
        var nextNoCollateIdx = 0

        // Begin a new page: bump page; reset per-page line numbering when the policy says so.
        func startNewPage() {
            page += 1
            linesThisPage = 0
            if resetLinesPerPage { pageLine = -1 }
            lineWord = 0
            lineHasText = false
        }

        // Walk the text by scanning word/punct runs; blank lines bump the paragraph, page breaks bump page.
        var i = 0
        let length = ns.length
        while i < length {
            // No-collate region: jump the whole excluded span (markers included) — emit nothing. A blank line
            // may still separate it from following prose, so we do NOT bump paragraph here; the next text line
            // resumes numbering naturally.
            while nextNoCollateIdx < noCollate.count && i >= noCollate[nextNoCollateIdx].upperBound {
                nextNoCollateIdx += 1
            }
            if nextNoCollateIdx < noCollate.count && i >= noCollate[nextNoCollateIdx].lowerBound {
                i = noCollate[nextNoCollateIdx].upperBound
                nextNoCollateIdx += 1
                if lineHasText { lineWord = 0; lineHasText = false }
                continue
            }
            // Marker-driven page break: at the START of a marker, start a new page and SKIP the marker text.
            if nextBreakIdx < markerBreaks.count && i >= markerBreaks[nextBreakIdx].lowerBound {
                startNewPage()
                i = markerBreaks[nextBreakIdx].upperBound
                nextBreakIdx += 1
                continue
            }
            // Explicit-offset page break: when we reach a declared page start (and it isn't offset 0).
            if nextExplicitIdx < explicitStarts.count && i >= explicitStarts[nextExplicitIdx] {
                if explicitStarts[nextExplicitIdx] > 0 { startNewPage() }
                nextExplicitIdx += 1
                continue
            }
            // Decode the scalar at `i`, including a surrogate pair (characters above U+FFFF: rare CJK, historic
            // scripts, mathematical letters, emoji). Building it from one UTF-16 unit returned nil for each half, so
            // such characters were silently dropped (release 1 review, B4).
            let (scalar, width) = scalarAt(ns, i)

            // Newline: end the current line. The NEXT text-bearing line will advance `pageLine` lazily (so
            // blank lines never consume a line number). Paragraph breaks (blank line) bump `paragraph`.
            if scalar == "\n" {
                if isBlankLineBreak(ns, at: i) && lineHasText {
                    paragraph += 1
                }
                if lineHasText { lineWord = 0; lineHasText = false }
                i += 1
                continue
            }
            if scalar != nil && CharacterSet.whitespaces.contains(scalar!) {
                i += width
                continue
            }

            // Word run: starts with a letter or digit; may contain intra-word apostrophes and hyphens. A trailing
            // apostrophe or hyphen run is trimmed back off (it is a closing quote or a dash, not part of the word),
            // so `'Hello,'` tokenises as quote + `Hello` + punctuation, the same words as `"Hello,"` (B5).
            if let s = scalar, isWordStart(s) {
                let start = i
                while i < length {
                    let (c, w) = scalarAt(ns, i)
                    guard let c, isWordScalar(c) else { break }
                    i += w
                }
                while i > start + 1, let c = UnicodeScalar(ns.character(at: i - 1)), isWordJoiner(c) { i -= 1 }
                // `.linesPerPage`: a new text line that would overflow the page starts a new page first.
                if !lineHasText, let lpp = linesPerPage, linesThisPage >= lpp { startNewPage() }
                if !lineHasText { pageLine += 1; lineHasText = true; linesThisPage += 1 }
                // Split a hyphenated compound into component word tokens (hyphen = foldable punctuation), so
                // `dun-white` tokenises like `dun white`. Only an INTERIOR hyphen splits — a leading/trailing
                // `-` (a dash abutting the word) is left as a single token. Apostrophes never split.
                for tok in wordUnits(ns, start: start, end: i, split: normalizer.splitHyphenatedWords) {
                    let surface = ns.substring(with: NSRange(location: tok.lowerBound,
                                                             length: tok.upperBound - tok.lowerBound))
                    let isHyphen = surface.allSatisfy { $0 == "-" }   // a hyphen RUN (`--`) is a dash, i.e. punctuation
                    let norm = isHyphen ? (normalizer.dropPunctuation ? "" : surface)
                                        : normalizer.normalize(word: surface)
                    tokens.append(Token(surface: surface, normalized: norm,
                                        kind: isHyphen ? .punctuation : .word,
                                        range: tok, line: pageLine, paragraph: paragraph,
                                        page: page, wordIndex: lineWord))
                    lineWord += 1
                }
                continue
            }

            // Punctuation / symbol run: a single char each (so "..." → three units is avoided; group runs).
            // An apostrophe or hyphen that does not continue a word (a leading quote, a dash) belongs here too.
            let start = i
            while i < length {
                let (c, w) = scalarAt(ns, i)
                guard let c else { break }
                if isWordStart(c) || CharacterSet.whitespacesAndNewlines.contains(c) { break }
                i += w
            }
            if i > start {
                if !lineHasText, let lpp = linesPerPage, linesThisPage >= lpp { startNewPage() }
                if !lineHasText { pageLine += 1; lineHasText = true; linesThisPage += 1 }
                let surface = ns.substring(with: NSRange(location: start, length: i - start))
                // Punctuation normalizes to "" when dropPunctuation is on → ignored by alignment.
                let norm = normalizer.dropPunctuation ? "" : surface
                tokens.append(Token(surface: surface, normalized: norm, kind: .punctuation,
                                    range: start..<i, line: pageLine, paragraph: paragraph,
                                    page: page, wordIndex: lineWord))
                lineWord += 1
            } else {
                i += max(1, width)   // safety: never stall (e.g. a lone surrogate)
            }
        }
        return tokens
    }

    // A scalar that can START a word: a letter, digit or mark.
    private static func isWordStart(_ s: UnicodeScalar) -> Bool { CharacterSet.alphanumerics.contains(s) }

    // An apostrophe or hyphen: part of a word only BETWEEN word characters (`don't`, `dun-white`).
    private static func isWordJoiner(_ s: UnicodeScalar) -> Bool {
        s == "'" || s == "\u{2019}" /* ’ */ || s == "\u{2018}" /* ‘ */ || s == "\u{02BC}" /* ʼ */ || s == "-"
    }

    // A scalar that belongs inside a word: letters, digits, marks, and intra-word apostrophes and hyphens.
    private static func isWordScalar(_ s: UnicodeScalar) -> Bool { isWordStart(s) || isWordJoiner(s) }

    /// The Unicode scalar starting at UTF-16 offset `i` and its width in UTF-16 units: 2 for a valid surrogate
    /// pair, else 1. Returns nil for a lone surrogate.
    private static func scalarAt(_ ns: NSString, _ i: Int) -> (UnicodeScalar?, Int) {
        let u = ns.character(at: i)
        if UTF16.isLeadSurrogate(u), i + 1 < ns.length {
            let v = ns.character(at: i + 1)
            if UTF16.isTrailSurrogate(v) {
                let value = 0x10000 + ((UInt32(u) - 0xD800) << 10) + (UInt32(v) - 0xDC00)
                return (UnicodeScalar(value), 2)
            }
        }
        return (UnicodeScalar(u), 1)
    }

    /// Break a word run `[start, end)` into emit units. With `split` off (or no interior hyphen) this is the
    /// single whole-word range. With `split` on, an INTERIOR hyphen run separates component sub-words: each
    /// sub-word and each hyphen becomes its own range (the hyphen ranges are emitted as foldable punctuation
    /// by the caller). A leading/trailing hyphen does NOT split (it abuts the word edge), so e.g. a stray
    /// `-word` stays one token.
    private static func wordUnits(_ ns: NSString, start: Int, end: Int, split: Bool) -> [Range<Int>] {
        guard split else { return [start..<end] }
        func isHyphen(_ at: Int) -> Bool { UnicodeScalar(ns.character(at: at)) == "-" }
        // No interior hyphen → no split (interior = not at start, not at end).
        var hasInterior = false
        var k = start + 1
        while k < end - 1 { if isHyphen(k) { hasInterior = true; break }; k += 1 }
        guard hasInterior else { return [start..<end] }

        var units: [Range<Int>] = []
        var segStart = start
        var j = start
        while j < end {
            // An interior hyphen run boundary splits; leading/trailing hyphens fold into the adjacent edge.
            if isHyphen(j) && j > start && j < end - 1 && !isHyphen(j - 1) {
                if j > segStart { units.append(segStart..<j) }     // the sub-word before the hyphen(s)
                let hStart = j
                while j < end && isHyphen(j) { j += 1 }            // consume a run of hyphens
                units.append(hStart..<j)                           // the hyphen run, as one foldable unit
                segStart = j
                continue
            }
            j += 1
        }
        if segStart < end { units.append(segStart..<end) }         // the trailing sub-word
        return units
    }

    // True when the newline at `idx` begins a blank-line paragraph break (\n[ \t]*\n).
    private static func isBlankLineBreak(_ ns: NSString, at idx: Int) -> Bool {
        var j = idx + 1
        let len = ns.length
        while j < len {
            let c = UnicodeScalar(ns.character(at: j))
            guard let c else { return false }
            if c == "\n" { return true }
            if c == " " || c == "\t" || c == "\r" { j += 1; continue }
            return false
        }
        return false
    }

    /// The character ranges of every page-break marker in the text, in order. Crossing one increments the
    /// page index assigned to subsequent tokens.
    static func pageBreakRanges(in text: String) -> [Range<Int>] {
        guard let regex = try? NSRegularExpression(pattern: pageBreakPattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                    .map { $0.range.location..<($0.range.location + $0.range.length) }
    }

    // MARK: no-collate regions (editorial exclusion)
    //
    // An editor wraps edition-specific matter that should NOT be aligned (front matter, a translator's note, a
    // list of illustrations, an appendix) in a `<!-- no_collate --> … <!-- /no_collate -->` region. The whole
    // enclosed span — markers included — is skipped: no tokens are emitted, so it never reaches the aligner.
    // This is the region analogue of the page-break marker (which skips a POINT); it is what stops unrelated
    // front matter in two witnesses from being force-aligned into hundreds of junk "substitutions" and, worse,
    // giving the aligner unanchored common words to mis-match across the whole novel.
    //
    // Syntax (case-insensitive, whitespace-tolerant). The natural, minimal form is a single HTML comment that
    // brackets the block — the excluded matter lives *inside* one comment:
    //
    //     <!-- no_collate
    //     …front matter, translator note, list of illustrations…
    //     -->
    //
    // i.e. OPEN = `<!-- no_collate` (or `no-collate`), CLOSE = the comment's own `-->` (a bare `-->`, typically
    // on its own line). An explicit `<!-- /no_collate -->` is also accepted as a close for authors who prefer a
    // named end tag. An unclosed open runs to end-of-text (the common "everything after here is back matter").
    // The open deliberately does NOT require a `-->` on its own line, so the one-comment form above works.
    static let noCollateOpenPattern = #"<!--\s*no[_-]collate\b"#
    static let noCollateClosePattern = #"(<!--\s*/\s*no[_-]collate\s*-->)|(-->)"#

    /// Character ranges (marker-inclusive) that must be excluded from tokenisation, in ascending order. Each
    /// runs from a `no_collate` open marker to its matching close (or end-of-text if unclosed).
    static func noCollateRanges(in text: String) -> [Range<Int>] {
        let ns = text as NSString
        guard let openRE = try? NSRegularExpression(pattern: noCollateOpenPattern, options: [.caseInsensitive]),
              let closeRE = try? NSRegularExpression(pattern: noCollateClosePattern,
                                                     options: [.caseInsensitive, .anchorsMatchLines])
        else { return [] }
        let full = NSRange(location: 0, length: ns.length)
        let opens = openRE.matches(in: text, range: full).map { $0.range }
        let closes = closeRE.matches(in: text, range: full).map { $0.range }
        var ranges: [Range<Int>] = []
        var searchFrom = 0
        for open in opens where open.location >= searchFrom {
            // The first close marker that starts at/after the END of this open marker; else run to end-of-text.
            let openEnd = open.location + open.length
            let close = closes.first { $0.location >= openEnd }
            let end = close.map { $0.location + $0.length } ?? ns.length
            ranges.append(open.location..<end)
            searchFrom = end
        }
        return ranges
    }
}
