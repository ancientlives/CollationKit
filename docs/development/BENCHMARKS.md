# Benchmarks — measured cost (BACKLOG B3)

The development log *characterised* the engine's cost (it depends on lexical diversity, not just length —
see DEVELOPMENT_LOG 2026-06-28); this document **measures** it. It supplies the measured numbers for the engine's evaluation. The harness is the `collate-bench` target.

```sh
swift run -c release collate-bench                 # default sweep → table + CSV on stdout
swift run -c release collate-bench --csv out.csv   # also write the CSV to a file
swift run -c release collate-bench --quick         # smaller, faster smoke sweep
```

> Always measure with `-c release`; a debug build is several × slower and not representative (the harness
> prints the build config in its header so a recorded run can't be misread).

> **Since B14 (2026-07-06)** the graph sweep runs **witness-count × merge strategy** (`base-anchored` vs
> `peer-msa`) — the measured half of the engine paper's two-strategy ablation. Early observation from the
> quick sweep: the peer merge is *faster* than the lift at the same N (it aligns keys against the consensus
> directly, skipping the per-witness pairwise classifier) — e.g. N=4 × 1000 words: ~10 ms vs ~16 ms — with the
> same ~linear growth in N; on the real full-novel pair (~105k/144k words) both strategies run < 4 s. Note the
> `variants` column is **not comparable across strategies**: the peer apparatus is token-granular, so an
> unequal-length rewrite counts as substitution + insertion nodes where the lift's classifier coalesced one
> entry — a granularity difference, not extra findings. Re-record the full CSV at the next B3 refresh.

## Debug vs. release — why full texts need `-c release`

`swift run` and `swift build` produce a **debug** binary by default (a SwiftPM/Xcode convention, not a project
choice): unoptimised, with assertions and integer-overflow traps live and full debug symbols — fast to compile
and safe to debug, which is what you want while *developing* the engine. The cost is runtime speed: the
Needleman–Wunsch core and the token-graph merge run many times slower unoptimised. On small inputs nobody
notices; on a full novel the difference is **seconds vs. minutes**, and because each stage can grind for minutes
a debug run *reads as a freeze* even though it is making progress (the engine prints per-stage progress to
stderr precisely so you can see it working). This is why the docs steer you to a **release** build for real
texts rather than flipping the default — debug is the right default for the edit-run-test loop; release is for
*using* the engine on large corpora:

```sh
swift build -c release
.build/release/collate run a.txt b.txt --out ./results     # or:  swift run -c release collate run …
```

A debug run on input over ~200k characters prints a one-time warning to this effect.

**Reference points** (release, Apple silicon), **end-to-end** — load + collate + render + write all six export
files (the ~14 MB interactive HTML included):

| input | witnesses | words | end-to-end |
|-------|----------:|------:|-----------:|
| *20,000 Leagues* (Mercier ↔ Walter) | 2 | ~105k / ~144k | ~5 s |
| three full novels | 3 | ~270k total | ~6 s |

The **engine core** alone (`collate` + `variantGraph`, what the `collate-bench` sweep above times) is under 4 s
for the full-novel pair; the extra ~1 s is tokenising from disk and writing the exports. The same run in a
**debug** build does not finish in two minutes.

## Method

The harness sweeps the **three variables that actually drive cost** and times (records the time) the public API
(`Collation.collate` and `Collation.variantGraph`):

- **length** — witness word count. The Needleman–Wunsch core is `O(n·m)`, but bounded by anchor chunking,
  so for distinctive prose it behaves far closer to linear.
- **lexical diversity** — the fraction of *distinctive* tokens, which sets **anchor density**: unique
  n-grams let the anchor pass chunk NW into small regions; low-diversity text starves the anchor pass and
  falls back to the banded matrix. This is the non-obvious axis (the "cost depends on information, not
  length" result).
- **witness count** — `N` for the N-witness variant graph (progressive base-anchored fold).

Corpus generation is **deterministic** (a fixed-seed SplitMix64 PRNG), so the *shape* of the results
reproduces run to run; absolute times are machine-dependent. Each point is **warmed up once, then measured
over 5 trials, and the median reported** to damp scheduler noise. `anchorDensity` (fraction of comparable
tokens whose normalized key is unique) is reported next to each time because it is the variable that
*explains* the time. The raw CSV for the run below is committed at
[`benchmarks/results.csv`](benchmarks/results.csv).

## Recorded results

Host: macOS 26.5.1 (Build 25F80), 8 cores; build: release; 5 trials/point (median); editRate 0.05.
*(Absolute times are host-specific; the relationships are the result.)*

### Pairwise — time vs. length × lexical diversity (2 witnesses)

| words | diversity | anchorDensity | variants | time (ms) |
|------:|----------:|--------------:|---------:|----------:|
| 500   | 0.10 | 0.114 | 1   | 1.29 |
| 500   | 0.30 | 0.290 | 6   | 1.32 |
| 500   | 0.60 | 0.592 | 12  | 1.44 |
| 500   | 0.90 | 0.898 | 23  | 1.47 |
| 1000  | 0.10 | 0.109 | 9   | 2.57 |
| 1000  | 0.60 | 0.597 | 30  | 2.85 |
| 1000  | 0.90 | 0.893 | 37  | 2.95 |
| 2000  | 0.10 | 0.105 | 9   | 5.23 |
| 2000  | 0.60 | 0.606 | 50  | 5.84 |
| 2000  | 0.90 | 0.889 | 67  | 6.09 |
| 4000  | 0.10 | 0.096 | 15  | 10.12 |
| 4000  | 0.60 | 0.597 | 126 | 12.38 |
| 4000  | 0.90 | 0.903 | 139 | 12.94 |
| 8000  | 0.10 | 0.101 | 31  | 20.39 |
| 8000  | 0.60 | 0.609 | 201 | 26.42 |
| 8000  | 0.90 | 0.900 | 355 | 27.83 |

### Graph — time vs. witness count (2000 words, diversity 0.60)

| witnesses | anchorDensity | variants | time (ms) |
|----------:|--------------:|---------:|----------:|
| 2 | 0.613 | 78  | 10.55 |
| 3 | 0.606 | 119 | 18.71 |
| 5 | 0.591 | 206 | 34.95 |
| 8 | 0.608 | 368 | 59.28 |

## What the numbers show

1. **Near-linear in length for realistic prose.** From 500 → 8000 words (16×) the pairwise time grows
   ≈ 1.4 ms → 27.8 ms at high diversity (≈ 19×) — close to linear, not the `O(n·m)` worst case. Anchor
   chunking is doing its job: a lightly-edited 8k-word witness pair collates in **under 30 ms**.
2. **Diversity's effect is modest at realistic anchor densities — and the anchor pass is robust.** Even at
   diversity 0.10 the time is within ~30 % of diversity 0.90 at the same length, because index-suffixed
   tokens still leave *some* unique anchors. The pathological cliff is the *near-zero* anchor-density case
   (heavily repetitive text), which the banded fallback bounds by design (characterised in the
   DEVELOPMENT_LOG; not re-measured here because the generator floors anchor density above zero).
3. **The N-witness graph scales ~linearly in witness count.** 2 → 8 witnesses (4×) takes 10.6 ms → 59.3 ms
   (≈ 5.6×) — consistent with the progressive base-anchored fold doing `N−1` pairwise collations plus the
   fold, slightly super-linear from the growing reading sets.
4. **Variant count tracks diversity and length** as expected (more distinctive tokens → more edit sites
   land on distinctive words → more reported variants), a sanity check that the timing path is real work.

## Honest limitations of this benchmark

- **Synthetic corpus.** The text is generated, not natural prose; the real-edition cases
  ([`CASE_STUDY.md`](CASE_STUDY.md)) cover *correctness* on real text, this covers *cost* on controlled
  inputs. The two are complementary.
- **Anchor-density floor.** The generator never produces *zero* anchors, so the worst-case banded-fallback
  cliff is characterised (DEVELOPMENT_LOG) rather than measured here; a dedicated adversarial point (all
  tokens from a tiny pool) would measure it and is a natural extension.
- **Single host.** Numbers are from one machine; the harness header records the host so results stay
  interpretable. Cross-machine / cross-language timing (e.g. against a Rust port) is future work
  (`porting/RUST_STANDALONE_PLAN.md`).
