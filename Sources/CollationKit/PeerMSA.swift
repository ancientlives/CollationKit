import Foundation

// MARK: - Peer multiple-sequence alignment merge (BACKLOG B14 — the `.peerMSA` strategy)
//
// The base-anchored lift (`TokenGraph.build`) assembles the N-witness graph from N−1 pairwise alignments
// against a fixed base: every witness is seen *through* the copy-text. This file implements the peer merge
// (`PAPER_NOTES §5.3` steps 1–5): each witness is aligned against the *whole growing graph* — concretely, the
// tractable first version aligns against the graph's **linear consensus spine** (the majority reading at each
// slot), reusing the existing anchor + NW machinery (`Transposition.align`) rather than rewriting alignment.
//
// What this buys over the lift (the B14 acceptance set):
//   • **Non-base-shared variance.** Text the base lacks becomes part of the alignable structure: when witness
//     B inserts "the red rose" and witness C inserts "a red rose", C aligns against a consensus that already
//     contains B's insertion — so "red rose" is ONE shared reading and only "the|a" diverges. The lift keyed
//     each insertion by its whole text and produced two unrelated nodes.
//   • **Recurring-word moves become `certain` from structure.** The merge-level displaced-run recovery pairs a
//     deleted and an inserted occurrence that are unique among the *unmatched* occurrences; every other
//     occurrence of the word is matched in place in the merged graph, and swapping pins between identical
//     tokens is a no-op, so the displacement is structurally forced — `certain`, where the pairwise post-pass
//     could only say `likely` (it lacked the merged structure to rule the other occurrences out).
//   • **Base-privilege confined to rendering.** The apparatus is still *keyed* to `witnesses[0]` (the output
//     shape needs a copy-text lemma), but no *alignment decision* privileges it: after seeding, the base is
//     just the first contributor to a consensus every later witness aligns against.
//
// Determinism (§9): non-base witnesses are merged in **sorted-id order**, not input order, so the graph — and
// its projected JSON — is byte-stable when the caller reorders them (a property test pins this). All ties are
// broken lexicographically; nothing iterates a dictionary unordered.
//
// Page-awareness: each slot carries a representative page (recorded at creation), so the page-aware
// transposition tie-break (§4.3) flows through `Transposition.align` unchanged — a guarded test keeps the
// page-crossing attribution the rewrite was most at risk of losing.

extension TokenGraph {

    /// Max distance (in consensus tokens) between a lone omission and an insertion of the same key for the
    /// pair to count as a DISPLACEMENT (a move) rather than a coincidence of unrelated edits. Clause-scale:
    /// the motivating single-word moves travel a few tokens; unrelated re-uses of a common word travel far.
    static let displacedWindow = 12

    /// One position in the growing merged spine. `readings` keeps each witness's OWN normalised form and
    /// surface (so a B10 lexicon match shows per-witness renderings); `baseFullPos` is the base witness's
    /// full-token index when the base carries this slot (nil for text the base lacks); `createdKey` is the
    /// reading the slot was created with (the incumbent).
    private struct Slot {
        let uid: Int
        var readings: [String: TokenGraphReading]
        let page: Int
        let baseFullPos: Int?
        let createdKey: String

        /// The consensus key for aligning the next witness: the majority non-∅ reading. A TIE keeps the
        /// INCUMBENT (the slot's creation reading) when it is among the leaders, else the smallest key —
        /// flipping the consensus to a variant reading on a 1–1 tie would break anchors for every later
        /// witness (an arbitrary lexicographic flip measurably scattered alignments in `collate-bench`).
        var consensusKey: String {
            let nonNull = readings.filter { $0.key != "∅" }
            guard let top = nonNull.values.map({ $0.witnesses.count }).max() else { return "∅" }
            let leaders = nonNull.filter { $0.value.witnesses.count == top }.keys
            if leaders.contains(createdKey) { return createdKey }
            return leaders.min() ?? "∅"
        }
    }

