import Foundation

// MARK: - Token-graph merge (BACKLOG B11)
//
// The successor to the base-anchored progressive fold: all witnesses are merged into one DAG where every
// token is a node, witnesses traverse edges in reading order, and a run that aligns to existing nodes but
// OUT OF spine order is a move (one transposition). This is what lets single-word, recurring-word, and
// N-witness moves be handled uniformly — and why pure insertions (off-spine nodes) need no `insertionAnchor`
// special-casing at the graph level.
//
// Migration stance (TOKEN_GRAPH_PLAN.md §4): the graph is built by *merging the pairwise engine's results*
// into a shared structure rather than re-implementing alignment. The pairwise `Collation.collate` already
// resolves substitution / insertion / deletion / transposition (incl. recursive anchoring and the page-aware
// tie-break); B11 lifts those per-witness results into ONE graph across the whole set. `projectedVariantGraph`
// projects the graph back onto the apparatus-facing `Collation.VariantGraph`, so `Apparatus`, `Synopsis`,
// `CollationJSON`, the CLI and a host app consume it unchanged. The headline new capability the graph gives over
// the old fold is the RECURRING-WORD move: because the move is read off graph structure (an out-of-spine
// traversal edge) rather than a brittle single-word post-pass, it is reported `certain`, not `likely`/missed.

/// A node in the token-graph: a set of aligned tokens across witnesses (keyed by normalised form), agreement
/// when every witness in the set shares it.
public struct TokenGraphNode: Equatable {
    public typealias NodeID = Int
    public let id: NodeID
    /// normalised key → the surface + the witnesses carrying it at this node.
    public let readings: [String: TokenGraphReading]
    /// True when every witness under comparison shares this node (no variance here).
    public let isAgreement: Bool

    public init(id: NodeID, readings: [String: TokenGraphReading], isAgreement: Bool) {
        self.id = id; self.readings = readings; self.isAgreement = isAgreement
    }
}

public struct TokenGraphReading: Equatable {
    public let surface: String
    public let witnesses: Set<String>
    public init(surface: String, witnesses: Set<String>) { self.surface = surface; self.witnesses = witnesses }
}

/// A directed edge: which witnesses traverse from `from` to `to` in reading order; `isMove` when this traversal
/// is out of the canonical spine order (i.e. a transposition for those witnesses). A move edge carries a
/// `confidence`: under the base-anchored lift it is inherited from the pairwise pass; under the peer MSA (B14)
/// it is computed FROM STRUCTURE (whether the displaced run is unambiguous in the merged graph) — which is how
/// a recurring-word move the pairwise post-pass can only call `likely` becomes `certain`.
public struct TokenGraphEdge: Equatable {
    public let from: TokenGraphNode.NodeID
    public let to: TokenGraphNode.NodeID
    public let witnesses: Set<String>
    public let isMove: Bool
    public let confidence: MoveConfidence
    public init(from: TokenGraphNode.NodeID, to: TokenGraphNode.NodeID, witnesses: Set<String>, isMove: Bool,
                confidence: MoveConfidence = .certain) {
        self.from = from; self.to = to; self.witnesses = witnesses; self.isMove = isMove
        self.confidence = confidence
    }
}

/// The merged variant graph across all witnesses, with a canonical reading order (`spine`).
public struct TokenGraph: Equatable {
    public let nodes: [TokenGraphNode]
    public let edges: [TokenGraphEdge]
    public let spine: [TokenGraphNode.NodeID]   // canonical reading order (the copy-text path)

    /// Projection metadata carried from the build so `projectedVariantGraph` is exact rather than heuristic:
    /// the base comparable-token position each spine node maps to, and the insert-after anchor of each
    /// off-spine inserted node (by node id). Not part of graph identity/equality (it is derived from the same
    /// merge), so it is excluded from `Equatable` below.
    public var baseComparablePositions: [Int] = []          // spine index → base full-token position
    public var insertedAnchorByNodeID: [TokenGraphNode.NodeID: Int] = [:]

    public init(nodes: [TokenGraphNode], edges: [TokenGraphEdge], spine: [TokenGraphNode.NodeID]) {
        self.nodes = nodes; self.edges = edges; self.spine = spine
    }

    public static func == (lhs: TokenGraph, rhs: TokenGraph) -> Bool {
        lhs.nodes == rhs.nodes && lhs.edges == rhs.edges && lhs.spine == rhs.spine
    }
}

// MARK: - build

public extension TokenGraph {

