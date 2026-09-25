import Foundation

// MARK: - Variant classification (stage 3)
//
// Turns a `SegmentAlignment` (over comparable tokens) into a list of typed, navigable `Variation`s — the
// apparatus entries a scholar reads. Adjacent same-type ops are coalesced into one variation (so a reworded
// clause is ONE substitution spanning several words, not five). Each variation carries the surface readings
// from both witnesses, the originating token-index ranges (so the UI can scroll to the spot), and a
// `crossesPage` flag set when a transposed/changed block sits on different pages in the two witnesses —
// directly answering "show changes even across pages".

// String-backed so JSON encodes a stable, self-describing tag ("substitution") rather than an ordinal —
// important for the cross-language wire format (§ CollationJSON) consumed by a web/WASM front end.
public enum VariationType: String, Equatable, Codable, CaseIterable {
    case insertion        // present in compared, absent in base
    case deletion         // present in base, absent in compared
    case substitution     // different reading in the same place (a SUBSTANTIVE change)
    case transposition    // same reading, moved to a different position (incl. across a page)
    case variantSpelling  // same word, different ACCIDENTAL surface (colour/color, End/end) — folded in
                          // alignment, but recorded here when accidentals are wanted (diplomatic view)
}

/// Where a variant sits in a witness, in the coordinates a reader/scholar references a printed witness by —
/// **page**, **line within that page** (text lines only; blanks and page-break markers are not numbered),
/// and the variant's **word span on the line(s)** — plus the exact character range for visual highlighting.
///
/// The word coordinate is line-relative (the Nth word *on its line*), and a span: a single-word variant is
/// one word position, a multi-word variant a word range. This is what lets the user reference the original
/// context — "p.1, line 2, words 2–6" — rather than an opaque document-global word count.
///
/// All values are 0-based internally; `human` renders the scholarly, 1-based citation. A reading that runs
/// onto further lines records `endLine`/`endWord` so the citation can say "lines 2–3".
public struct TextLocation: Equatable {
    public let page: Int
    public let line: Int                 // 0-based text line within the page (first word's line)
    public let endLine: Int              // line of the last word (== line for a single-line reading)
    public let firstWord: Int            // 0-based word position on `line` of the first word
    public let lastWord: Int             // 0-based word position on `endLine` of the last word
    public let charRange: Range<Int>     // UTF-16 offsets into the witness text (for highlighting)

    public init(page: Int, line: Int, endLine: Int, firstWord: Int, lastWord: Int, charRange: Range<Int>) {
        self.page = page; self.line = line; self.endLine = endLine
        self.firstWord = firstWord; self.lastWord = lastWord; self.charRange = charRange
    }

    /// Whether the reading is a single word (→ a word *position*) or several (→ a word *range*).
    public var isSingleWord: Bool { line == endLine && firstWord == lastWord }

    /// A 1-based scholarly citation. Single word on a line:  "p.1 · line 2 · word 3".
    /// Several words on one line:                            "p.1 · line 2 · words 3–6".
    /// A reading spanning lines:                             "p.2 · lines 1–2 · words 4…2".
    public var human: String {
        let p = "p.\(page + 1)"
        if line == endLine {
            let l = "line \(line + 1)"
            let w = firstWord == lastWord ? "word \(firstWord + 1)" : "words \(firstWord + 1)–\(lastWord + 1)"
            return "\(p) · \(l) · \(w)"
        } else {
            return "\(p) · lines \(line + 1)–\(endLine + 1) · words \(firstWord + 1)…\(lastWord + 1)"
        }
    }
}

/// How sure the engine is that a reported **transposition** is genuinely a move (vs. a coincidence). Anchored
/// moves and exact displaced-word matches are `certain`; a `likely` move is a heuristic pairing (e.g. a
/// deleted word and an inserted word that are *near* matches — a misspelling, or plausibly the same lemma —
/// rather than identical) which a report/visualisation should surface as tentative, not assert. Only meaningful
/// for `.transposition`; other variation types are always `certain`.
public enum MoveConfidence: String, Equatable, Codable {
    case certain   // anchored, or an exact displaced-reading match (unique key, identical normalisation)
    case likely    // a heuristic near-match move — surface as "possible move", do not assert
}