    /// Build the token-graph by **peer MSA** (B14): seed the spine from `witnesses[0]` (the render base),
    /// then progressively align every further witness — in sorted-id order — against the current consensus
    /// spine and merge the result. Returns the same `TokenGraph` shape as the lift, so
    /// `projectedVariantGraph` (and everything above it) is reused unchanged.
    static func buildPeerMSA(witnesses: [Witness],
                             normalizer: Normalizer = .substantive,
                             pagination: PaginationModel = .default,
                             anchorLength: Int = 3,
                             scores: AlignmentScores = .prose,
                             lexicon: TranslationLexicon? = nil,
                             progress: ((String) -> Void)? = nil) -> TokenGraph? {
        guard let base = witnesses.first else { return nil }
        let allIDs = Set(witnesses.map { $0.id })
        // Key the lexicon exactly as the tokens are keyed (review B7).
        let lexicon = lexicon?.normalized(with: normalizer)

        // ---- seed the spine from the base ----
        var nextUid = 0
        var slotsByUid: [Int: Slot] = [:]
        var spineOrder: [Int] = []          // uids in merged reading order (splices preserve uids)
        let baseTokens = Tokenizer.tokenize(base.text, with: normalizer, pagination: pagination)
        for (i, t) in baseTokens.enumerated() where t.isComparable {
            slotsByUid[nextUid] = Slot(uid: nextUid,
                                       readings: [t.normalized: TokenGraphReading(surface: t.surface,
                                                                                  witnesses: [base.id])],
                                       page: t.page, baseFullPos: i, createdKey: t.normalized)
            spineOrder.append(nextUid)
            nextUid += 1
        }

        // Moves recorded with stable uids (slot indices shift as later witnesses splice insertions).
        // `fromUid`/`toUid` nil = before-all / after-all.
        struct MoveRecord { let witness: String; let fromUid: Int?; let toUid: Int?
                            let confidence: MoveConfidence }
        var moveRecords: [MoveRecord] = []

        // ---- merge each further witness against the consensus (sorted-id order for reorder-stability) ----
        let sortedRest = witnesses.dropFirst().sorted(by: { $0.id < $1.id })
        for (offset, witness) in sortedRest.enumerated() {
            progress?("aligning witness \(offset + 1)/\(sortedRest.count) against the consensus spine: "
                      + "\(witness.id) (\(spineOrder.count) slots so far)")
            let wTokens = Tokenizer.tokenize(witness.text, with: normalizer, pagination: pagination)
            let (wKeys, wMap, wPages) = Collation.comparable(wTokens, lexicon: lexicon)

            // The consensus the witness aligns against: majority reading per slot, pivoted by the lexicon so
            // translation-equivalent forms compare equal (B10 attaches here — step 1's alignment seeding).
            let cKeys = spineOrder.map { uid -> String in
                let key = slotsByUid[uid]!.consensusKey
                return lexicon?.pivot(key) ?? key
            }
            let cPages = spineOrder.map { slotsByUid[$0]!.page }

            let aligned = Transposition.align(cKeys, wKeys, anchorLength: anchorLength, scores: scores,
                                              aPages: cPages, bPages: wPages)

            // Pass 1 — walk the in-order regions, collecting per-slot ops and insertion records. Regions are
            // emitted in consensus order with ordered ops, so `lastConsensusIdx` tracks the slot each
            // insertion follows (-1 = before all).
            enum SlotOp { case reads(bTok: Int)      // witness carries this slot (match or substitute)
                          case omits }               // witness lacks this slot
            var slotOps: [Int: SlotOp] = [:]         // consensus index → op
            var inserts: [(afterIdx: Int, bTok: Int)] = []
            var lastConsensusIdx = -1
            for segment in aligned.segments {
                guard case .region(let ops) = segment else { continue }
                for op in ops {
                    switch op {
                    case .match(let a, let b), .substitute(let a, let b):
                        slotOps[a] = .reads(bTok: b); lastConsensusIdx = a
                    case .delete(let a):
                        slotOps[a] = .omits; lastConsensusIdx = a
                    case .insert(let b):
                        inserts.append((afterIdx: lastConsensusIdx, bTok: b))
                    }
                }
            }

            // Pass 2 — merge-level displaced-run recovery (§4.5 lifted to the graph): a deleted slot and an
            // inserted token with the same key, each UNIQUE among this witness's unmatched occurrences, are a
            // displacement — the witness carries the slot (reordered), not an omission + an addition. Every
            // other occurrence of the key is matched in place in the merged structure, and re-pinning between
            // identical tokens changes nothing, so the pairing is structurally forced → `certain` (this is
            // where the lift's `likely` recurring-word moves upgrade; PAPER_NOTES §5.3 step 4).
            //
            // LOCALITY BOUND (`displacedWindow`): a genuine lone-word move is clause-local (the motivating
            // `the well-known author` case moves ~3 tokens). Without a bound, a common function word inside a
            // genuinely NEW inserted passage pairs with any distant unrelated omission of the same word — a
            // false long-range "move" that also punches a hole in the inserted run's reading (surfaced by the
            // Verne corpus: ward's added sentence lost its "from"). The del and the insertion anchor must sit
            // within the window for the pairing to be a displacement rather than a coincidence.
            var delByKey: [String: [Int]] = [:]      // key → consensus indices this witness omitted
            for (a, op) in slotOps { if case .omits = op { delByKey[cKeys[a], default: []].append(a) } }
            var insByKey: [String: [Int]] = [:]      // key → indices into `inserts`
            for (i, rec) in inserts.enumerated() { insByKey[wKeys[rec.bTok], default: []].append(i) }

            var recoveredIns = Set<Int>()            // indices into `inserts` consumed by recovery
            struct Displaced { let a: Int; let bTok: Int }
            var displaced: [Displaced] = []
            for key in delByKey.keys.sorted() {
                guard let dels = delByKey[key], dels.count == 1,
                      let inss = insByKey[key], inss.count == 1,
                      abs(inserts[inss[0]].afterIdx - dels[0]) <= displacedWindow else { continue }
                displaced.append(Displaced(a: dels[0], bTok: inserts[inss[0]].bTok))
                recoveredIns.insert(inss[0])
            }
            // Coalesce contiguous displaced words (consecutive in BOTH sequences) into single move blocks.
            displaced.sort { $0.a < $1.a }
            var displacedRuns: [(aLo: Int, aHi: Int)] = []
            var bTokForSlot: [Int: Int] = [:]
            for d in displaced {
                bTokForSlot[d.a] = d.bTok
                if let last = displacedRuns.last, d.a == last.aHi + 1,
                   let prevB = bTokForSlot[last.aHi], d.bTok == prevB + 1 {
                    displacedRuns[displacedRuns.count - 1].aHi = d.a
                } else {
                    displacedRuns.append((aLo: d.a, aHi: d.a))
                }
            }
            for run in displacedRuns {
                moveRecords.append(MoveRecord(
                    witness: witness.id,
                    fromUid: run.aLo > 0 ? spineOrder[run.aLo - 1] : nil,
                    toUid: run.aHi + 1 < spineOrder.count ? spineOrder[run.aHi + 1] : nil,
                    confidence: .certain))
            }

            // Pass 3 — anchor-pass transpositions: the witness carries those slots, reordered. Apply the
            // block's inner alignment (edits inside the move) to the slots; record the move edge. Anchor-pass
            // moves rest on unique shared n-grams, so they are `certain` by construction. Insertions INSIDE a
            // moved block are within-move edits (pairwise-report material, as in the lift) — not graph slots.
            for segment in aligned.segments {
                guard case .transposition(let aRange, _, let innerOps) = segment else { continue }
                for op in innerOps {
                    switch op {
                    case .match(let a, let b), .substitute(let a, let b): slotOps[a] = .reads(bTok: b)
                    case .delete(let a):                                  slotOps[a] = .omits
                    case .insert:                                         break
                    }
                }
                moveRecords.append(MoveRecord(
                    witness: witness.id,
                    fromUid: aRange.lowerBound > 0 ? spineOrder[aRange.lowerBound - 1] : nil,
                    toUid: aRange.upperBound < spineOrder.count ? spineOrder[aRange.upperBound] : nil,
                    confidence: .certain))
            }

            // Pass 4 — apply the readings. The witness contributes its OWN token form at each slot it
            // carries (under a lexicon, a match may add a different normalised form — the per-witness
            // rendering a synoptic translation view needs); an omitted slot reads ∅; a displaced slot reads
            // the paired token.
            for (a, op) in slotOps {
                let uid = spineOrder[a]
                switch op {
                case .reads(let bTok):
                    let t = wTokens[wMap[bTok]]
                    addPeerReading(&slotsByUid[uid]!.readings, normalized: t.normalized,
                                   surface: t.surface, witness: witness.id)
                case .omits:
                    if let bTok = bTokForSlot[a] {          // displaced, not omitted: carries the paired token
                        let t = wTokens[wMap[bTok]]
                        addPeerReading(&slotsByUid[uid]!.readings, normalized: t.normalized,
                                       surface: t.surface, witness: witness.id)
                    } else {
                        addPeerReading(&slotsByUid[uid]!.readings, normalized: "∅",
                                       surface: "∅", witness: witness.id)
                    }
                }
            }

            // Pass 5 — splice the (unrecovered) insertions into the spine as new slots, so LATER witnesses
            // align against them (the peer-MSA step that closes the non-base-shared-variance gap). Grouped by
            // anchor, spliced in descending anchor order so earlier indices stay valid.
            var insertsByAnchor: [Int: [Int]] = [:]           // afterIdx → bToks in order
            for (i, rec) in inserts.enumerated() where !recoveredIns.contains(i) {
                insertsByAnchor[rec.afterIdx, default: []].append(rec.bTok)
            }
            for afterIdx in insertsByAnchor.keys.sorted(by: >) {
                var newUids: [Int] = []
                for bTok in insertsByAnchor[afterIdx]! {
                    let t = wTokens[wMap[bTok]]
                    slotsByUid[nextUid] = Slot(uid: nextUid,
                                               readings: [t.normalized: TokenGraphReading(surface: t.surface,
                                                                                          witnesses: [witness.id])],
                                               page: t.page, baseFullPos: nil, createdKey: t.normalized)
                    newUids.append(nextUid)
                    nextUid += 1
                }
                spineOrder.insert(contentsOf: newUids, at: afterIdx + 1)
            }
        }

        // ---- finalise ----
        // ∅ for every witness absent from a slot (witnesses merged before the slot existed, and the base at
        // slots it doesn't carry).
        for uid in spineOrder {
            let carriers = slotsByUid[uid]!.readings.values.reduce(into: Set<String>()) { $0.formUnion($1.witnesses) }
            let absent = allIDs.subtracting(carriers)
            if !absent.isEmpty {
                addPeerReading(&slotsByUid[uid]!.readings, normalized: "∅", surface: "∅", witnesses: absent)
            }
        }

        // Coalesce ADJACENT inserted slots whose reading partitions are identical (same witness-sets per
        // bucket) into run-granular nodes — "i sing the body" reads as one apparatus row, exactly the B6c
        // shape — while a partially-shared insertion splits precisely where the carrier sets diverge.
        var mergedOrder: [Int] = []
        for uid in spineOrder {
            let slot = slotsByUid[uid]!
            if slot.baseFullPos == nil, let lastUid = mergedOrder.last,
               let last = slotsByUid[lastUid], last.baseFullPos == nil,
               let joined = coalesce(last, slot) {
                slotsByUid[lastUid] = joined
                slotsByUid[uid] = nil
            } else {
                mergedOrder.append(uid)
            }
        }

        // Node ids: base-carried slots first (spine, in order), then inserted slots (in merged reading
        // order) — mirroring the lift's id layout so consumers see one shape.
        let spineUids = mergedOrder.filter { slotsByUid[$0]!.baseFullPos != nil }
        let insertedUids = mergedOrder.filter { slotsByUid[$0]!.baseFullPos == nil }
        var nodeIDForUid: [Int: Int] = [:]
        for (i, uid) in (spineUids + insertedUids).enumerated() { nodeIDForUid[uid] = i }

        var nodes: [TokenGraphNode] = []
        for uid in spineUids + insertedUids {
            let slot = slotsByUid[uid]!
            let isAgreement = slot.readings.count == 1
                && slot.readings.values.first!.witnesses == allIDs
            nodes.append(TokenGraphNode(id: nodeIDForUid[uid]!, readings: slot.readings,
                                        isAgreement: isAgreement))
        }

        // Inserted-node anchors: the base full-token position of the nearest PRECEDING base-carried slot in
        // the merged reading order (-1 = before all base text) — the same insert-after semantics as the lift.
        var insertedAnchorByNodeID: [TokenGraphNode.NodeID: Int] = [:]
        var lastBaseFullPos = -1
        for uid in mergedOrder {
            let slot = slotsByUid[uid]!
            if let basePos = slot.baseFullPos { lastBaseFullPos = basePos }
            else { insertedAnchorByNodeID[nodeIDForUid[uid]!] = lastBaseFullPos }
        }

        // Edges: consecutive spine edges, then move edges (uids → final node ids; nil → -1 / end).
        let spineIDs = spineUids.map { nodeIDForUid[$0]! }
        var edges: [TokenGraphEdge] = []
        if spineIDs.count >= 2 {
            for i in 0..<(spineIDs.count - 1) {
                edges.append(TokenGraphEdge(from: spineIDs[i], to: spineIDs[i + 1],
                                            witnesses: allIDs, isMove: false))
            }
        }
        struct ResolvedMove { let from: Int; let to: Int; let witness: String; let confidence: MoveConfidence }
        let resolved = moveRecords.map { m -> ResolvedMove in
            // A recorded endpoint uid may have been coalesced away; fall back sensibly.
            let from = m.fromUid.flatMap { nodeIDForUid[$0] } ?? -1
            let to = m.toUid.flatMap { nodeIDForUid[$0] } ?? nodes.count
            return ResolvedMove(from: from, to: to, witness: m.witness, confidence: m.confidence)
        }
        for m in resolved.sorted(by: { $0.from != $1.from ? $0.from < $1.from
                                                          : ($0.to != $1.to ? $0.to < $1.to
                                                                            : $0.witness < $1.witness) }) {
            edges.append(TokenGraphEdge(from: m.from, to: m.to, witnesses: [m.witness], isMove: true,
                                        confidence: m.confidence))
        }

        var graph = TokenGraph(nodes: nodes, edges: edges, spine: spineIDs)
        graph.baseComparablePositions = spineUids.map { slotsByUid[$0]!.baseFullPos! }
        graph.insertedAnchorByNodeID = insertedAnchorByNodeID
        return graph
    }