    /// Build the token-graph for a witness set by merging every witness onto the base (`witnesses[0]`), the
    /// same base as the apparatus. The base seeds the spine; each further witness's pairwise collation against
    /// the base tells us, per base position, whether it agrees / substitutes / omits, what it inserts and
    /// where, and which runs MOVED — and each of those is recorded on the shared graph (readings on nodes,
    /// off-spine insertions as extra nodes, moves as `isMove` edges).
    ///
    /// Determinism (ALGORITHMS §9): node ids are assigned in spine-then-insertion order; readings and edge
    /// witness sets are value types compared structurally; nothing here depends on dictionary iteration order.
    /// `reusing`: pairwise results the caller has ALREADY computed against the base (`collate(witnesses[0],
    /// w)` with the same normalizer/anchorLength/scores/pagination/lexicon). The build consumes a matching
    /// result instead of re-collating that witness — on a full-novel pair this halves the engine work (the
    /// CLI runner always has these). Results are matched by (base id, compared id); anything missing is
    /// computed as before. The accidental/punctuation overlays are safe to differ: the fold ignores
    /// `.variantSpelling` (overlays never change substantive alignment), so a pair collated with overlays on
    /// folds to the same graph.
    /// `progress`: optional per-stage reporting so a long merge is never a silent black box — one line as each
    /// witness folds onto the spine (with whether its pairwise result was reused or freshly collated) and one
    /// for the finalisation. The callback is invoked synchronously on the calling thread; nil = no reporting.
    /// The reading a compared witness contributes to the `k`-th of `n` base nodes covered by a substitution, given
    /// the substitution's comparable compared tokens `compWords` (release 1 review, B2):
    ///   • equal word counts → one-to-one;
    ///   • otherwise one-to-one up to the last shared position, which carries ALL remaining compared words joined
    ///     (so no compared text is lost), and any further base node reads `∅` (omitted).
    /// `red green` → `blue, yellow` gives `red] blue`, `green] yellow`; `red` → `very bright blue` gives
    /// `red] very bright blue`; `red green` → `crimson` gives `red] crimson`, `green] ∅`.
    static func substitutionReading(forBaseNode k: Int, of n: Int, compWords: [Int],
                                    compTokens: [Token]) -> (normalized: String, surface: String) {
        let m = compWords.count
        guard m > 0, k < m else { return ("∅", "∅") }
        let lastShared = min(n, m) - 1
        let span = k == lastShared ? Array(compWords[k...]) : [compWords[k]]
        return (span.map { compTokens[$0].normalized }.joined(separator: " "),
                span.map { compTokens[$0].surface }.joined(separator: " "))
    }