public struct Variation: Equatable {
    public let type: VariationType
    public let baseReading: String        // surface text from the base witness ("" for a pure insertion)
    public let comparedReading: String    // surface text from the compared witness ("" for a pure deletion)
    public let baseTokenRange: Range<Int>?     // indices into base's full token list (nil if none)
    public let comparedTokenRange: Range<Int>? // indices into compared's full token list (nil if none)
    /// Where this variant is located in each witness (nil on the side that omits it). Carries page/line/
    /// word/char-range so the UI can take the reader to the spot in any of those coordinate systems.
    public let baseLocation: TextLocation?
    public let comparedLocation: TextLocation?
    /// True when this edit was found *inside a moved block* (via recursive anchoring) — e.g. a word changed
    /// in a sentence that was also transposed. The apparatus can then note "(within a transposed passage)"
    /// instead of mis-reporting it as an unrelated insertion/deletion elsewhere.
    public let withinTransposition: Bool
    /// For a `.transposition`: how sure the engine is it is a real move (see `MoveConfidence`). Always
    /// `.certain` for the other variation types.
    public let confidence: MoveConfidence
    /// For a **pure `.insertion`** (text present in `compared`, absent in `base`): the base full-token index
    /// this inserted span *follows* — i.e. the last base token before the insertion point — or `-1` when the
    /// insertion precedes all base text. `nil` for every other variation type (they carry a `baseTokenRange`
    /// instead). This is what lets the N-witness variant graph *anchor* an insertion between two base
    /// positions (BACKLOG **B6c**) instead of dropping it, so inserted stanzas appear in the apparatus.
    public let insertionAnchor: Int?

    public var basePage: Int? { baseLocation?.page }
    public var comparedPage: Int? { comparedLocation?.page }
    public var crossesPage: Bool {
        guard let bp = basePage, let cp = comparedPage else { return false }
        return bp != cp
    }

    public init(type: VariationType, baseReading: String, comparedReading: String,
                baseTokenRange: Range<Int>?, comparedTokenRange: Range<Int>?,
                baseLocation: TextLocation?, comparedLocation: TextLocation?,
                withinTransposition: Bool = false,
                confidence: MoveConfidence = .certain,
                insertionAnchor: Int? = nil) {
        self.type = type
        self.baseReading = baseReading
        self.comparedReading = comparedReading
        self.baseTokenRange = baseTokenRange
        self.comparedTokenRange = comparedTokenRange
        self.baseLocation = baseLocation
        self.comparedLocation = comparedLocation
        self.withinTransposition = withinTransposition
        self.confidence = confidence
        self.insertionAnchor = insertionAnchor
    }
}

public enum VariationClassifier {

