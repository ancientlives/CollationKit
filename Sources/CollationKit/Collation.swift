import Foundation

// MARK: - Collation facade — the public entry point
//
// A pure `enum` of static functions, value-type I/O, deterministic.
// `collate(base:compared:)` runs the whole pipeline for a PAIR of witnesses:
//   tokenize+normalize → transposition-aware align → classify → apparatus.
// `variantGraph(witnesses:)` is the N-witness structure (progressive alignment against a base, the
// "Gothenburg model"): tokenize → normalize → align each witness to the base → fold into a graph of
// readings keyed by base position, recording which witnesses agree and where they diverge.

public struct CollationResult: Equatable {
    public let base: String                 // base witness id
    public let compared: String             // compared witness id
    public let variations: [Variation]
    /// Convenience tallies for tests/UI.
    public var insertions: Int { variations.filter { $0.type == .insertion }.count }
    public var deletions: Int { variations.filter { $0.type == .deletion }.count }
    public var substitutions: Int { variations.filter { $0.type == .substitution }.count }
    public var transpositions: Int { variations.filter { $0.type == .transposition }.count }
    public var variantSpellings: Int { variations.filter { $0.type == .variantSpelling }.count }
    public var crossPageVariations: [Variation] { variations.filter { $0.crossesPage } }
}

/// Which N-witness merge strategy `Collation.variantGraph` uses to populate the token-graph. The two occupy
/// different points on a **quality / cost / base-dependence** trade space, so the engine keeps both as a
/// selectable option rather than hard-wiring one (see `docs/reference/PAPER_NOTES.md §5.4`):
///
/// - `.baseAnchored` — the shipping B11 path: build the token-graph by *lifting* N−1 pairwise alignments against
///   a fixed **base** (copy-text). Predictable, bounded cost; the apparatus is keyed to the copy-text (the
///   editorial convention). Best for one author's successive editions and for interactive / constrained-runtime
///   collation. Base-sensitive: re-choosing the base can shift the apparatus.
/// - `.peerMSA` — **the peer multiple-sequence alignment (B14, landed 2026-07-06).** Each witness is aligned
///   against the *whole growing graph* (the linear consensus spine — see `PeerMSA.swift` and
///   `PAPER_NOTES.md §5.3`), so non-base-shared variance groups correctly, recurring-word moves are `certain`
///   from structure, and — with a B10 `TranslationLexicon` — cross-language witness sets anchor on
///   translation-equivalent forms. Best for base-free material (competing translations, independent
///   witnesses) and offline quality-first collation; the apparatus is still *rendered* against
///   `witnesses[0]`, but no alignment decision privileges it.
public enum CollationStrategy: String, Equatable, CaseIterable {
    case baseAnchored
    case peerMSA

    /// Whether this strategy is implemented and will run as itself (vs. falling back). Both are available
    /// since B14 landed; the property remains so callers/ports can gate on it.
    public var isAvailable: Bool {
        switch self {
        case .baseAnchored: return true
        case .peerMSA: return true
        }
    }

    /// A short, user-facing label (plain language, no jargon) — for a UI affordance or CLI help.
    public var label: String {
        switch self {
        case .baseAnchored: return "Apparatus keyed to a copy-text (faster)"
        case .peerMSA: return "Peer alignment — best when witnesses have no base text (slower, more thorough)"
        }
    }

    /// The **context-aware default** (UI/UX policy, `PAPER_NOTES §5.4`): if the set has a designated copy-text
    /// (`base` non-nil, the common editorial case) prefer `.baseAnchored`; if there is no privileged witness,
    /// prefer `.peerMSA` (available since B14). A host app *suggests* this; the user may override. Kept here
    /// (not in the UI) so the CLI, tests, and any host app share one policy.
    public static func contextualDefault(hasCopyText: Bool) -> CollationStrategy {
        if hasCopyText { return .baseAnchored }
        return CollationStrategy.peerMSA.isAvailable ? .peerMSA : .baseAnchored
    }
}

public enum Collation {

