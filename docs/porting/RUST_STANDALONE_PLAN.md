# Plan: a standalone, fastest-possible CLI collation engine

A planning experiment (not committed work): if the goal were a **standalone collation engine + CLI in the
fastest practical language**, how would we build it? This documents the language choice, architecture, and a
milestone plan, reusing everything already learned in the Swift prototype.

> Context: for embedding the engine in a native Swift/SwiftUI application, **Swift is the right choice** (no
> FFI/serialization boundary; the engine's value types feed SwiftUI directly). This plan is for a
> *different* goal: a portable, maximally fast, standalone research/CLI tool (and a natural WASM/web target).

## 1. Language choice

**Recommendation: Rust** — but the reasoning matters more than the verdict, because the choice turns on the
*shape of this specific engine*, not a general "X is fast" claim.

### The four axes that actually decide it

The engine is (a) **allocation- and branch-heavy** (DP matrices, n-gram hashing) and (b) **built on tagged
unions** — `AlignOp = match | substitute | delete | insert` plus the `Variation`/`SegmentKind` enums are
pervasive, and exhaustive `match`/`switch` over them is the core control flow. The web goal wants (c)
**first-class WASM**, and the DP buffers want (d) **memory safety** (where off-by-one / aliasing bugs live).
So the axes are: **raw speed · sum-type ergonomics · WASM · safety + ecosystem.**

| | Raw speed | Sum types / `match` | WASM/web | Safety + ecosystem | Fit for *this* engine |
|---|---|---|---|---|---|
| **Rust** | top tier (no GC, layout control, SIMD) | **excellent** — maps 1:1 from the Swift `enum` design | **first-class** (`wasm-pack`/`wasm-bindgen`) | safe by default; `cargo`, `serde`, `clap`, `criterion` | **Best on all four at once** |
| **Zig** | top tier | good (`tagged union` + `switch`) | yes | manual memory (safer than C); **young ecosystem, pre-1.0 churn** | **Runner-up** — as fast, weaker tooling/maturity |
| **C / C++** | top tier | **poor** — manual `struct{tag; union}`, no exhaustiveness | yes (Emscripten) | manual memory in DP buffers = bug-prone | Equal speed, hand-roll what Rust gives, with risk |
| **Go** | fast, but **GC** (pauses) | **weak** — no sum types; fake `AlignOp` via interfaces/tag | partial (TinyGo) | easy, great tooling | Easiest to *write*, **worst fit** — all sum types + tight loops |
| **Python** | **slow (10–100×)** | okay (dynamic; `match` ≥3.10) | weak/heavy (Pyodide) | superb for prototyping | The *sketching* language, **not** the "fastest" answer |
| **Swift (standalone)** | fast | excellent (already have it) | experimental/heavy | have it | No new benefit over the existing prototype |

### Why Rust over each alternative (the candid version)

- **The goal was "fastest possible,"** which removes **Python** (it's where you'd *prototype* an algorithm,
  not ship speed — you'd drop to NumPy/C for the DP anyway) and **Go** (GC pauses + no sum types make it the
  *worst structural fit* for an enum-and-tight-loop engine, despite being easiest to write).
- That leaves the genuinely-fast trio — **C, Rust, Zig** — and here is the honest part: **among these three,
  raw speed is largely a wash** for this workload. It is bounded by the same `O(n·m)` DP and n-gram hashing;
  hand-tuned C or Zig with SIMD could edge a microbenchmark, but the marginal gain isn't worth the cost. So
  the tiebreaker is *fit + safety + ecosystem + WASM*, **not speed**:
  - **C** loses on safety (manual memory exactly where the bugs are) and on modelling the sum-type-heavy
    design (no exhaustiveness; error-prone tagged unions).
  - **Zig** is the legitimate runner-up — comparable speed, real tagged unions + `switch`, decent WASM —
    losing to Rust *only* on maturity: a settled language plus the libraries (`serde` for the JSON contract,
    `clap` for the CLI, `criterion`/`wasm-bindgen` for bench/web) that make the port mechanical. Defensible if
    minimalism is valued over ecosystem.
  - **Rust** uniquely wins **all four axes at once**: C-class speed, *with* memory safety, *with* the
    algebraic-data-type ergonomics that let the Swift design port almost mechanically (`enum`→`enum`,
    `switch`→`match`), *with* the best WASM story.

**Bottom line:** Rust is chosen not because it is uniquely fastest (it isn't, versus C/Zig) but because it is
*as fast as anything realistic* while being the best **fit** for a sum-type-heavy, allocation-heavy engine
that must be safe and ship to WASM. For pure peak microbenchmark speed alone, C/Zig + SIMD is the alternative;
for fastest *time-to-correct-port*, Rust.

## 2. What to reuse from the Swift prototype

The hard intellectual work is **language-independent** and already done — port the *design*, not the code:

- the pipeline (tokenize → normalize → align → classify → graph → render);
- Needleman–Wunsch with the 2/−1/−2 scoring and deterministic traceback;
- the anchor pass: unique-common n-grams → max-weight increasing subsequence (page-aware) → masked regions;
- recursive anchoring (bounded-gap bridging + inner alignment);
- adaptive anchor length + banded NW fallback;
- the location/citation model and `PaginationModel`;
- the **JSON interchange schema** — reuse it verbatim as the Rust tool's output, so results are
  **byte-comparable** with the Swift engine (a built-in cross-implementation test: same witnesses → same JSON).

[`ALGORITHMS.md`](../reference/ALGORITHMS.md) is the port spec ([`PAPER_NOTES.md`](../reference/PAPER_NOTES.md)
is the Swift-grounded reference).

## 3. Crate layout

```
collate-rs/
  Cargo.toml
  crates/
    collation-core/      # the pure engine — no I/O, no CLI; mirrors CollationKit
      src/
        token.rs         # Witness, Token, Kind
        normalize.rs     # Normalizer, presets, GB/US table
        tokenize.rs      # tokenizer + PaginationModel
        align.rs         # needleman_wunsch, banded, banded_auto_widening
        transposition.rs # anchors, max-weight LIS, bridging, inner alignment
        variation.rs     # Variation, TextLocation, classifier
        collation.rs     # collate(), variant_graph()
        apparatus.rs / synopsis.rs / report.rs / json.rs
      tests/             # port the Swift test suite 1:1 (same fixtures, same assertions)
    collate-cli/         # thin CLI over collation-core (clap)
    collate-wasm/        # wasm-bindgen wrapper exposing collate()/variant_graph() → JSON
```

Recommended dependencies, all mature and lightweight:

- `clap` — CLI args (mirrors the demo's `--accidentals`, `--lines-per-page`, `--json`, …).
- `serde` + `serde_json` — the JSON interchange (reuse the `schemaVersion`-tagged schema).
- `unicode-segmentation` — correct word/grapheme boundaries (better than the prototype's hand-rolled scan).
- `wasm-bindgen` + `wasm-pack` (wasm crate only) — the web target.
- (optional) `rayon` — data-parallel N-witness collation (each base↔witness pair is independent → trivial
  parallelism); `criterion` for benchmarks.

## 4. Performance opportunities Rust unlocks (beyond a straight port)

- **Intern tokens to `u32` ids.** Map each normalized key to an integer once; alignment then compares ints,
  not strings — big constant-factor win in the DP inner loop and n-gram hashing.
- **Flat DP buffers.** Use a single `Vec<i32>` with manual indexing (or two rolling rows) instead of a vector
  of vectors — cache-friendly; the banded variant stores only the band.
- **`rayon` over witness pairs** for the N-witness graph (embarrassingly parallel).
- **Zero-copy slices** for regions/inner alignments (`&[u32]`), no per-region allocation.
- **SIMD** (optional, later) for the NW row update — diminishing returns, do only if benchmarks demand.

Expect order-of-magnitude throughput over the prototype on large corpora, before any SIMD.

## 5. Milestones

1. **M1 — core port + parity tests (1 unit).** Port `collation-core` and the *entire* Swift test suite as Rust
   tests, same fixtures. Done when all pass and the six-edition JSON matches the Swift `--json` byte-for-byte
   (the strongest correctness signal: two independent implementations agreeing).
2. **M2 — CLI.** `collate-cli` with the demo's flags; reads files/stdin, emits text or `--json`.
3. **M3 — perf pass.** Token interning + flat/banded buffers + `rayon`; add `criterion` benchmarks across the
   lexical-diversity spectrum and witness counts; record the cost curve (paper material).
4. **M4 — WASM + minimal web demo.** `collate-wasm` exposes `collate(jsonInput) → jsonOutput`; a tiny web page
   renders the synoptic columns / apparatus from the JSON. Proves the portability thesis end to end.
5. **M5 (optional) — comparison harness.** Drive CollateX and this tool over a shared corpus, diff the JSON,
   quantify where transposition/citation handling differs (feeds the paper's empirical section).

## 6. Risks / notes

- **Unicode/tokenisation parity.** Using `unicode-segmentation` may tokenise slightly differently from the
  prototype's hand-rolled scanner; lock parity in M1 (it's a feature, but must be deliberate).
- **Determinism across languages.** Sorted JSON keys + sorted readings already make output byte-stable; keep
  the same tie-break rules (diagonal>up>left; earliest-in-A anchor pruning) so the Rust output matches Swift.
- **Scope creep.** The standalone tool is only worthwhile if a use beyond a native Swift application exists
  (research CLI, web demo, speed at scale). If the only consumer is a Swift application, this plan is a *thought
  experiment* and Swift stays the answer.

## 7. Bottom line

Rust would make a *standalone* engine the fastest and most portable, with a clean WASM/web path, and the port
is low-risk because the design is fully specified (`ALGORITHMS.md`) and the JSON schema gives an automatic
cross-implementation correctness check. It would **not** help — and would add a boundary — for embedding in a
native Swift application, which stays Swift.