    /// Build the apparatus from a pairwise alignment. `base`/`compared` are the FULL token lists (including
    /// punctuation); `aKeys`/`bKeys` map comparable-token indices back to full-token indices so readings and
    /// ranges reference the real text. (The aligner runs on comparable tokens only.)
    /// `recordAccidentals` (default false): when true, matched positions whose *surfaces* differ but whose
    /// normalized keys are equal (e.g. colour/color, End/end) are reported as `.variantSpelling` — the
    /// accidental layer of the apparatus. Left off, the apparatus shows only substantive variation.
    public static func classify(_ alignment: SegmentAlignment,
                                base: [Token], compared: [Token],
                                aMap: [Int], bMap: [Int],
                                recordAccidentals: Bool = false,
                                recordPunctuation: Bool = false,
                                lexicon: TranslationLexicon? = nil) -> [Variation] {
        var out: [Variation] = []
        // Carried ACROSS regions (anchors are emitted as regions too) so the punctuation overlay compares the
        // gap between two consecutive matched words even when an anchor splits them into separate regions —
        // avoiding the double-count a per-region reset caused. Reset only across a transposition (below).
        var prevAFull = -1, prevBFull = -1

        // Flatten region ops in order; transposition segments are emitted directly.
        for segment in alignment.segments {
            switch segment {
            case .transposition(let aRange, let bRange, let innerOps):
                let baseFull = mapRange(aRange, via: aMap)
                let compFull = mapRange(bRange, via: bMap)
                // Confidence: a short anchor block near the diagonal on a LONG parallel pair is a *possible* move
                // (the gate's irreducible residual — cannot be dropped without losing genuine short moves, so it is
                // softened to `.likely` rather than asserted); a distinctive-length block, or a short block in a
                // short witness, stays `.certain`. See `Transposition.anchorMoveIsCertain`.
                let moveConfidence: MoveConfidence =
                    Transposition.anchorMoveIsCertain(blockLength: aRange.count,
                                                      aCount: aMap.count, bCount: bMap.count) ? .certain : .likely
                out.append(Variation(
                    type: .transposition,
                    baseReading: baseFull.map { surface(base, $0) } ?? "",
                    comparedReading: compFull.map { surface(compared, $0) } ?? "",
                    baseTokenRange: baseFull, comparedTokenRange: compFull,
                    baseLocation: baseFull.flatMap { location(base, $0) },
                    comparedLocation: compFull.flatMap { location(compared, $0) },
                    confidence: moveConfidence))
                // Recover edits made INSIDE the moved block (recursive anchoring): classify the move's own
                // alignment, tagging each as occurring within the transposition so the apparatus can say so.
                out.append(contentsOf: classifyRegion(innerOps, base: base, compared: compared,
                                                      aMap: aMap, bMap: bMap,
                                                      recordAccidentals: recordAccidentals,
                                                      recordPunctuation: recordPunctuation,
                                                      withinTransposition: true,
                                                      prevAFull: &prevAFull, prevBFull: &prevBFull))
                // A move breaks the linear punctuation flow: don't compare punctuation across the move.
                prevAFull = -1; prevBFull = -1
            case .region(let ops):
                out.append(contentsOf: classifyRegion(ops, base: base, compared: compared,
                                                       aMap: aMap, bMap: bMap,
                                                       recordAccidentals: recordAccidentals,
                                                       recordPunctuation: recordPunctuation,
                                                       prevAFull: &prevAFull, prevBFull: &prevBFull))
            }
        }
        return recoverDisplacedReadings(out, base: base, compared: compared, lexicon: lexicon)
    }

