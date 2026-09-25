import CollationKit
import Foundation

// MARK: - The one place that drives the engine (BACKLOG B9, CLI_PLAN §2)
//
// `CollationRunner` takes validated options + loaded witnesses and calls the `CollationKit` public API to
// produce a `CollationRun` — the pairwise results, the N-witness graph, and the render models. It is the SINGLE
// point of contact with the engine (CLI_PLAN §0 rule 1: no engine logic anywhere else in the CLI). Exporters
// and console output work off the `CollationRun`, never the engine directly.

/// Everything a run produces, ready to render/export. Value type, deterministic (mirrors the engine's output).
public struct CollationRun {
    public let baseID: String
    public let witnessOrder: [String]
    public let witnesses: [Witness]               // kept so the JSON export goes through the exact corpus path
    public let pairs: [CollationResult]           // successive-pair collations (order[i-1] vs order[i])
    public let graph: Collation.VariantGraph      // N-witness variant graph (base = order[0])
    /// The merge substrate the `graph` projection came from (spine, edges, `isMove`, inserted-node anchors).
    /// The projection deliberately drops this structure; the interactive viewer's *visual* variant-graph needs
    /// it back (VIEWER_UX_PLAN #2). Nil only when no graph could be built (empty set / legacy fallback).
    public let tokenGraph: TokenGraph?
    public let options: CLIOptions
    public let lexicon: TranslationLexicon?       // B10: kept so the JSON export reproduces the run exactly
    /// Base-anchored pairwise results (base ↔ each other witness), computed when the run will feed the
    /// interactive HTML viewer (B8): the viewer's perspectives annotate each witness's text with how it
    /// differs from the base, which needs char-range variations against the base — not the successive pairs.
    /// For a 2-witness run this IS `pairs` (reused, no extra work); empty when the viewer isn't wanted.
    public let basePairs: [CollationResult]

    public init(baseID: String, witnessOrder: [String], witnesses: [Witness],
                pairs: [CollationResult], graph: Collation.VariantGraph, options: CLIOptions,
                lexicon: TranslationLexicon? = nil, basePairs: [CollationResult] = [],
                tokenGraph: TokenGraph? = nil) {
        self.baseID = baseID; self.witnessOrder = witnessOrder; self.witnesses = witnesses
        self.pairs = pairs; self.graph = graph; self.options = options; self.lexicon = lexicon
        self.basePairs = basePairs; self.tokenGraph = tokenGraph
    }

    /// Total variants across the successive pairs (the number a user thinks of as "how many variants").
    public var totalPairVariants: Int { pairs.reduce(0) { $0 + $1.variations.count } }
}

public enum CollationRunner {

    /// Run the collation for the given options + witnesses (+ optional pre-loaded B10 lexicon — file IO stays
    /// in the caller). Pure and deterministic: same inputs → same `CollationRun`.
    ///
    /// `includeViewerPairs`: also compute the base-anchored pairs the HTML viewer needs (skipped otherwise —
    /// for N > 2 they are extra collations; for N = 2 the successive pair is reused free).
    /// `progress`: optional stage reporting ("collating pair 1/2 …") so a long run is never silent — the
    /// caller chooses the channel (the CLI sends it to stderr, keeping stdout clean for piped output).
    public static func run(_ opts: CLIOptions, witnesses: [Witness],
                           lexicon: TranslationLexicon? = nil,
                           includeViewerPairs: Bool = false,
                           progress: ((String) -> Void)? = nil) -> CollationRun {
        let pagination = opts.pagination.model
        let normalizer = opts.normalizer
        let scores = opts.scoring.scores
        let pairCount = max(0, witnesses.count - 1)

        var pairs: [CollationResult] = []
        for i in 1..<witnesses.count {
            progress?("collating pair \(i)/\(pairCount): \(witnesses[i - 1].id) ↔ \(witnesses[i].id) …")
            pairs.append(Collation.collate(
                base: witnesses[i - 1], compared: witnesses[i],
                normalizer: normalizer, scores: scores,
                recordAccidentals: opts.effectiveRecordAccidentals,
                recordPunctuation: opts.effectiveRecordPunctuation,
                pagination: pagination, lexicon: lexicon))
        }

        // The viewer's base-anchored pairs, computed BEFORE the graph so the graph build can consume them
        // (witnesses[0] ↔ witnesses[1] is exactly pairs[0], so it is always reused; further witnesses need
        // their own collation against the base).
        var basePairs: [CollationResult] = []
        if includeViewerPairs, witnesses.count >= 2 {
            basePairs.append(pairs[0])
            for i in 2..<witnesses.count {
                progress?("collating against base for the viewer: \(witnesses[0].id) ↔ \(witnesses[i].id) …")
                basePairs.append(Collation.collate(
                    base: witnesses[0], compared: witnesses[i],
                    normalizer: normalizer, scores: scores,
                    recordAccidentals: opts.effectiveRecordAccidentals,
                    recordPunctuation: opts.effectiveRecordPunctuation,
                    pagination: pagination, lexicon: lexicon))
            }
        }

        // Hand every base-anchored result we already hold to the graph build, so the `.baseAnchored` lift
        // does NOT re-collate them (it used to — on a full-novel pair that silently doubled the run; in a
        // debug build it read as a hang). Without viewer pairs, pairs[0] is still base-anchored and reusable.
        let reusable = basePairs.isEmpty ? Array(pairs.prefix(1)) : basePairs
        progress?("building the N-witness variant graph (\(opts.strategy.rawValue)) …")
        // Forward the graph build's per-witness sub-stages through the same channel, indented so they read as
        // steps under the header above — otherwise this stage is a single line that looks frozen on a full-text
        // run (the merge folds each witness onto the spine in turn; on a large debug build each fold is seconds).
        let (graph, tokenGraph) = Collation.variantGraphWithTokens(
            witnesses: witnesses, normalizer: normalizer,
            scores: scores, pagination: pagination, strategy: opts.strategy,
            lexicon: lexicon, reusing: reusable,
            progress: progress.map { p in { p("  " + $0) } })

        return CollationRun(baseID: graph.baseID, witnessOrder: witnesses.map { $0.id },
                            witnesses: witnesses, pairs: pairs, graph: graph, options: opts,
                            lexicon: lexicon, basePairs: basePairs, tokenGraph: tokenGraph)
    }
}
