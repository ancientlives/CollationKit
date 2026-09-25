import Foundation

// MARK: - JSON interchange (cross-language / web / WASM)
//
// A STABLE, self-describing JSON encoding of collation results, decoupled from the engine's internal Swift
// types. Purpose: let non-Swift consumers — a future WASM/web front end, a comparison harness against other
// collators (e.g. CollateX), a notebook — read the engine's output without the Swift value semantics. The
// DTOs below are the versioned wire contract; they deliberately reshape internal representations into shapes
// that travel well across languages:
//   • token ranges become explicit { from, to } (half-open), not Swift's Range encoding;
//   • locations carry BOTH 0-based fields and the 1-based `cite` string, so a JS client needn't re-derive it;
//   • the variant-graph readings (a Set) are sorted arrays, so output is deterministic across runs/languages.
// Bump `schemaVersion` on any breaking change to this shape.

public enum CollationJSON {

    // v3 (B6c): the variant graph can carry INSERTED nodes — `basePosition` may be -1 and an optional
    // `insertedAfter` records the base position an insertion follows. Additive to consumers that ignore
    // unknown/absent fields, but bumped because a node's `basePosition` can now be negative.
    public static let schemaVersion = 3

    // MARK: DTOs (the wire schema)

    public struct RangeDTO: Codable, Equatable {
        public let from: Int   // inclusive lower bound (token index)
        public let to: Int     // exclusive upper bound
    }

    public struct LocationDTO: Codable, Equatable {
        public let page: Int          // 0-based
        public let line: Int          // 0-based, page-relative, text lines only
        public let endLine: Int
        public let firstWord: Int     // 0-based, line-relative
        public let lastWord: Int
        public let charFrom: Int      // UTF-16 offset, inclusive
        public let charTo: Int        // exclusive
        public let cite: String       // 1-based human citation, e.g. "p.1 · line 2 · word 3"
    }

    public struct VariationDTO: Codable, Equatable {
        public let type: VariationType
        public let baseReading: String
        public let comparedReading: String
        public let baseTokens: RangeDTO?
        public let comparedTokens: RangeDTO?
        public let baseLocation: LocationDTO?
        public let comparedLocation: LocationDTO?
        public let crossesPage: Bool
        public let withinTransposition: Bool
        /// For a transposition: "certain" (anchored / exact displaced match) or "likely" (heuristic
        /// near-match). "certain" for every other variation type. (Schema v2.)
        public let confidence: MoveConfidence
    }

    public struct PairwiseDTO: Codable, Equatable {
        public let schemaVersion: Int
        public let base: String        // base witness id
        public let compared: String    // compared witness id
        public let counts: [String: Int]   // {insertion, deletion, substitution, transposition, variantSpelling}
        public let variations: [VariationDTO]
    }

    public struct GraphNodeDTO: Codable, Equatable {
        public let basePosition: Int      // base token index, or -1 for an inserted node (B6c)
        /// For an inserted node: the base position it follows (-1 = before all base text). Absent/`null` for a
        /// normal base-anchored node. Lets a consumer place inserted text between two base positions.
        public let insertedAfter: Int?
        public let isVariant: Bool
        /// reading → sorted list of witness sigla carrying it (deterministic; a Set would be order-unstable).
        public let readings: [ReadingDTO]
    }

    public struct ReadingDTO: Codable, Equatable {
        public let reading: String
        public let witnesses: [String]
    }

    public struct GraphDTO: Codable, Equatable {
        public let schemaVersion: Int
        public let baseID: String
        public let nodes: [GraphNodeDTO]
    }

    // MARK: encoding (model → DTO → JSON string)

    public static func dto(_ r: CollationResult) -> PairwiseDTO {
        PairwiseDTO(
            schemaVersion: schemaVersion,
            base: r.base, compared: r.compared,
            counts: [
                "insertion": r.insertions, "deletion": r.deletions, "substitution": r.substitutions,
                "transposition": r.transpositions, "variantSpelling": r.variantSpellings,
            ],
            variations: r.variations.map(dto))
    }

    public static func dto(_ v: Variation) -> VariationDTO {
        VariationDTO(
            type: v.type, baseReading: v.baseReading, comparedReading: v.comparedReading,
            baseTokens: v.baseTokenRange.map { RangeDTO(from: $0.lowerBound, to: $0.upperBound) },
            comparedTokens: v.comparedTokenRange.map { RangeDTO(from: $0.lowerBound, to: $0.upperBound) },
            baseLocation: v.baseLocation.map(dto), comparedLocation: v.comparedLocation.map(dto),
            crossesPage: v.crossesPage, withinTransposition: v.withinTransposition,
            confidence: v.confidence)
    }

    public static func dto(_ l: TextLocation) -> LocationDTO {
        LocationDTO(page: l.page, line: l.line, endLine: l.endLine,
                    firstWord: l.firstWord, lastWord: l.lastWord,
                    charFrom: l.charRange.lowerBound, charTo: l.charRange.upperBound, cite: l.human)
    }