    /// Post-pass: recover **single-word moves the anchor pass cannot see**. The transposition detector needs
    /// unique *n-gram* anchors (n ≥ 2), so a token that moves ALONE never forms a shared bigram landmark and
    /// the monotonic NW reports it as a deletion (where it was) plus an insertion (where it went) — exactly the
    /// "diff artifact" the engine exists to avoid (e.g. `the well-known author` → `the author is well known`,
    /// where `author` *moved* but was mis-reported as delete + insert).
    ///
    /// Fix (token-granular): find a base WORD token inside a `.deletion` whose normalised key matches a
    /// compared WORD token inside an `.insertion`, where that key is **unique** among the unmatched words on
    /// each side — an unambiguous displacement. Carve the matched word out of both variations into one
    /// `.transposition` (`confidence = .certain`); whatever else those variations covered remains a (smaller)
    /// deletion / insertion. Conservative by construction — it never fires on a genuine lone delete or insert
    /// (no counterpart), so it cannot fabricate a move — and deterministic (keys processed in sorted order,
    /// only-unique pairs merged). A future heuristic layer can add `.likely` near-matches (misspellings /
    /// synonyms) with `confidence = .likely`.
    static func recoverDisplacedReadings(_ variations: [Variation],
                                         base: [Token], compared: [Token],
                                         lexicon: TranslationLexicon? = nil) -> [Variation] {
        // Pair displaced words on the same key the ALIGNER used: the lexicon pivot when one is active (B10),
        // so a moved translation pair ("mer"→"sea") is recovered as a move too; identity otherwise.
        func key(_ s: String) -> String { lexicon?.pivot(s.lowercased()) ?? s.lowercased() }
        // Global key frequency across each FULL witness. A move whose word is globally unique on both sides is
        // an unambiguous displacement (`certain`); if the word recurs, the deleted/inserted occurrences were
        // *paired* by elimination — plausible but not guaranteed — so the move is reported as `likely`.
        func globalCounts(_ tokens: [Token]) -> [String: Int] {
            var c: [String: Int] = [:]
            for t in tokens where t.kind == .word && t.isComparable { c[key(t.normalized), default: 0] += 1 }
            return c
        }
        let baseFreq = globalCounts(base), compFreq = globalCounts(compared)
        // Collect the candidate displaced WORD tokens: base words under deletions, compared words under
        // insertions (skip anything already inside a move). Index by normalised key with its (variation, token).
        var delWords: [String: [(vi: Int, tok: Int)]] = [:]
        var insWords: [String: [(vi: Int, tok: Int)]] = [:]
        for (vi, v) in variations.enumerated() where !v.withinTransposition {
            if v.type == .deletion, let r = v.baseTokenRange {
                for t in r where base[t].kind == .word && base[t].isComparable {
                    delWords[key(base[t].normalized), default: []].append((vi, t))
                }
            } else if v.type == .insertion, let r = v.comparedTokenRange {
                for t in r where compared[t].kind == .word && compared[t].isComparable {
                    insWords[key(compared[t].normalized), default: []].append((vi, t))
                }
            }
        }
        // Recover a displaced word only when it is **unique among the unmatched words on BOTH sides** — exactly
        // one deletion-occurrence and one insertion-occurrence carry this key. That 1:1 correspondence is what
        // makes "these are the same word, relocated" a defensible claim; a common function word left unmatched by
        // the aligner (many `of`/`and`/`was` on each side) has no such correspondence and must NOT be paired by
        // mere proximity — doing so manufactures thousands of spurious "moves" out of alignment noise.
        //
        // Given that unique pair, the EXPANDING-WINDOW search (`Transposition.pairByExpandingWindow`) decides the
        // DISTANCE question: two aligned witnesses are globally co-linear, so it accepts the pair when it sits
        // near its diagonal-predicted position, and reaches further out only when the pairing is unambiguous —
        // admitting a genuinely large but singular move (a relocated passage) while still rejecting a far
        // coincidence. Confidence: `certain` only when the pairing is NEAR the diagonal AND the word is globally
        // unique in both full witnesses; `likely` when it was reached by widening, or the word recurs elsewhere
        // (paired by elimination — plausible, not proven). See DEVELOPMENT_LOG 2026-07-08.
        struct Move { var delVi: Int; var delTokLo: Int; var delTokHi: Int
                      var insVi: Int; var insTokLo: Int; var insTokHi: Int; var confidence: MoveConfidence
                      // For the rarity gate (below): `globallyUnique` = every word in the block occurs exactly once
                      // on both sides (⇒ the block itself is corroboration of a real move); `maxDeviation` = the
                      // largest diagonal deviation of any word in the block (how far off the co-linear expectation
                      // the pairing sits — the locality metric); `words` = the block's span. A coalesced block ANDs
                      // `globallyUnique` and takes the MAX deviation across its words, so the gate judges the block
                      // by its least-corroborated, least-local member.
                      var globallyUnique: Bool; var maxDeviation: Int; var words: Int }
        var raw: [Move] = []
        for k in delWords.keys.sorted() {
            guard let dels = delWords[k], dels.count == 1,
                  let inss = insWords[k], inss.count == 1 else { continue }   // unique among unmatched, both sides
            let pairs = Transposition.pairByExpandingWindow(
                delPositions: [dels[0].tok], insPositions: [inss[0].tok],
                aCount: base.count, bCount: compared.count)
            guard let p = pairs.first else { continue }                       // gated out (beyond the far ceiling)
            let globallyUnique = (baseFreq[k] == 1) && (compFreq[k] == 1)
            let confidence: MoveConfidence = (p.near && globallyUnique) ? .certain : .likely
            let deviation = Transposition.diagonalDeviation(delTok: dels[0].tok, insTok: inss[0].tok,
                                                            aCount: base.count, bCount: compared.count)
            raw.append(Move(delVi: dels[0].vi, delTokLo: dels[0].tok, delTokHi: dels[0].tok,
                            insVi: inss[0].vi, insTokLo: inss[0].tok, insTokHi: inss[0].tok,
                            confidence: confidence, globallyUnique: globallyUnique,
                            maxDeviation: deviation, words: 1))
        }
        guard !raw.isEmpty else { return variations }

        // Coalesce moved words that are CONTIGUOUS in BOTH witnesses into one transposition block, so a moved
        // phrase (`at last`) is reported as a single move, not word-by-word. Sort by base position, then merge
        // a run whose base AND compared token indices are both consecutive and within the same variations. A
        // block is `certain` only if every word in it is `certain` (one ambiguous word taints the block).
        raw.sort { $0.delTokLo < $1.delTokLo }
        var coalesced: [Move] = []
        for m in raw {
            if var last = coalesced.last,
               last.delVi == m.delVi, last.insVi == m.insVi,
               m.delTokLo == last.delTokHi + 1, m.insTokLo == last.insTokHi + 1 {
                last.delTokHi = m.delTokHi; last.insTokHi = m.insTokHi
                last.words += m.words
                last.globallyUnique = last.globallyUnique && m.globallyUnique
                last.maxDeviation = max(last.maxDeviation, m.maxDeviation)
                if m.confidence == .likely { last.confidence = .likely }
                coalesced[coalesced.count - 1] = last
            } else {
                coalesced.append(m)
            }
        }

        // RARITY / LOCALITY GATE — reject the coincidental phantom moves the 1:1-among-unmatched test admits.
        //
        // PROBLEM. The 1:1 test above is over the *unmatched* words only. A word that is COMMON in a witness but
        // matched by the aligner at all-but-one of its occurrences is left unmatched exactly once, so it passes the
        // 1:1 test. The §5.6 displacement gate then only rejects pairings FAR from the co-linear diagonal — but two
        // independent translations run in parallel, so a common word's lone leftover routinely lands NEAR the
        // diagonal purely by coincidence. Result: a phantom transposition. This was found by hand on the Verne
        // *De la Terre à la Lune* pair: "quietly" (Towle uses it 5×; the base deletes the one clause containing its
        // single "quietly") was reported as *moving* ~100 lines to an unrelated sentence, and 13 more lone common
        // words ("daily", "board", "level", …) with it — all paired by elimination, none real moves.
        //
        // KEY OBSERVATION. What separates a real recovered move from such a coincidence is CORROBORATION, of which
        // there are exactly three sources — and a lone common word has NONE of them:
        //   (1) GLOBAL UNIQUENESS — the word occurs once on each side, so "these two are the same word, relocated"
        //       is unambiguous however far apart they sit (this is what lets a genuinely large singular move stand).
        //   (2) A MULTI-WORD BLOCK — several contiguous words all displacing to the same spot together is not a
        //       coincidence; the phrase corroborates itself.
        //   (3) LOCALITY — a short hop. A genuine move of a *repeated* word is the word swapping a few positions
        //       with a neighbour inside the same clause (Verne "firearms": "ancient or modern firearms" →
        //       "firearms, ancient and modern", diagonal deviation 46). A coincidence lands hundreds–thousands of
        //       tokens off the diagonal (the 26 Verne false moves: deviation 141–5536). The two populations are
        //       cleanly separated (gap 46 → 141), so a small ABSOLUTE bound (`Transposition.localMoveTokens` = 80)
        //       tells them apart — where the length-proportional `moveTolerance` (≈1785 on this novel) is far too
        //       loose (its job is (1)'s large-but-unique moves, not this). See `localMoveTokens` for the full
        //       calibration and its margins.
        //
        // GATE. Keep a block iff it has at least one source of corroboration: globally unique, OR a multi-word
        // block, OR a genuinely local single word (deviation ≤ localMoveTokens). Equivalently, DROP only a lone,
        // globally-common, NON-local word — the exact coincidence signature. A dropped block reverts to the plain
        // deletion + insertion the aligner already found (never fabricating; only *declining* to reclassify). This
        // is Option 1 of the 2026-07-15 decision (see DEVELOPMENT_LOG and PAPER_NOTES §4.5 for the full rationale
        // and the alternatives weighed).
        let moves = coalesced.filter { m in
            m.globallyUnique                                   // (1) unambiguous by uniqueness
                || m.words >= 2                                // (2) a phrase corroborates itself
                || m.maxDeviation <= Transposition.localMoveTokens   // (3) a genuinely local single-word hop
        }
        guard !moves.isEmpty else { return variations }

        // For each affected variation, the set of token indices carved out into moves.
        var carvedFromDel: [Int: Set<Int>] = [:]
        var carvedFromIns: [Int: Set<Int>] = [:]
        for m in moves {
            for t in m.delTokLo...m.delTokHi { carvedFromDel[m.delVi, default: []].insert(t) }
            for t in m.insTokLo...m.insTokHi { carvedFromIns[m.insVi, default: []].insert(t) }
        }

        // Rebuild a deletion/insertion variation from the token indices that survive after carving.
        func remnant(_ v: Variation, side: Token, tokens: [Token], removed: Set<Int>, isDeletion: Bool) -> Variation? {
            _ = side
            guard let r = isDeletion ? v.baseTokenRange : v.comparedTokenRange else { return nil }
            let kept = r.filter { !removed.contains($0) }
            guard let lo = kept.min(), let hi = kept.max() else { return nil }   // nothing left → no remnant
            let range = lo..<(hi + 1)
            let reading = surface(tokens, range)
            return Variation(
                type: isDeletion ? .deletion : .insertion,
                baseReading: isDeletion ? reading : "",
                comparedReading: isDeletion ? "" : reading,
                baseTokenRange: isDeletion ? range : nil,
                comparedTokenRange: isDeletion ? nil : range,
                baseLocation: isDeletion ? location(tokens, range) : nil,
                comparedLocation: isDeletion ? nil : location(tokens, range),
                insertionAnchor: isDeletion ? nil : v.insertionAnchor)   // keep the insertion's B6c anchor
        }

        // Emit: keep untouched variations as-is; for carved deletions/insertions emit their remnant (if any);
        // append the recovered transpositions. Order: a recovered move is emitted at its DELETION's position
        // (where the base reader encounters the now-absent text), preserving a stable, base-ordered apparatus.
        var transpositionAtDel: [Int: [Variation]] = [:]
        for m in moves {
            let bRange = m.delTokLo..<(m.delTokHi + 1)
            let cRange = m.insTokLo..<(m.insTokHi + 1)
            transpositionAtDel[m.delVi, default: []].append(Variation(
                type: .transposition,
                baseReading: surface(base, bRange), comparedReading: surface(compared, cRange),
                baseTokenRange: bRange, comparedTokenRange: cRange,
                baseLocation: location(base, bRange), comparedLocation: location(compared, cRange),
                withinTransposition: false, confidence: m.confidence))
        }

        var out: [Variation] = []
        out.reserveCapacity(variations.count + moves.count)
        for (vi, v) in variations.enumerated() {
            if let removed = carvedFromDel[vi] {
                if let rem = remnant(v, side: base[0], tokens: base, removed: removed, isDeletion: true) { out.append(rem) }
                out.append(contentsOf: transpositionAtDel[vi] ?? [])
            } else if let removed = carvedFromIns[vi] {
                if let rem = remnant(v, side: compared[0], tokens: compared, removed: removed, isDeletion: false) { out.append(rem) }
                // the move itself is emitted at the deletion site, not here
            } else {
                out.append(v)
            }
        }
        return out
    }

