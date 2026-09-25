import Foundation

// MARK: - Located variant report (model, prototyped pure)
//
// Answers "WHERE in the text was each change identified?" — the user-facing locating layer. Each variation
// is rendered with its page / line / word citation (and the underlying char range is available for visual
// highlighting in a host app). This is the textual counterpart to the apparatus: where the apparatus is keyed
// to a lemma, the report is keyed to *location*, which is what a reader scanning a document wants.
//
// Pure model → text, so it is testable and host-agnostic; a host app's view can map the same data to a list with
// "jump to" navigation and inline highlight via `TextLocation.charRange`.

public enum Report {

    /// A human-readable, located list of the variants in a pairwise collation. Each line names the change
    /// type, the readings, and where it sits in each witness ("base p.1·line 2·word 9 → compared p.0·…").
    public static func located(_ result: CollationResult, witnessLabels: (base: String, compared: String)? = nil) -> String {
        let baseLabel = witnessLabels?.base ?? result.base
        let compLabel = witnessLabels?.compared ?? result.compared
        if result.variations.isEmpty {
            return "\(baseLabel) vs \(compLabel): no variants."
        }
        var lines = ["\(baseLabel) vs \(compLabel): \(result.variations.count) variant(s)"]
        for (i, v) in result.variations.enumerated() {
            let tags = (v.crossesPage ? "  (ACROSS PAGES)" : "")
                     + (v.withinTransposition ? "  (within a moved passage)" : "")
                     + (v.type == .transposition && v.confidence == .likely ? "  (POSSIBLE move)" : "")
            lines.append("  [\(i + 1)] \(label(v.type))\(tags)")
            lines.append("      \(baseLabel): \(reading(v.baseReading)) @ \(loc(v.baseLocation))")
            lines.append("      \(compLabel): \(reading(v.comparedReading)) @ \(loc(v.comparedLocation))")
        }
        return lines.joined(separator: "\n")
    }

    private static func label(_ t: VariationType) -> String {
        switch t {
        case .insertion: return "INSERTION"
        case .deletion: return "DELETION"
        case .substitution: return "SUBSTITUTION"
        case .transposition: return "TRANSPOSITION (moved)"
        case .variantSpelling: return "ACCIDENTAL (spelling/case)"
        }
    }

    private static func reading(_ s: String) -> String { s.isEmpty ? "∅ (omitted)" : "“\(s)”" }
    private static func loc(_ l: TextLocation?) -> String { l?.human ?? "—" }
}