    /// Collate two witnesses. The `normalizer` controls the substantive/accidental distinction (default
    /// folds accidentals so only meaningful variants surface).
    /// `recordAccidentals`: when true, surface-only differences at aligned positions (spelling/case/
    /// punctuation that normalization folded) are reported as `.variantSpelling`. Default false → a
    /// substantive-only apparatus.
    /// `recordPunctuation` (default false): when true, punctuation-only differences between aligned words —
    /// comma drops, `:`→`;`, `—`→space — are reported as `.variantSpelling` accidentals (the *diplomatic*
    /// layer). Punctuation still does NOT drive alignment (prose aligns to prose); this is a pure overlay, so
    /// the substantive apparatus is byte-identical with it off. Surfaced by the real-edition study, where the
    /// Frankenstein 1818→1831 changes were almost all punctuation and thus invisible (BACKLOG B6b).
    /// `lexicon` (default nil, B10): a bilingual `TranslationLexicon` whose groups are treated as the SAME
    /// alignment key, so a translation pair ("année"/"year") anchors instead of drifting positionally.
    /// Alignment-only: readings keep each witness's own words; nil = identity = unchanged behaviour.
    public static func collate(base: Witness, compared: Witness,
                               normalizer: Normalizer = .substantive,
                               anchorLength: Int = 3,
                               scores: AlignmentScores = AlignmentScores(),
                               recordAccidentals: Bool = false,
                               recordPunctuation: Bool = false,
                               pagination: PaginationModel = .default,
                               lexicon: TranslationLexicon? = nil) -> CollationResult {
        let baseTokens = Tokenizer.tokenize(base.text, with: normalizer, pagination: pagination)
        let compTokens = Tokenizer.tokenize(compared.text, with: normalizer, pagination: pagination)

        // Reduce to the comparable tokens the aligner sees, keeping a map back to full-token indices and a
        // parallel page list so the aligner can break transposition ties in favour of the page-stable block.
        let (aKeys, aMap, aPages) = comparable(baseTokens, lexicon: lexicon)
        let (bKeys, bMap, bPages) = comparable(compTokens, lexicon: lexicon)

        let aligned = Transposition.align(aKeys, bKeys, anchorLength: anchorLength, scores: scores,
                                          aPages: aPages, bPages: bPages)
        let variations = VariationClassifier.classify(aligned, base: baseTokens, compared: compTokens,
                                                      aMap: aMap, bMap: bMap,
                                                      recordAccidentals: recordAccidentals,
                                                      recordPunctuation: recordPunctuation,
                                                      lexicon: lexicon)
        return CollationResult(base: base.id, compared: compared.id, variations: variations)
    }

    /// The comparable-key sequence + a parallel map from comparable index → full-token index + the page of
    /// each comparable token (for the aligner's page-aware tie-break). With a `lexicon` (B10), keys are the
    /// lexicon's PIVOT forms, so translation-equivalent words compare equal in the aligner; readings/surfaces
    /// downstream are untouched (the maps still reference the real tokens).
    static func comparable(_ tokens: [Token],
                           lexicon: TranslationLexicon? = nil) -> (keys: [String], map: [Int], pages: [Int]) {
        var keys: [String] = []
        var map: [Int] = []
        var pages: [Int] = []
        for (i, t) in tokens.enumerated() where t.isComparable {
            keys.append(lexicon?.pivot(t.normalized) ?? t.normalized)
            map.append(i)
            pages.append(t.page)
        }
        return (keys, map, pages)
    }

    // MARK: N-witness variant graph (progressive, base-anchored)

    /// A point of variation across all witnesses. Most nodes are keyed to a base-token position
    /// (`basePosition`); a node created for text some witnesses **insert** where the base has nothing is an
    /// *inserted node* — it has no base token, so `basePosition == -1` and `insertedAfter` records the base
    /// position it follows (the "insert-after" anchor; -1 = before all base text). `readings` maps a reading
    /// (surface) → the set of witness ids that carry it; `∅` is the reading for witnesses that DON'T carry the
    /// insertion (they omit it). More than one reading ⇒ a divergence the apparatus records.
    ///
    /// Inserted nodes (B6c) are what let the N-witness apparatus/synopsis show text added in some witnesses —
    /// e.g. a stanza Whitman added in 1891 — which the earlier base-anchored fold dropped ("(no points of
    /// variance)"). They sort *after* their anchor base position but *before* the next (see `variantGraph`).
    public struct GraphNode: Equatable {
        public let basePosition: Int           // base token index, or -1 for an inserted-only node
        /// For an inserted node: the base position it follows (-1 = before all base text). `nil` for a normal
        /// base-anchored node.
        public let insertedAfter: Int?
        public let readings: [String: Set<String>]
        public var isVariant: Bool { readings.count > 1 }
        /// True when this node exists only because some witness inserted text here (no base token).
        public var isInserted: Bool { basePosition < 0 }

        public init(basePosition: Int, readings: [String: Set<String>], insertedAfter: Int? = nil) {
            self.basePosition = basePosition
            self.readings = readings
            self.insertedAfter = insertedAfter
        }
    }

    /// A run of base text that one or more witnesses carry in a different place (a transposition). The moved
    /// words agree with the base, so they are not variant nodes; without this record the apparatus could not show
    /// a move at all (release 1 review, B3). `basePositions` are base full-token positions of the moved words, in
    /// order; `lemma` is the base's reading of them; `witnesses` are the witnesses that moved them, with the
    /// confidence the merge assigned.
    public struct GraphMove: Equatable {
        public let basePositions: [Int]
        public let lemma: String
        public let witnesses: Set<String>
        public let confidence: MoveConfidence
    }