    // MARK: helpers

    private static func addPeerReading(_ readings: inout [String: TokenGraphReading],
                                       normalized: String, surface: String, witness: String) {
        addPeerReading(&readings, normalized: normalized, surface: surface, witnesses: [witness])
    }

    private static func addPeerReading(_ readings: inout [String: TokenGraphReading],
                                       normalized: String, surface: String, witnesses: Set<String>) {
        if let existing = readings[normalized] {
            readings[normalized] = TokenGraphReading(surface: existing.surface,
                                                     witnesses: existing.witnesses.union(witnesses))
        } else {
            readings[normalized] = TokenGraphReading(surface: surface, witnesses: witnesses)
        }
    }

    /// Join two adjacent inserted slots when their reading partitions match bucket-for-bucket (identical
    /// witness sets), concatenating keys and surfaces per bucket. Returns nil when the partitions differ —
    /// the run splits there, which is exactly where a partially-shared insertion diverges.
    private static func coalesce(_ a: Slot, _ b: Slot) -> Slot? {
        guard a.readings.count == b.readings.count else { return nil }
        // Pair buckets by witness-set equality; every bucket in `a` must match exactly one in `b`.
        var joined: [String: TokenGraphReading] = [:]
        for (aKey, aReading) in a.readings {
            guard let (bKey, bReading) = b.readings.first(where: { $0.value.witnesses == aReading.witnesses })
            else { return nil }
            if aKey == "∅" && bKey == "∅" {
                joined["∅"] = TokenGraphReading(surface: "∅", witnesses: aReading.witnesses)
            } else if aKey != "∅" && bKey != "∅" {
                joined[aKey + " " + bKey] = TokenGraphReading(surface: aReading.surface + " " + bReading.surface,
                                                              witnesses: aReading.witnesses)
            } else {
                return nil   // a carrier set that has text on one side and ∅ on the other cannot join
            }
        }
        guard joined.count == a.readings.count else { return nil }   // key collision → don't coalesce
        // Coalescing happens at finalisation, after all merges — the joined slot's consensus is never
        // consulted again, so carrying `a`'s creation key is only for completeness.
        return Slot(uid: a.uid, readings: joined, page: a.page, baseFullPos: nil, createdKey: a.createdKey)
    }
}