    /// Coalesce a region's ops into variations: runs of matches are skipped; consecutive non-match ops of a
    /// compatible kind merge (delete+insert adjacent → substitution; like-with-like → insertion/deletion).
    private static func classifyRegion(_ ops: [AlignOp], base: [Token], compared: [Token],
                                       aMap: [Int], bMap: [Int],
                                       recordAccidentals: Bool,
                                       recordPunctuation: Bool = false,
                                       withinTransposition: Bool = false,
                                       prevAFull: inout Int, prevBFull: inout Int) -> [Variation] {
        var out: [Variation] = []
        var pendingDel: [Int] = []   // comparable A indices
        var pendingIns: [Int] = []   // comparable B indices

        func flush() {
            guard !pendingDel.isEmpty || !pendingIns.isEmpty else { return }
            let baseFull = fullRange(pendingDel, via: aMap)
            let compFull = fullRange(pendingIns, via: bMap)
            let type: VariationType
            if !pendingDel.isEmpty && !pendingIns.isEmpty { type = .substitution }
            else if !pendingIns.isEmpty { type = .insertion }
            else { type = .deletion }
            // For a PURE insertion, record the base token it follows (`prevAFull`, or -1 before all base
            // text) so the N-witness graph can anchor it between two base positions instead of dropping it
            // (B6c). Only meaningful for pure insertions; substitutions/deletions carry a `baseTokenRange`.
            let anchor: Int? = (type == .insertion) ? prevAFull : nil
            out.append(Variation(
                type: type,
                baseReading: baseFull.map { surface(base, $0) } ?? "",
                comparedReading: compFull.map { surface(compared, $0) } ?? "",
                baseTokenRange: baseFull, comparedTokenRange: compFull,
                baseLocation: baseFull.flatMap { location(base, $0) },
                comparedLocation: compFull.flatMap { location(compared, $0) },
                withinTransposition: withinTransposition,
                insertionAnchor: anchor))
            pendingDel.removeAll(); pendingIns.removeAll()
        }

        // Compare the punctuation tokens in the gaps (prevFull, full) on each side; if they differ, emit a
        // `.variantSpelling` accidental. A pure overlay: it never affects alignment or substantive output.
        func punctuationAccidental(aFull: Int, bFull: Int) {
            guard recordPunctuation else { return }
            let baseP = punctuationSurfaces(base, after: prevAFull, before: aFull)
            let compP = punctuationSurfaces(compared, after: prevBFull, before: bFull)
            if baseP.joined() != compP.joined() {
                // Locate the accidental at the matched word it precedes (or the gap's edge).
                out.append(Variation(
                    type: .variantSpelling,
                    baseReading: baseP.isEmpty ? "∅" : baseP.joined(separator: " "),
                    comparedReading: compP.isEmpty ? "∅" : compP.joined(separator: " "),
                    baseTokenRange: aFull..<(aFull + 1), comparedTokenRange: bFull..<(bFull + 1),
                    baseLocation: location(base, aFull..<(aFull + 1)),
                    comparedLocation: location(compared, bFull..<(bFull + 1)),
                    withinTransposition: withinTransposition))
            }
        }

        for op in ops {
            switch op {
            case .match(let a, let b):
                flush()
                let aFull = aMap[a], bFull = bMap[b]
                // Punctuation between the previous matched word and this one (diplomatic overlay). Only once a
                // first match has been seen (prev ≥ 0); the very first matched word has no preceding gap.
                if prevAFull >= 0 && prevBFull >= 0 { punctuationAccidental(aFull: aFull, bFull: bFull) }
                // Same normalized key, but do the SURFACES differ? Then it's an accidental (spelling /
                // capitalization) variant — recorded only when asked for. The `normalized` equality guard
                // matters under a B10 lexicon: a MATCH can then pair translation-equivalent words whose
                // normalised forms differ ("année"/"year") — that is structural agreement across a language
                // boundary, not a spelling accidental, so it must not be reported here. Without a lexicon a
                // match implies equal normalised keys, so the guard changes nothing.
                if recordAccidentals {
                    let bt = base[aFull], ct = compared[bFull]
                    if bt.normalized == ct.normalized, bt.surface != ct.surface {
                        out.append(Variation(
                            type: .variantSpelling,
                            baseReading: bt.surface, comparedReading: ct.surface,
                            baseTokenRange: aFull..<(aFull + 1),
                            comparedTokenRange: bFull..<(bFull + 1),
                            baseLocation: location(base, aFull..<(aFull + 1)),
                            comparedLocation: location(compared, bFull..<(bFull + 1)),
                            withinTransposition: withinTransposition))
                    }
                }
                prevAFull = aFull; prevBFull = bFull
            case .substitute(let a, let b):
                pendingDel.append(a); pendingIns.append(b)
            case .delete(let a):
                pendingDel.append(a)
            case .insert(let b):
                pendingIns.append(b)
            }
        }
        flush()
        return out
    }

