// swift-tools-version: 5.9
import PackageDescription

// CollationKit — a standalone, deterministic textual-collation engine, originally prototyped for a native
// macOS markdown editor (the intended host application).
//
// PURE Swift, no AppKit / no I/O: value-type input/output, deterministic, deeply unit-tested. Built in
// isolation so the hardest parts (transposition-aware alignment across pages, N-witness variant graphs)
// can be developed and verified independently of any host application.
let package = Package(
    name: "CollationKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CollationKit", targets: ["CollationKit"]),
        .executable(name: "collate-demo", targets: ["collate-demo"]),
        .executable(name: "collate-bench", targets: ["collate-bench"]),
        // B9: the `collate` harness — a testable CLI core (`CollateCLI`) + a thin shell (`collate`). The core
        // depends on `CollationKit` only (one-way: collate → CollateCLI → CollationKit); the engine never
        // depends on the CLI. See docs/development/CLI_PLAN.md §0.
        .executable(name: "collate", targets: ["collate"]),
    ],
    targets: [
        .target(name: "CollationKit"),
        .executableTarget(name: "collate-demo", dependencies: ["CollationKit"]),
        .executableTarget(name: "collate-bench", dependencies: ["CollationKit"]),
        // The testable CLI core (no process/exit, no raw stdin) — pure I/O + formatting over the engine's
        // public API. Unit-tested without a terminal.
        .target(name: "CollateCLI", dependencies: ["CollationKit"]),
        // The thin shell: wire argv + real stdout/stderr + exit codes to the core.
        .executableTarget(name: "collate", dependencies: ["CollateCLI"]),
        .testTarget(name: "CollationKitTests", dependencies: ["CollationKit", "CollateCLI"]),
    ]
)