    static func build(witnesses: [Witness],
                      normalizer: Normalizer = .substantive,
                      pagination: PaginationModel = .default,
                      anchorLength: Int = 3,
                      scores: AlignmentScores = .prose,
                      lexicon: TranslationLexicon? = nil,
                      reusing precomputed: [CollationResult] = [],
                      progress: ((String) -> Void)? = nil) -> TokenGraph? {
        guard let base = witnesses.first else { return nil }
        let baseTokens = Tokenizer.tokenize(base.text, with: normalizer, pagination: pagination)

        // Comparable base positions, in order — these seed the spine. Each becomes a node whose readings we
        // fold the other witnesses onto. A parallel `basePos → nodeIndex` map lets the per-witness passes find
        // the node for a base token.
        let basePositions = baseTokens.enumerated().filter { $0.element.isComparable }.map { $0.offset }
        var nodeReadings: [[String: TokenGraphReading]] = []      // one entry per spine node, in spine order
        var nodeIndexForBasePos: [Int: Int] = [:]
        for pos in basePositions {
            let t = baseTokens[pos]
            nodeIndexForBasePos[pos] = nodeReadings.count
            nodeReadings.append([t.normalized: TokenGraphReading(surface: t.surface, witnesses: [base.id])])
        }

        // Off-spine INSERTED nodes, collected by (insert-after base position, normalised inserted reading) so
        // the same insertion shared by several witnesses coalesces onto one node — the structural equivalent of
        // B6c, but falling out of the merge rather than needing an `insertionAnchor` special case downstream.
        struct InsertKey: Hashable { let anchor: Int; let normalized: String }
        var insertReadings: [InsertKey: TokenGraphReading] = [:]

        // Move edges: a witness traverses out of spine order across a moved run. We record one edge per moved
        // block per witness, from the spine node BEFORE the block's base span to the node AFTER it, flagged
        // `isMove`. That an edge exists at all is the graph's assertion "this witness reordered here"; the
        // pairwise result carries the exact spans/readings the projection and the located report use.
        struct MoveRecord { let witness: String; let fromNode: Int; let toNode: Int
                            let confidence: MoveConfidence }
        var moveRecords: [MoveRecord] = []

        let mergeCount = witnesses.count - 1
        for (offset, compared) in witnesses.dropFirst().enumerated() {
            let reused = precomputed.first { $0.base == base.id && $0.compared == compared.id }
            progress?("merging witness \(offset + 1)/\(mergeCount) onto the spine: "
                      + "\(base.id) ↔ \(compared.id)"
                      + (reused != nil ? " (reusing pairwise result)" : " (collating — no reusable pair)"))
            let result = reused
                ?? Collation.collate(base: base, compared: compared,
                                     normalizer: normalizer, anchorLength: anchorLength,
                                     scores: scores, pagination: pagination, lexicon: lexicon)
            let compTokens = Tokenizer.tokenize(compared.text, with: normalizer, pagination: pagination)

            var changed = Set<Int>()   // base positions this witness altered (deletion/substitution)
            for v in result.variations {
                switch v.type {
                case .deletion:
                    if let r = v.baseTokenRange {
                        for pos in r {
                            guard let ni = nodeIndexForBasePos[pos] else { continue }
                            addReading(&nodeReadings[ni], normalized: "∅", surface: "∅", witness: compared.id)
                            changed.insert(pos)
                        }
                    }
                case .substitution:
                    if let r = v.baseTokenRange {
                        // Fold the substitution onto the base nodes using COMPARABLE tokens on both sides (release 1
                        // review, B2). The ranges are full-token ranges, so they include punctuation; pairing by raw
                        // offset paired "green" with a comma and silently dropped every compared token past the
                        // base range's length.
                        let baseNodes = r.filter { nodeIndexForBasePos[$0] != nil }
                        let compWords = (v.comparedTokenRange.map { Array($0) } ?? [])
                            .filter { $0 < compTokens.count && compTokens[$0].isComparable }
                        for (k, pos) in baseNodes.enumerated() {
                            guard let ni = nodeIndexForBasePos[pos] else { continue }
                            let (norm, surf) = Self.substitutionReading(forBaseNode: k, of: baseNodes.count,
                                                                        compWords: compWords, compTokens: compTokens)
                            addReading(&nodeReadings[ni], normalized: norm, surface: surf, witness: compared.id)
                            changed.insert(pos)
                        }
                    }
                case .insertion:
                    // Off-spine inserted text (skip an edit inside a moved block — reported by the pairwise
                    // result, not a graph node). The anchor is the base token it follows (-1 = before all text).
                    if !v.withinTransposition, let anchor = v.insertionAnchor {
                        let key = InsertKey(anchor: anchor, normalized: normalizedReading(v.comparedReading))
                        addReading(&insertReadings, key: key,
                                   surface: v.comparedReading, witness: compared.id)
                    }
                case .transposition:
                    // A move: the witness carries the base text (agreement at the base positions), reordered.
                    // Record a move edge spanning the block; leave the base positions as agreement (below).
                    if let r = v.baseTokenRange {
                        let fromNode = r.lowerBound > 0 ? nearestNodeAtOrBefore(r.lowerBound - 1, nodeIndexForBasePos) : -1
                        let toNode = nearestNodeAtOrAfter(r.upperBound, nodeIndexForBasePos, count: nodeReadings.count)
                        moveRecords.append(MoveRecord(witness: compared.id, fromNode: fromNode, toNode: toNode,
                                                      confidence: v.confidence))
                    }
                case .variantSpelling:
                    break   // accidentals aren't structural graph nodes
                }
            }
            // Every base position this witness did NOT change shares the base reading → agreement.
            for pos in basePositions where !changed.contains(pos) {
                guard let ni = nodeIndexForBasePos[pos] else { continue }
                let t = baseTokens[pos]
                addReading(&nodeReadings[ni], normalized: t.normalized, surface: t.surface, witness: compared.id)
            }
        }

        let allIDs = Set(witnesses.map { $0.id })
        progress?("finalising the graph (\(nodeReadings.count) spine nodes, "
                  + "\(insertReadings.count) inserted, \(moveRecords.count) move edge(s)) …")

        // Finalise spine nodes (ids 0..<spine.count, in reading order).
        var nodes: [TokenGraphNode] = []
        var spine: [TokenGraphNode.NodeID] = []
        for (i, readings) in nodeReadings.enumerated() {
            let carriers = readings.values.reduce(into: Set<String>()) { $0.formUnion($1.witnesses) }
            let isAgreement = readings.count == 1 && carriers == allIDs
            nodes.append(TokenGraphNode(id: i, readings: readings, isAgreement: isAgreement))
            spine.append(i)
        }

        // Append off-spine inserted nodes (deterministic: sort by anchor, then normalised reading). Each gets a
        // fresh id after the spine ids. They are NOT on the spine (only the base reading order is), so a
        // consumer sees them as inserted branches.
        var insertNodeID = nodes.count
        var insertedAnchorByNodeID: [TokenGraphNode.NodeID: Int] = [:]
        let orderedInserts = insertReadings.keys.sorted { a, b in
            a.anchor != b.anchor ? a.anchor < b.anchor : a.normalized < b.normalized
        }
        for key in orderedInserts {
            let reading = insertReadings[key]!
            let absent = allIDs.subtracting(reading.witnesses)
            var readings: [String: TokenGraphReading] = [key.normalized: reading]
            if !absent.isEmpty { readings["∅"] = TokenGraphReading(surface: "∅", witnesses: absent) }
            nodes.append(TokenGraphNode(id: insertNodeID, readings: readings, isAgreement: false))
            insertedAnchorByNodeID[insertNodeID] = key.anchor
            insertNodeID += 1
        }

        // Edges. Spine (reading-order) edges between consecutive spine nodes carry all witnesses that stay in
        // order there; move edges carry the reordering witness and are flagged `isMove`. Emitted in a fixed
        // order (spine edges by position, then move edges sorted) so the graph is deterministic.
        var edges: [TokenGraphEdge] = []
        if spine.count >= 2 {
            for i in 0..<(spine.count - 1) {
                edges.append(TokenGraphEdge(from: spine[i], to: spine[i + 1], witnesses: allIDs, isMove: false))
            }
        }
        for m in moveRecords.sorted(by: { $0.fromNode != $1.fromNode ? $0.fromNode < $1.fromNode
                                                                      : ($0.toNode != $1.toNode ? $0.toNode < $1.toNode
                                                                                                : $0.witness < $1.witness) }) {
            edges.append(TokenGraphEdge(from: m.fromNode, to: m.toNode, witnesses: [m.witness], isMove: true,
                                        confidence: m.confidence))
        }

        var graph = TokenGraph(nodes: nodes, edges: edges, spine: spine)
        graph.baseComparablePositions = basePositions
        graph.insertedAnchorByNodeID = insertedAnchorByNodeID
        return graph
    }

