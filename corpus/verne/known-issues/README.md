# Known issues surfaced by this corpus

Real editions are a stress test; here is what they exposed in the engine. These are **engine** findings, not
corpus problems — recorded here (with reproducers) so they can be fixed in CollationKit.

## 1. Full-novel collation crashes — `Range requires lowerBound <= upperBound` — ✅ FIXED 2026-07-01

**Resolution.** Fixed in `Transposition.appendRegion` (it now takes bounds and clamps the region spans, so
B-overlapping spine anchors yield an empty gap instead of an inverted range). The full novels now collate
(~3 s, ≈21.8k variants). Guarded by `PropertyTests.testLargeRepetitiveReorderedPairsDoNotTrap` (verified to
reproduce the crash pre-fix). See `docs/development/DEVELOPMENT_LOG.md` 2026-07-01. The account below is kept for
the record.

**What (was).** Collating the two whole-novel witnesses of *Twenty Thousand Leagues*
(`corpus/verne/20000-leagues/full/mercier.txt` vs `full/walter.txt`, ~106k vs ~148k words) aborted with a fatal
`Range requires lowerBound <= upperBound` — an inverted `Range` in the engine. Fast (<1 s), so a logic trap,
not a timeout. All output formats crashed (the fault is in the pairwise collation, before rendering).

**Minimal reproducer (saved here).** The crash first appears around **700 lines** of each witness:

```sh
BIN=.build/debug/collate     # (built at the repository root with `swift build`)
$BIN run corpus/verne/known-issues/repro-mercier-700.txt corpus/verne/known-issues/repro-walter-700.txt --format text
# → Fatal error: Range requires lowerBound <= upperBound
```

`repro-mercier-700.txt` / `repro-walter-700.txt` are `head -700` of the two full-novel witnesses; 600 lines
is OK, 700+ crashes. (`repro-walter-700.txt` comes from the copyrighted Walter translation, so it is not committed;
`scripts/build_corpus.sh` rebuilds it locally. See `../README.md`, "Provenance & licence".)

**Likely area.** This is the same *class* as the inverted-`Range` bug the property tests once caught in
`Variation.location()` (fixed by taking min/max extremes — see DEVELOPMENT_LOG 2026-06-30), but a different,
un-hit path exposed by large, highly-divergent real translations (heavy transposition + move recovery). A fix
should (a) find the remaining `a..<b` construction that can invert under these inputs, guard it with
min/max, and (b) add a property/fuzz case at this scale so it stays fixed. The reproducer here is a ready
regression fixture.

**Workaround / impact on the corpus.** Use the **chapter excerpts** (`mercier.txt` / `walter.txt`, ~2k words)
for routine collation testing — they collate cleanly (~403 variants). The `full/*.txt` witnesses are retained
for the *scale* test that the fix should make pass.

---

*Add further findings below as new editions surface them.*
