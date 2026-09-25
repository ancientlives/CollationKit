import Foundation

// MARK: - Witness & Token model (stage 1)
//
// A *witness* is one version of the work (manuscript, typescript, proofs, GB/US 1st editions, the Uniform
// edition, …). Collation aligns witnesses at the level of meaningful textual units — words + punctuation —
// NOT lines (prose reflows and moves across pages, so a line-oriented diff is the wrong tool). Structural
// boundaries (paragraph, page) are retained on each token so the engine can recognise a passage that MOVED
// across a page boundary, and so the UI can navigate back to the right place in each witness.

/// One version of the document under collation. `id` names the edition (e.g. "MS", "TS", "GB1"); `text`
/// is its full markdown/plain text.
public struct Witness: Equatable {
    public let id: String
    public let text: String
    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// A single textual unit in a witness. `kind` distinguishes words from punctuation (punctuation is an
/// *accidental* that normalization can fold away). `normalized` is the comparison key produced by the
/// active `Normalizer`; alignment compares on `normalized`, while `surface` preserves the reading shown to
/// the user. `range` is the unit's location in the witness's original text (UTF-16 offsets) so a variant
/// can be navigated to — even when it sits on a different page than in another witness.
public struct Token: Equatable {
    public enum Kind: Equatable { case word, punctuation }

    public let surface: String        // the text as it appears in the witness ("colour")
    public let normalized: String     // the comparison key ("color", or "" if normalization drops it)
    public let kind: Kind
    public let range: Range<Int>      // [start, end) UTF-16 offsets into the witness text
    // Scholarly citation coordinates, matching how a printed witness is referenced:
    public let line: Int              // 0-based TEXT line WITHIN THE PAGE (blank/marker lines not counted)
    public let paragraph: Int         // 0-based paragraph index within the witness
    public let page: Int              // 0-based page index (see page-break markers) — for "across pages"
    public let wordIndex: Int         // 0-based word position WITHIN ITS LINE (the Nth word on that line)

    public init(surface: String, normalized: String, kind: Kind,
                range: Range<Int>, line: Int, paragraph: Int, page: Int, wordIndex: Int) {
        self.surface = surface
        self.normalized = normalized
        self.kind = kind
        self.range = range
        self.line = line
        self.paragraph = paragraph
        self.page = page
        self.wordIndex = wordIndex
    }

    /// A token that carries no comparison weight after normalization (e.g. punctuation folded to "").
    public var isComparable: Bool { !normalized.isEmpty }
}