    // MARK: reading helpers

    /// Add a witness to a node's reading bucket keyed by normalised form (merging carriers, keeping the surface).
    private static func addReading(_ readings: inout [String: TokenGraphReading],
                                   normalized: String, surface: String, witness: String) {
        if let existing = readings[normalized] {
            var w = existing.witnesses; w.insert(witness)
            readings[normalized] = TokenGraphReading(surface: existing.surface, witnesses: w)
        } else {
            readings[normalized] = TokenGraphReading(surface: surface, witnesses: [witness])
        }
    }

    private static func addReading<K: Hashable>(_ map: inout [K: TokenGraphReading], key: K,
                                                surface: String, witness: String) {
        if let existing = map[key] {
            var w = existing.witnesses; w.insert(witness)
            map[key] = TokenGraphReading(surface: existing.surface, witnesses: w)
        } else {
            map[key] = TokenGraphReading(surface: surface, witnesses: [witness])
        }
    }

    /// A whitespace-collapsed key for an inserted reading, so witnesses that insert the same text (modulo
    /// spacing) share one node. Lower-cased to fold trivial surface differences the fold already ignores.
    private static func normalizedReading(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    private static func nearestNodeAtOrBefore(_ basePos: Int, _ map: [Int: Int]) -> Int {
        var p = basePos
        while p >= 0 { if let ni = map[p] { return ni }; p -= 1 }
        return -1
    }

    private static func nearestNodeAtOrAfter(_ basePos: Int, _ map: [Int: Int], count: Int) -> Int {
        var p = basePos
        while map[p] == nil && p < basePos + 4096 { p += 1; if let ni = map[p] { return ni } }
        return map[basePos] ?? count   // count = a virtual "after the end" node id
    }
}

// MARK: - projection to the apparatus-facing VariantGraph

public extension TokenGraph {

