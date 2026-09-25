import Foundation

// MARK: - Narrative summary of a collation (a prose "what happened" account)
//
// The apparatus is keyed to a lemma and the located report to a position; both are exhaustive lists. This layer
// answers a different, higher-level question a reader actually asks first: *in plain words, how — and how much —
// does this witness differ from the base, where do the changes fall, and can I trust the comparison?* It turns the
// same `CollationResult` into a short prose story: the overall extent, the dominant kind of change, where changes
// cluster, the moves, and an alignment-quality verdict (the same drift/monotonicity the viewer's alignment map
// visualises). It is the textual counterpart of the interactive dashboard — usable in the console/exports, and a
// quotable characterisation of a result.
//
// Pure model → text, deterministic, host-agnostic (like `Report`/`Apparatus`). Needs the witness *lengths* to
// judge "how much of the text" and to compute the co-linearity (alignment-quality) metric, so it takes the two
// witness texts alongside the pairwise result.

public enum CollationNarrative {

    /// A plain-prose account of how the compared witness differs from the base. `base`/`compared` are the two
    /// witness texts (needed for proportions and the alignment metric); `labels` override the ids in the prose.
    public static func summary(_ result: CollationResult, base: String, compared: String,
                               labels: (base: String, compared: String)? = nil) -> String {
        let baseLabel = labels?.base ?? result.base
        let compLabel = labels?.compared ?? result.compared
        let baseLen = (base as NSString).length
        let compLen = (compared as NSString).length

        let vars = result.variations
        if vars.isEmpty {
            return "\(compLabel) is textually identical to \(baseLabel) under the current collation settings — "
                 + "no substantive variants were found."
        }

        // Counts by type.
        var count: [VariationType: Int] = [:]
        for v in vars { count[v.type, default: 0] += 1 }
        let subs = count[.substitution] ?? 0, ins = count[.insertion] ?? 0
        let dels = count[.deletion] ?? 0, moves = count[.transposition] ?? 0
        let spell = count[.variantSpelling] ?? 0
        let total = vars.count

        // How much of the BASE text is touched (chars covered by a base-side reading; insertions have no base
        // span, so they don't count toward "of the base").
        var changedChars = 0
        for v in vars where v.type != .insertion {
            if let r = v.baseLocation?.charRange { changedChars += max(0, r.upperBound - r.lowerBound) }
        }
        let pct = baseLen > 0 ? Double(changedChars) / Double(baseLen) * 100.0 : 0

        // Dominant kind.
        let ranked: [(VariationType, Int)] = [(.substitution, subs), (.deletion, dels),
                                              (.insertion, ins), (.transposition, moves)]
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let dominant = ranked.first

        // Where changes cluster — split the base into three parts and see where the change-covered chars land.
        let thirds = clusterThirds(vars, baseLen: baseLen)

        // Alignment quality (co-linearity): from the base↔comp char-offset pairs, the max deviation from the
        // ideal diagonal (as a % of length) and the monotonicity (% advancing in step). A sound alignment keeps
        // both near-ideal — the same numbers the viewer's alignment map reports.
        let quality = alignmentQuality(vars, baseLen: baseLen, compLen: compLen)

        var out: [String] = []

        // 1) Headline extent.
        out.append("\(compLabel) differs from \(baseLabel) at "
                   + "\(fmt(total)) point\(total == 1 ? "" : "s")"
                   + (pct >= 0.05 ? ", touching about \(pctStr(pct)) of the base text." : "."))

        // 2) The make-up of the changes.
        var parts: [String] = []
        if subs > 0 { parts.append("\(fmt(subs)) substitution\(subs == 1 ? "" : "s") (\(share(subs, total)))") }
        if dels > 0 { parts.append("\(fmt(dels)) deletion\(dels == 1 ? "" : "s")") }
        if ins > 0 { parts.append("\(fmt(ins)) insertion\(ins == 1 ? "" : "s")") }
        if moves > 0 { parts.append("\(fmt(moves)) moved passage\(moves == 1 ? "" : "s")") }
        if !parts.isEmpty {
            let dom = dominant.map { "The dominant kind is \(plainType($0.0)) (\(share($0.1, total))). " } ?? ""
            out.append(dom + "In all: " + joinList(parts) + ".")
        }

        // 3) Where they fall.
        if let where_ = thirds { out.append(where_) }

        // 4) Moves + confidence framing.
        if moves > 0 {
            let likely = vars.filter { $0.type == .transposition && $0.confidence == .likely }.count
            let crossPage = vars.filter { $0.type == .transposition && $0.crossesPage }.count
            var m = "\(fmt(moves)) passage\(moves == 1 ? " was" : "s were") relocated"
            if crossPage > 0 { m += " (\(fmt(crossPage)) across a page boundary)" }
            if likely > 0 { m += "; \(fmt(likely)) of these are reported as *possible* moves (a heuristic pairing), the rest as certain" }
            out.append(m + ".")
        }

        // 5) Accidentals note (reassurance about what was checked).
        if spell == 0 {
            out.append("Spelling and other accidental differences were checked and none were recorded — this is a "
                       + "substantive collation.")
        } else {
            out.append("\(fmt(spell)) accidental (spelling/case) difference\(spell == 1 ? " was" : "s were") also recorded.")
        }

        // 6) Trust — the alignment verdict.
        if let q = quality {
            if q.good {
                out.append("The alignment is sound: the two texts track each other throughout (the shared points "
                           + "stay within \(pctStr(q.maxDriftPct)) of the ideal diagonal and \(pctStr(q.monoPct)) "
                           + "advance in step), so the comparison holds end to end"
                           + (compLen != baseLen ? " — the difference in overall length simply reflects that the "
                              + "two texts are not the same length, not a mis-alignment." : "."))
            } else {
                out.append("The alignment is worth checking: some shared points sit off the ideal diagonal "
                           + "(up to \(pctStr(q.maxDriftPct)); \(pctStr(q.monoPct)) monotonic) — inspect the "
                           + "alignment map for any outliers.")
            }
        }

        return out.joined(separator: " ")
    }

