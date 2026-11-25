import XCTest
@testable import CollateCLI

// MARK: - Version consistency (release 1 review, blocker B10)
//
// The version lived in two places that had drifted apart: `collate --version` said 0.2.0 while `CITATION.cff` said
// 0.1.0. This test keeps them in step, and checks the CHANGELOG has an entry for the current version.

final class VersionConsistencyTests: XCTestCase {

    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testTheCLIAndCitationAgreeOnTheVersion() throws {
        let cff = try String(contentsOf: root.appendingPathComponent("CITATION.cff"), encoding: .utf8)
        let line = try XCTUnwrap(cff.split(whereSeparator: \.isNewline).first { $0.hasPrefix("version:") })
        let cited = line.dropFirst("version:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        XCTAssertEqual(CollateCLI.version, cited, "update CITATION.cff and CollateCLI.version together")
    }

    func testTheChangelogHasAnEntryForTheVersion() throws {
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        XCTAssertTrue(changelog.contains("## [\(CollateCLI.version)]"), "add a CHANGELOG entry for \(CollateCLI.version)")
    }
}