    public struct VariantGraph: Equatable {
        public let baseID: String
        public let nodes: [GraphNode]
        /// Transpositions relative to the base, in base-text order. (Not part of the JSON interchange: the pairwise
        /// results there already carry every move with its full citation.)
        public var moves: [GraphMove] = []
        /// The nodes where witnesses disagree — the apparatus.
        public var variantNodes: [GraphNode] { nodes.filter { $0.isVariant } }
    }

    /// Build an N-witness variant graph across the whole witness set. As of B11 this is backed by the
    /// **token-graph merge** (`TokenGraph.build`): all witnesses are merged into one DAG (nodes = aligned
    /// tokens, moves = out-of-spine edges, off-spine insertions = inserted nodes), which is then projected onto
    /// this apparatus-facing `VariantGraph` for the renderers. The projection reproduces the shape the earlier
    /// base-anchored fold produced (so `Apparatus`/`Synopsis`/`CollationJSON` are unchanged), while the graph
    /// substrate handles moves and insertions uniformly. See `docs/development/TOKEN_GRAPH_PLAN.md`.
    /// `strategy` (default `.baseAnchored`) selects the N-witness merge strategy (see `CollationStrategy` and
    /// `docs/reference/PAPER_NOTES.md §5.4`): `.baseAnchored` is the B11 lift (apparatus keyed to the
    /// copy-text; predictable cost); `.peerMSA` is the B14 peer merge (base-agnostic alignment; groups
    /// non-base-shared variance; `certain` recurring-word moves). `lexicon` (B10, default nil) supplies
    /// translation-equivalent anchor forms for cross-language sets; nil = unchanged behaviour.
    /// `reusing` (perf seam): pairwise results against the base the caller already holds — consumed by the
    /// `.baseAnchored` lift instead of re-collating (see `TokenGraph.build(reusing:)` for the contract);
    /// ignored by `.peerMSA` (the peer merge aligns against the consensus, not pairwise results).
    public static func variantGraph(witnesses: [Witness],
                                    normalizer: Normalizer = .substantive,
                                    anchorLength: Int = 3,
                                    scores: AlignmentScores = .prose,
                                    pagination: PaginationModel = .default,
                                    strategy: CollationStrategy = .baseAnchored,
                                    lexicon: TranslationLexicon? = nil,
                                    reusing precomputed: [CollationResult] = [],
                                    progress: ((String) -> Void)? = nil) -> VariantGraph {
        variantGraphWithTokens(witnesses: witnesses, normalizer: normalizer, anchorLength: anchorLength,
                               scores: scores, pagination: pagination, strategy: strategy, lexicon: lexicon,
                               reusing: precomputed, progress: progress).graph
    }

    /// Same as `variantGraph`, but also returns the underlying `TokenGraph` (the merge substrate — spine, edges,
    /// `isMove`, inserted-node anchors) when the build produced one. The apparatus-facing `VariantGraph`
    /// projection deliberately drops that structure; the interactive viewer's *visual* variant-graph (B8 / #2
    /// of VIEWER_UX_PLAN) needs it back, so callers that want to render the graph shape take this path and pass
    /// `tokens` through to the exporter. `tokens` is nil only when no graph could be built (empty set / fallback).
    public static func variantGraphWithTokens(witnesses: [Witness],
                                              normalizer: Normalizer = .substantive,
                                              anchorLength: Int = 3,
                                              scores: AlignmentScores = .prose,
                                              pagination: PaginationModel = .default,
                                              strategy: CollationStrategy = .baseAnchored,
                                              lexicon: TranslationLexicon? = nil,
                                              reusing precomputed: [CollationResult] = [],
                                              progress: ((String) -> Void)? = nil)
        -> (graph: VariantGraph, tokens: TokenGraph?) {
        guard let base = witnesses.first else {
            return (VariantGraph(baseID: "", nodes: []), nil)
        }
        switch strategy {
        case .baseAnchored:
            if let graph = TokenGraph.build(witnesses: witnesses, normalizer: normalizer,
                                            pagination: pagination, anchorLength: anchorLength,
                                            scores: scores, lexicon: lexicon, reusing: precomputed,
                                            progress: progress),
               let projected = graph.projectedVariantGraph(baseID: base.id) {
                return (projected, graph)
            }
            // Unreachable for a non-empty witness set (the guard above handles the empty one). The pre-B11 fold that
            // used to live here (`legacyVariantGraph`) was removed in 2026-10: it was dead and duplicated bug B2.
            return (VariantGraph(baseID: base.id, nodes: []), nil)
        case .peerMSA:
            if let graph = TokenGraph.buildPeerMSA(witnesses: witnesses, normalizer: normalizer,
                                                   pagination: pagination, anchorLength: anchorLength,
                                                   scores: scores, lexicon: lexicon, progress: progress),
               let projected = graph.projectedVariantGraph(baseID: base.id) {
                return (projected, graph)
            }
            return (VariantGraph(baseID: base.id, nodes: []), nil)
        }
    }

}
