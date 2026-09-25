import XCTest
@testable import CollationKit

// MARK: - Documented-test-count guard (doc-hygiene)
//
// The running test count is quoted in prose in places that must not silently rot:
//   • README.md                          (the `swift test  # N tests` comment and the `Tests/` layout line)
//   • docs/development/TESTING.md        (the test and suite counts)
//   • docs/development/DEVELOPMENT_LOG.md (the latest `State:` line)
// and docs/INDEX.md's maintenance convention explicitly lists these as things to update together.
//
// Nothing enforced that today, so adding or removing a test could leave the docs stating a stale number. This
// meta-test counts the tests SwiftPM actually discovers (via XCTest's own reflection) and asserts it equals
// the number the docs advertise. If you add/remove a test, this fails with a message telling you the new count
// and exactly which docs to update — turning "remember to edit the README" into a build-enforced invariant.
//
// It counts EVERY discovered test method, including this guard itself, so the advertised number is exactly
// what `swift test` reports to a user — no off-by-one to reason about.

final class TestCountGuardTests: XCTestCase {

    /// The count the docs advertise — and exactly what `swift test` prints. When this test fails, update BOTH
    /// this constant AND the prose:
    ///   - README.md  (the `swift test  # N tests` comment and the `Tests/` layout line)
    ///   - docs/development/TESTING.md  (the test and suite counts)
    ///   - docs/development/DEVELOPMENT_LOG.md  (the latest `State:` line)
    /// The suite count ("across M suites") is the number of `XCTestCase` subclasses.
    private static let documentedTestCount = 222

    func testDocumentedTestCountMatchesReality() {
        // XCTest builds a tree of suites; leaves are the individual `test…` methods. Count the leaves across
        // the whole default suite (this guard included, so the number equals `swift test`'s own report).
        let discovered = Self.countTests(in: XCTestSuite.default)

        XCTAssertEqual(discovered, Self.documentedTestCount, """
            Test count drift: the suite now has \(discovered) tests but the docs advertise \
            \(Self.documentedTestCount). Update `documentedTestCount` here AND the prose: the \
            `swift test  # N tests` comment in README.md, docs/development/TESTING.md, and the latest \
            `State:` line in docs/development/DEVELOPMENT_LOG.md — docs/INDEX.md's maintenance convention \
            requires these to stay in step.
            """)
    }

    /// Recursively count leaf test methods in an XCTest suite tree.
    private static func countTests(in test: XCTest) -> Int {
        guard let suite = test as? XCTestSuite else { return 1 }   // a leaf test case invocation
        return suite.tests.reduce(0) { $0 + countTests(in: $1) }
    }
}