    // MARK: helpers

    /// Which third(s) of the base text the change-covered characters concentrate in.
    private static func clusterThirds(_ vars: [Variation], baseLen: Int) -> String? {
        guard baseLen > 0 else { return nil }
        var bucket = [0, 0, 0]
        for v in vars where v.type != .insertion {
            if let r = v.baseLocation?.charRange {
                let mid = (r.lowerBound + r.upperBound) / 2
                let t = min(2, max(0, mid * 3 / baseLen))
                bucket[t] += max(1, r.upperBound - r.lowerBound)
            }
        }
        let tot = bucket.reduce(0, +)
        guard tot > 0 else { return nil }
        let names = ["the opening third", "the middle third", "the final third"]
        // Even spread?
        let even = bucket.allSatisfy { Double($0) / Double(tot) > 0.25 && Double($0) / Double(tot) < 0.42 }
        if even { return "The changes are spread fairly evenly across the whole work." }
        // Name the heaviest region(s).
        let ranked = bucket.enumerated().sorted { $0.element > $1.element }
        let top = ranked[0]
        let topShare = Double(top.element) / Double(tot)
        if topShare > 0.5 {
            return "The changes concentrate in \(names[top.offset]) of the work (\(pctStr(topShare * 100)) of them)."
        }
        return "The changes fall mostly in \(names[ranked[0].offset]) and \(names[ranked[1].offset]) of the work."
    }

    struct Quality { let maxDriftPct: Double; let monoPct: Double; let good: Bool }

    /// Co-linearity of the base↔comp correspondence points — the alignment-quality metric the viewer's map shows.
    private static func alignmentQuality(_ vars: [Variation], baseLen: Int, compLen: Int) -> Quality? {
        guard baseLen > 0, compLen > 0 else { return nil }
        var pts: [(b: Int, c: Int)] = []
        for v in vars {
            if let b = v.baseLocation?.charRange.lowerBound, let c = v.comparedLocation?.charRange.lowerBound {
                pts.append((b, c))
            }
        }
        guard pts.count > 1 else { return nil }
        pts.sort { $0.b < $1.b }
        var maxDev = 0.0, mono = 0
        for (i, p) in pts.enumerated() {
            let expC = Double(p.b) / Double(baseLen) * Double(compLen)
            let dev = abs(Double(p.c) - expC) / Double(compLen)
            if dev > maxDev { maxDev = dev }
            if i > 0 && p.c >= pts[i - 1].c { mono += 1 }
        }
        let monoPct = Double(mono) / Double(pts.count - 1) * 100.0
        let driftPct = maxDev * 100.0
        return Quality(maxDriftPct: driftPct, monoPct: monoPct, good: driftPct <= 8 && monoPct >= 98)
    }

    private static func plainType(_ t: VariationType) -> String {
        switch t {
        case .substitution: return "substitution"
        case .insertion: return "insertion"
        case .deletion: return "deletion"
        case .transposition: return "transposition (a moved passage)"
        case .variantSpelling: return "accidental (spelling/case)"
        }
    }

    private static func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
    private static func share(_ n: Int, _ total: Int) -> String {
        total > 0 ? "\(Int((Double(n) / Double(total) * 100).rounded()))%" : "0%"
    }
    private static func pctStr(_ p: Double) -> String {
        let r = (p * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(r)) + "%"
    }
    private static func joinList(_ parts: [String]) -> String {
        if parts.count == 1 { return parts[0] }
        if parts.count == 2 { return parts[0] + " and " + parts[1] }
        return parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
    }
}