    // MARK: helpers — comparable indices → full-token ranges, readings, pages

    /// Punctuation-token surfaces strictly between full-token indices `after` and `before` (exclusive both
    /// ends). Used by the diplomatic punctuation overlay to compare the punctuation that sits between two
    /// aligned words. Page-break/marker tokens never appear here (they are not tokens).
    private static func punctuationSurfaces(_ tokens: [Token], after: Int, before: Int) -> [String] {
        guard before > after + 1 else { return [] }
        var result: [String] = []
        for i in (after + 1)..<before where tokens[i].kind == .punctuation {
            // Whitespace-only or empty punctuation carries no editorial signal; keep real marks/spacing.
            let s = tokens[i].surface.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
        }
        return result
    }

    private static func mapRange(_ comparableRange: Range<Int>, via map: [Int]) -> Range<Int>? {
        guard !comparableRange.isEmpty, comparableRange.upperBound <= map.count else { return nil }
        let lo = map[comparableRange.lowerBound]
        let hi = map[comparableRange.upperBound - 1] + 1
        return lo..<hi
    }

    private static func fullRange(_ comparableIdx: [Int], via map: [Int]) -> Range<Int>? {
        guard let first = comparableIdx.first, let last = comparableIdx.last,
              last < map.count else { return nil }
        return map[first]..<(map[last] + 1)
    }