    /// Project the token-graph onto `Collation.VariantGraph` so existing renderers (`Apparatus`, `Synopsis`,
    /// `CollationJSON`) consume it unchanged. Spine nodes become base-anchored `GraphNode`s (their
    /// `basePosition` is the base full-token position carried from the build); off-spine inserted nodes become
    /// inserted `GraphNode`s (`basePosition = -1`, `insertedAfter = anchor`), exactly the shape B6c produced —
    /// but now derived from graph structure. Node/reading ordering matches the old fold, so this is a drop-in
    /// replacement for `Collation.variantGraph`'s hand-rolled fold.
    func projectedVariantGraph(baseID: String) -> Collation.VariantGraph? {
        var out: [Collation.GraphNode] = []
        // Spine nodes → base-anchored GraphNodes at their carried base full-token position.
        for (i, nodeID) in spine.enumerated() {
            guard let node = nodes.first(where: { $0.id == nodeID }) else { continue }
            let pos = i < baseComparablePositions.count ? baseComparablePositions[i] : i
            out.append(Collation.GraphNode(basePosition: pos, readings: projectReadings(node.readings)))
        }
        // Off-spine inserted nodes → inserted GraphNodes at their carried insert-after anchor.
        let spineSet = Set(spine)
        for node in nodes where !spineSet.contains(node.id) {
            let anchor = insertedAnchorByNodeID[node.id] ?? -1
            out.append(Collation.GraphNode(basePosition: -1, readings: projectReadings(node.readings),
                                           insertedAfter: anchor))
        }
        // Text order: an inserted node sits immediately after its anchor base position; ties broken as the old
        // fold did (base node first, then inserted nodes by their least non-∅ reading) for byte-stable output.
        let ordered = out.sorted { a, b in
            let ka = a.isInserted ? (a.insertedAfter ?? -1) : a.basePosition
            let kb = b.isInserted ? (b.insertedAfter ?? -1) : b.basePosition
            if ka != kb { return ka < kb }
            if a.isInserted != b.isInserted { return !a.isInserted }
            let ra = a.readings.keys.filter { $0 != "∅" }.min() ?? ""
            let rb = b.readings.keys.filter { $0 != "∅" }.min() ?? ""
            return ra < rb
        }
        return Collation.VariantGraph(baseID: baseID, nodes: ordered, moves: projectedMoves(baseID: baseID))
    }

    /// The moves, read off the move edges. A move edge runs from the spine node BEFORE a moved block to the node
    /// AFTER it (`-1` = before all text; an endpoint that is not a spine node, such as the virtual end, = after all
    /// text), so the moved words are the spine nodes strictly between its endpoints. This holds for both merge
    /// strategies, which record move edges this way. Moves with the same span and confidence merge their witnesses.
    func projectedMoves(baseID: String) -> [Collation.GraphMove] {
        var spineIndex: [TokenGraphNode.NodeID: Int] = [:]
        for (i, id) in spine.enumerated() { spineIndex[id] = i }
        var nodeByID: [TokenGraphNode.NodeID: TokenGraphNode] = [:]
        for node in nodes { nodeByID[node.id] = node }
        struct Key: Hashable { let lo: Int; let hi: Int; let confidence: MoveConfidence }
        var witnessesByKey: [Key: Set<String>] = [:]
        for edge in edges where edge.isMove {
            let lo = edge.from < 0 ? 0 : (spineIndex[edge.from].map { $0 + 1 } ?? 0)
            let hi = spineIndex[edge.to] ?? spine.count
            guard lo < hi else { continue }
            witnessesByKey[Key(lo: lo, hi: hi, confidence: edge.confidence), default: []].formUnion(edge.witnesses)
        }
        return witnessesByKey.map { key, witnesses -> Collation.GraphMove in
            let positions = (key.lo..<key.hi).map { $0 < baseComparablePositions.count ? baseComparablePositions[$0] : $0 }
            let words = (key.lo..<key.hi).compactMap { i -> String? in
                nodeByID[spine[i]]?.readings.values.first { $0.witnesses.contains(baseID) }?.surface
            }
            return Collation.GraphMove(basePositions: positions, lemma: words.joined(separator: " "),
                                       witnesses: witnesses, confidence: key.confidence)
        }
        .sorted { a, b in
            if a.basePositions != b.basePositions { return a.basePositions.lexicographicallyPrecedes(b.basePositions) }
            if a.confidence != b.confidence { return a.confidence == .certain }
            return a.witnesses.sorted().lexicographicallyPrecedes(b.witnesses.sorted())
        }
    }

    /// Turn graph readings (normalised → reading{surface,witnesses}) into the apparatus `surface → sigla`
    /// shape, merging any two normalised buckets that share a surface (they render identically). The `∅`
    /// omission bucket keeps its sign.
    private func projectReadings(_ readings: [String: TokenGraphReading]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for r in readings.values { out[r.surface, default: []].formUnion(r.witnesses) }
        return out
    }
}
