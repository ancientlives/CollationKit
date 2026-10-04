import Foundation

// MARK: - Translation-aware anchoring (BACKLOG B10)
//
// Cross-language collation (a French original vs. its English translations — the Verne corpus) fails on the
// substantive engine because alignment anchors on SHARED WORD-FORMS, and across a language boundary there are
// almost none: the alignment degrades to positional drift (CASE_STUDY.md Case 6). The fix is NOT to change
// within-language behaviour but to add an *anchoring layer*: a bilingual lexicon of equivalent forms
// ("année" ≈ "year", "marquée" ≈ "marked") that the aligner treats as the SAME key, so the anchor pass and NW
// pair the right words across the boundary.
//
// Design rules (the B10 contract):
//   1. ADDITIVE. The lexicon affects only the KEYS handed to the aligner (a "pivot" mapping). With no
//      lexicon, the pivot is the identity — every existing run and golden is byte-identical.
//   2. Alignment-only. Readings, surfaces, and normalised forms are untouched: the apparatus/synopsis still
//      show each witness's own words ("marquée | marked | signalised"), which is exactly what a synoptic
//      translation view should show. A lexicon match is *structural agreement* (the words are paired), not
//      textual agreement.
//   3. Pairwise semantics: a lexicon-paired match is treated as agreement (no variant reported) — the pair
//      "agrees in meaning". It is NOT a `.variantSpelling` accidental (the classifier guards on normalised
//      equality for that), and not a substitution (that would flood a cross-language apparatus with every
//      word of the text).
//
// The lexicon is user-supplied (per corpus): groups of equivalent normalised forms, any number of languages
// per group. The CLI loads it from a plain-text file (one group per line, forms separated by commas);
// the engine takes the parsed groups. See `docs/reference/ALGORITHMS.md §5.6`.

/// A bilingual/multilingual equivalence lexicon: groups of normalised word-forms that should be treated as
/// the SAME key for alignment purposes ("année, year", "mer, sea"). Forms are matched case-insensitively
/// against tokens' `normalized` keys. The pivot for a group is its lexicographically-smallest member, so the
/// mapping is deterministic and input-order-independent.
public struct TranslationLexicon: Equatable {
    /// normalised form → the group's canonical representative (the pivot key used for alignment).
    private let pivotByForm: [String: String]
    /// The groups as given (lower-cased, trimmed), kept so the lexicon can be re-keyed with a run's normaliser.
    private let groups: [[String]]

    /// Build from groups of equivalent forms. Forms are lower-cased; groups of fewer than two forms are
    /// ignored (nothing to equate). If a form appears in several groups, the first group (in sorted-pivot
    /// order) wins — deterministic, and a lexicon should not do that anyway.
    public init(groups: [[String]]) {
        // Canonical order (each group sorted, then the groups), so equality and re-keying ignore input order.
        self.groups = groups.map { Array(Set($0.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                                           .filter { !$0.isEmpty })).sorted() }
                            .filter { !$0.isEmpty }
                            .sorted { $0.lexicographicallyPrecedes($1) }
        var map: [String: String] = [:]
        // Deterministic: normalise each group, take its sorted-first member as pivot, apply groups in
        // pivot-sorted order so overlapping forms resolve the same way regardless of input order.
        let cleaned: [(pivot: String, forms: [String])] = groups.compactMap { group in
            let forms = Set(group.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                                 .filter { !$0.isEmpty })
            guard forms.count >= 2, let pivot = forms.min() else { return nil }
            return (pivot, forms.sorted())
        }.sorted { $0.pivot < $1.pivot }
        for (pivot, forms) in cleaned {
            for f in forms where map[f] == nil { map[f] = pivot }
        }
        self.pivotByForm = map
    }

    /// The lexicon re-keyed with `normalizer`, the same normalisation the run applies to tokens. Token keys are
    /// normalised (under `.substantive`, `année` → `annee`), so forms must be too, or an accented entry never
    /// matches (release 1 review, B7: the documented `année, year` example did nothing). The collation entry
    /// points apply this, so callers may build a lexicon from forms exactly as written.
    public func normalized(with normalizer: Normalizer) -> TranslationLexicon {
        TranslationLexicon(groups: groups.map { $0.map { normalizer.normalize(word: $0) } })
    }

    /// True when the lexicon equates nothing (behaves as the identity).
    public var isEmpty: Bool { pivotByForm.isEmpty }

    /// The alignment key for a normalised token form: its group's pivot when the form is in the lexicon,
    /// else the form itself. Identity for anything not covered — within-language behaviour is unchanged.
    public func pivot(_ normalizedForm: String) -> String {
        pivotByForm[normalizedForm.lowercased()] ?? normalizedForm
    }

    /// Whether two normalised forms are equated by the lexicon (used by the classifier to distinguish a
    /// translation pairing from a true accidental).
    public func equates(_ a: String, _ b: String) -> Bool {
        guard !isEmpty else { return a == b }
        return pivot(a) == pivot(b)
    }

    // MARK: file format (CLI `--lexicon <path>`)

    /// Parse the plain-text lexicon format: one group per line, forms separated by commas; `#` starts a
    /// comment; blank lines ignored. Example:
    /// ```
    /// # français ↔ english
    /// année, year
    /// mer, sea, seas
    /// ```
    public static func parse(_ text: String) -> TranslationLexicon {
        // Split on every newline style: `"\r\n"` is ONE Character in Swift, so splitting on `"\n"` read a CRLF file
        // as a single line and silently merged its groups (review B7).
        let groups: [[String]] = text.split(whereSeparator: \.isNewline).compactMap { line in
            let stripped = line[..<(line.firstIndex(of: "#") ?? line.endIndex)]
            let forms = stripped.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            return forms.count >= 2 ? forms : nil
        }
        return TranslationLexicon(groups: groups)
    }
}