    private static func surface(_ tokens: [Token], _ range: Range<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound <= tokens.count else { return "" }
        // Reconstruct the reading from surfaces, inserting single spaces between words (a readable
        // approximation; a host app can slice the original text by the tokens' char ranges).
        return tokens[range].map { $0.surface }.joined(separator: " ")
    }

    /// The location of a token range: page + line and word-span from its FIRST and LAST tokens, plus a char
    /// span covering the whole range so the UI can highlight the exact extent. The page is the first token's
    /// (a reading that crosses a page break is rare for a single variant; the char range still spans it).
    private static func location(_ tokens: [Token], _ range: Range<Int>) -> TextLocation? {
        guard range.lowerBound >= 0, range.lowerBound < tokens.count,
              range.upperBound <= tokens.count, !range.isEmpty else { return nil }
        let first = tokens[range.lowerBound]
        let last = tokens[range.upperBound - 1]
        // The char span covers the whole token range. Tokens are normally in source order so
        // `first.lowerBound ≤ last.upperBound`, but defend against any out-of-order range (e.g. a span the
        // classifier assembled across a reordered region) by taking the extremes — a Range must not invert.
        let lo = min(first.range.lowerBound, last.range.lowerBound)
        let hi = max(first.range.upperBound, last.range.upperBound)
        return TextLocation(page: first.page, line: first.line, endLine: last.line,
                            firstWord: first.wordIndex, lastWord: last.wordIndex,
                            charRange: lo..<hi)
    }
}