    public static func dto(_ g: Collation.VariantGraph) -> GraphDTO {
        GraphDTO(
            schemaVersion: schemaVersion, baseID: g.baseID,
            nodes: g.nodes.map { node in
                GraphNodeDTO(
                    basePosition: node.basePosition, insertedAfter: node.insertedAfter,
                    isVariant: node.isVariant,
                    readings: node.readings
                        .map { ReadingDTO(reading: $0.key, witnesses: $0.value.sorted()) }
                        .sorted { $0.reading < $1.reading })   // deterministic ordering
            })
    }

    // MARK: top-level CLI artifact (the shape `collate-demo --json` and the conformance corpus share)

    /// The full interchange a consumer receives: the N-witness variant graph plus each successive pair.
    /// This is the exact artifact emitted by `collate-demo --json` and pinned by the conformance corpus;
    /// the schema (`docs/conformance/collation.schema.json`) describes this top-level object.
    public struct Output: Codable, Equatable {
        public let graph: GraphDTO
        public let pairs: [PairwiseDTO]
        public init(graph: GraphDTO, pairs: [PairwiseDTO]) { self.graph = graph; self.pairs = pairs }
    }

    /// Build the `{ graph, pairs }` interchange for a witness set. Single code path shared by the CLI and
    /// the conformance tests, so committed goldens are byte-identical to real CLI output.
    public static func output(witnesses: [Witness], normalizer: Normalizer = .substantive,
                              pagination: PaginationModel = .default,
                              scores: AlignmentScores = .prose,
                              recordAccidentals: Bool = false,
                              recordPunctuation: Bool = false,
                              strategy: CollationStrategy = .baseAnchored,
                              lexicon: TranslationLexicon? = nil) -> Output {
        let graph = Collation.variantGraph(witnesses: witnesses, normalizer: normalizer,
                                           scores: scores, pagination: pagination, strategy: strategy,
                                           lexicon: lexicon)
        var pairs: [PairwiseDTO] = []
        for i in 1..<witnesses.count {
            let r = Collation.collate(base: witnesses[i - 1], compared: witnesses[i],
                                      normalizer: normalizer, scores: scores,
                                      recordAccidentals: recordAccidentals,
                                      recordPunctuation: recordPunctuation, pagination: pagination,
                                      lexicon: lexicon)
            pairs.append(dto(r))
        }
        return Output(graph: dto(graph), pairs: pairs)
    }

    /// The same artifact as a pretty, key-sorted JSON string (deterministic; safe to snapshot/diff).
    public static func outputString(witnesses: [Witness], normalizer: Normalizer = .substantive,
                                    pagination: PaginationModel = .default,
                                    scores: AlignmentScores = .prose,
                                    recordAccidentals: Bool = false,
                                    recordPunctuation: Bool = false,
                                    strategy: CollationStrategy = .baseAnchored,
                                    lexicon: TranslationLexicon? = nil) -> String {
        encodeToString(output(witnesses: witnesses, normalizer: normalizer,
                              pagination: pagination, scores: scores,
                              recordAccidentals: recordAccidentals,
                              recordPunctuation: recordPunctuation, strategy: strategy,
                              lexicon: lexicon),
                       pretty: true)
    }

    /// Build the interchange from ALREADY-COMPUTED results — the same DTO mapping and encoding as the
    /// witness-based form, minus the engine work. For a caller that has just collated (the CLI runner), the
    /// witness-based `output` would silently re-run the whole engine (every pair + the graph) just to encode
    /// it — on a full-novel set that doubles minutes of work (surfaced by the Verne corpus in a debug build).
    /// CONTRACT: `graph`/`pairs` must be the results the witness-based call would compute for the same inputs
    /// (same witnesses, options, strategy, lexicon); the CLI's golden byte-identity test enforces the tie.
    public static func output(graph: Collation.VariantGraph, pairs: [CollationResult]) -> Output {
        Output(graph: dto(graph), pairs: pairs.map { dto($0) })
    }

    /// `output(graph:pairs:)` as the pretty, key-sorted JSON string.
    public static func outputString(graph: Collation.VariantGraph, pairs: [CollationResult]) -> String {
        encodeToString(output(graph: graph, pairs: pairs), pretty: true)
    }

    // MARK: convenience — straight to a JSON string

    /// Pretty-printed, key-sorted JSON for a pairwise collation. Sorted keys keep output byte-stable (good for
    /// snapshot tests and cross-language diffing).
    public static func string(_ r: CollationResult, pretty: Bool = true) -> String {
        encodeToString(dto(r), pretty: pretty)
    }

    public static func string(_ g: Collation.VariantGraph, pretty: Bool = true) -> String {
        encodeToString(dto(g), pretty: pretty)
    }

    private static func encodeToString<T: Encodable>(_ value: T, pretty: Bool) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}
