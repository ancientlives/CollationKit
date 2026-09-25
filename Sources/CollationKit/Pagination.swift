import Foundation

// MARK: - Pagination model (source-page vs. printed-page citation)
//
// "Where is this on the page/line?" depends on an editorial convention the tool must be TOLD, not infer.
// The default (`.markers`) numbers by the breaks present in the source — right for born-digital copy, but a
// scholar citing a *printed* witness needs that edition's actual pagination supplied. This type makes the
// convention explicit, covering the three options recorded in DEVELOPMENT_LOG (2026-06-27):
//
//   • .markers          — pages break at source markers (<!-- page break -->, a stand-alone ---, form feed).
//   • .linesPerPage(N)   — synthesize a page boundary every N TEXT lines (a uniform printed page ≈ N lines).
//   • .explicit(offsets) — pages begin at the given UTF-16 source offsets (imported from a real edition).
//
// Orthogonally, `lineNumbering` chooses how lines are numbered within the witness:
//   • .perPage     — line numbers reset to 1 on each page (the common critical-edition layout).
//   • .continuous  — line numbers run 1…N through the whole witness (a "through-numbered" text, e.g. a poem
//                    cited by line 1–1247 regardless of page).

public struct PaginationModel: Equatable {

    public enum Pages: Equatable {
        case markers
        case linesPerPage(Int)
        case explicit([Int])
    }

    public enum LineNumbering: Equatable {
        case perPage
        case continuous
    }

    public var pages: Pages
    public var lineNumbering: LineNumbering

    public init(pages: Pages = .markers, lineNumbering: LineNumbering = .perPage) {
        self.pages = pages
        self.lineNumbering = lineNumbering
    }

    /// The default: pages from source markers, line numbers reset per page. Matches the prior behaviour.
    public static let `default` = PaginationModel()

    /// A uniform printed page of `n` text lines, line numbers reset per page (a typical critical edition).
    public static func printedPage(linesPerPage n: Int) -> PaginationModel {
        PaginationModel(pages: .linesPerPage(n), lineNumbering: .perPage)
    }

    /// A through-numbered witness: one continuous line sequence, no per-page reset (page is always 0).
    public static let throughNumbered = PaginationModel(pages: .linesPerPage(Int.max),
                                                        lineNumbering: .continuous)
}
