import XCTest
@testable import CollationKit

// MARK: - Conformance corpus (BACKLOG B1) + JSON Schema check (BACKLOG B2)
//
// A language-neutral corpus under `docs/conformance/` pins the engine's `--json` output. Each case is a
// directory of plain witness files plus a `meta.json` describing how to collate them; the committed golden
// is the expected `{ graph, pairs }` interchange. A PORT "passes" when it reproduces every golden
// byte-for-byte (subject to the determinism rules in reference/ALGORITHMS.md §9). These tests both LOCK the
// goldens for the Swift reference and, with COLLATION_RECORD=1, regenerate them after an intentional
// behaviour change.
//
//   swift test --filter Conformance                         # verify against committed goldens
//   COLLATION_RECORD=1 swift test --filter Conformance      # regenerate goldens from the engine
//
// The goldens are produced by the SAME code path as the CLI (`CollationJSON.outputString`), so they are the
// real artifact a consumer receives, not a test-only re-encoding.

final class ConformanceTests: XCTestCase {

    // MARK: corpus location & case loading

    /// The `docs/conformance/` root, resolved from this source file's path (no SwiftPM resource bundle — the
    /// package is intentionally dependency- and resource-free). Tests/CollationKitTests/ → repo root → docs.
    private static let corpusRoot: URL = {
        URL(fileURLWithPath: #filePath)            // …/Tests/CollationKitTests/ConformanceTests.swift
            .deletingLastPathComponent()           // …/Tests/CollationKitTests
            .deletingLastPathComponent()           // …/Tests
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("docs/conformance")
    }()

    private static let casesDir = corpusRoot.appendingPathComponent("cases")
    private static let goldenDir = corpusRoot.appendingPathComponent("golden")
    private static let schemaURL = corpusRoot.appendingPathComponent("collation.schema.json")

    private static let recording = ProcessInfo.processInfo.environment["COLLATION_RECORD"] == "1"

    /// One corpus case: the metadata plus the resolved witness set and collation options.
    private struct Case {
        let id: String                 // directory name, e.g. "01-substitution"
        let meta: Meta
        let witnesses: [Witness]
        let normalizer: Normalizer
        let pagination: PaginationModel
        var goldenURL: URL { ConformanceTests.goldenDir.appendingPathComponent("\(id).json") }
    }

    private struct Meta: Decodable {
        let name: String
        let description: String
        let base: String
        let witnessOrder: [String]
        let recordAccidentals: Bool
        let recordPunctuation: Bool?    // optional (default false) — the diplomatic punctuation overlay (B6b)
        let pagination: PaginationSpec
        let normalizer: String         // "substantive" | "gbUS" | "diplomatic"
        let strategy: String?           // optional (default base-anchored) — "base-anchored" | "peer-msa" (B14)
        let lexicon: [[String]]?        // optional (B10) — translation equivalence groups, inline

        var collationStrategy: CollationStrategy {
            switch strategy {
            case "peer-msa", "peerMSA": return .peerMSA
            default:                    return .baseAnchored
            }
        }
        var translationLexicon: TranslationLexicon? {
            lexicon.map { TranslationLexicon(groups: $0) }
        }

        // pagination is either a string tag ("default" | "throughNumbered") or { "linesPerPage": N }.
        enum PaginationSpec: Decodable {
            case `default`, throughNumbered, linesPerPage(Int)
            init(from decoder: Decoder) throws {
                if let s = try? decoder.singleValueContainer().decode(String.self) {
                    switch s {
                    case "default": self = .default
                    case "throughNumbered": self = .throughNumbered
                    default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                debugDescription: "unknown pagination tag \(s)"))
                    }
                    return
                }
                struct Obj: Decodable { let linesPerPage: Int }
                self = .linesPerPage(try Obj(from: decoder).linesPerPage)
            }
            var model: PaginationModel {
                switch self {
                case .default: return .default
                case .throughNumbered: return .throughNumbered
                case .linesPerPage(let n): return .printedPage(linesPerPage: n)
                }
            }
        }
    }

    private static func normalizer(named name: String) -> Normalizer {
        switch name {
        case "gbUS": return Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        case "diplomatic": return .diplomatic
        default: return .substantive
        }
    }

    /// Load every case under `cases/`, in directory order, building its witness set in `witnessOrder`.
    private static func loadCases() throws -> [Case] {
        let dirs = try FileManager.default
            .contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try dirs.map { dir in
            let metaData = try Data(contentsOf: dir.appendingPathComponent("meta.json"))
            let meta = try JSONDecoder().decode(Meta.self, from: metaData)
            let witnesses = try meta.witnessOrder.map { siglum -> Witness in
                let text = try String(contentsOf: dir.appendingPathComponent("\(siglum).txt"), encoding: .utf8)
                return Witness(id: siglum, text: text)
            }
            return Case(id: dir.lastPathComponent, meta: meta, witnesses: witnesses,
                        normalizer: normalizer(named: meta.normalizer),
                        pagination: meta.pagination.model)
        }
    }

    /// Emit the `{ graph, pairs }` JSON for a case through the SAME path as `collate-demo --json`.
    private static func emit(_ c: Case) -> String {
        CollationJSON.outputString(witnesses: c.witnesses, normalizer: c.normalizer,
                                   pagination: c.pagination, recordAccidentals: c.meta.recordAccidentals,
                                   recordPunctuation: c.meta.recordPunctuation ?? false,
                                   strategy: c.meta.collationStrategy,
                                   lexicon: c.meta.translationLexicon)
    }

    // MARK: tests

    func testCorpusIsNonEmpty() throws {
        let cases = try Self.loadCases()
        XCTAssertGreaterThanOrEqual(cases.count, 15, "the corpus should cover ~15–20 behaviour cases")
    }

    /// B1: each case's freshly-emitted JSON equals its committed golden, byte-for-byte. With
    /// COLLATION_RECORD=1 this WRITES the goldens instead of asserting (the documented refresh path).
    func testGoldensMatchOrRecord() throws {
        try FileManager.default.createDirectory(at: Self.goldenDir, withIntermediateDirectories: true)
        for c in try Self.loadCases() {
            let produced = Self.emit(c) + "\n"
            if Self.recording {
                try produced.write(to: c.goldenURL, atomically: true, encoding: .utf8)
                continue
            }
            guard let golden = try? String(contentsOf: c.goldenURL, encoding: .utf8) else {
                XCTFail("missing golden for \(c.id); run COLLATION_RECORD=1 swift test --filter Conformance")
                continue
            }
            if produced != golden {
                XCTFail("golden mismatch for \(c.id): the engine no longer reproduces docs/conformance/golden/\(c.id).json. "
                        + "If this is an INTENTIONAL behaviour change, refresh with COLLATION_RECORD=1.")
            }
        }
    }

    /// B1: the emitter is deterministic — identical bytes on repeat (guards §9 rule 5, the sorted-output rule).
    func testEmissionIsDeterministic() throws {
        for c in try Self.loadCases() {
            XCTAssertEqual(Self.emit(c), Self.emit(c), "non-deterministic output for \(c.id)")
        }
    }

    /// B1↔B2: each golden strictly decodes into the CollationJSON DTOs (the Swift mirror of the schema), and
    /// its schemaVersion matches the schema's declared const — so the wire shape and the schema can't drift
    /// apart silently. Skipped while recording (goldens may not exist yet).
    func testGoldensConformToInterchangeShape() throws {
        try XCTSkipIf(Self.recording, "recording goldens; conformance asserted on the next non-record run")
        let decoder = JSONDecoder()
        let schemaVersion = try Self.schemaConstSchemaVersion()
        XCTAssertEqual(schemaVersion, CollationJSON.schemaVersion,
                       "schema const schemaVersion is out of step with CollationJSON.schemaVersion")
        for c in try Self.loadCases() {
            let data = try Data(contentsOf: c.goldenURL)
            let out = try decoder.decode(CollationJSON.Output.self, from: data)   // strict shape check
            XCTAssertEqual(out.graph.schemaVersion, schemaVersion, "graph schemaVersion in \(c.id)")
            for p in out.pairs { XCTAssertEqual(p.schemaVersion, schemaVersion, "pair schemaVersion in \(c.id)") }
        }
    }

    /// Read the `schemaVersion` const out of collation.schema.json (its $defs.schemaVersion.const).
    private static func schemaConstSchemaVersion() throws -> Int {
        let data = try Data(contentsOf: schemaURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let defs = json?["$defs"] as? [String: Any]
        let sv = defs?["schemaVersion"] as? [String: Any]
        guard let constant = sv?["const"] as? Int else {
            throw XCTSkip("collation.schema.json has no $defs.schemaVersion.const")
        }
        return constant
    }
}
