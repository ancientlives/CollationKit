# Baseline: state of the repository at review time

Measured on 3 October 2026, branch `review/release-1` from `main` at `e340719` (after PR #5).

## Build and tests

| Check | Result |
| --- | --- |
| `swift build` (clean, debug) | Succeeds. **0 warnings in `Sources/`** |
| `swift build -c release` | Succeeds |
| `swift test` | **222 tests, 0 failures**, about 8 s |
| Compiler warnings in `Tests/` | 3, all "variable was never mutated; change to `let`": `LexicalDiversityTests.swift:59`, `:82`, `PropertyTests.swift:100` |
| Conformance goldens (`validate.py`) | 29 / 29 valid against the JSON Schema |
| CI on `main` | Green (macOS build and test; schema validation on Ubuntu) |
| Toolchain used | Apple Swift 6.3.2, macOS (arm64) |

## Size

| Area | Lines | Files |
| --- | --- | --- |
| `Sources/CollationKit` (engine) | 3,788 | 16 |
| `Sources/CollateCLI` (CLI core and viewer; `HTMLExport.swift` alone is about 2,200) | 3,485 | 9 |
| `Sources/collate`, `collate-demo`, `collate-bench` (executables) | 18 / 91 / 219 | 3 |
| `Tests/CollationKitTests` | 3,523 | 27 suites, 222 tests |
| Public declarations in the engine (`public …`) | 238 | |
| Documentation (Markdown under the root, `docs/`, `corpus/verne/`) | about 8,600 | 24 files |
| `docs/development/DEVELOPMENT_LOG.md` | 2,266 | |

| Folder | Size |
| --- | --- |
| `corpus/` | 4.2 MB (public-domain texts; the Walter translation is rebuilt locally) |
| `docs/` | 1.5 MB (mostly conformance goldens) |
| `site/` | 1.5 MB (six demo viewers) |
| `Sources/` · `Tests/` | 0.5 MB · 0.3 MB |
