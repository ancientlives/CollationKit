#!/usr/bin/env bash
# Regenerate the live viewer demos published on the project website (site/demos/*.html).
# Run from anywhere; builds the release binary first. Each demo is a self-contained collation.html.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release >/dev/null
BIN=.build/release/collate
OUT=site/demos
C=docs/conformance/cases
V=corpus/verne
mkdir -p "$OUT"

# Frankenstein, 1818 vs 1831 (authorial revision, pairwise), diplomatic: punctuation + spelling recorded too.
$BIN run --format html --diplomatic $C/26-frankenstein-diplomatic/{1818,1831}.txt > "$OUT/frankenstein.html"

# Whitman, "Song of Myself" opening across three editions (N-witness variant graph).
$BIN run --format html $C/23-whitman-three-editions/{ed1855,ed1860,ed1891}.txt > "$OUT/whitman-three-editions.html"

# Whitman, the "Calamus" cluster 1860 vs 1867: a found whole-poem transposition.
$BIN run --format html $C/27-whitman-calamus-cluster/{ed1860,ed1867}.txt > "$OUT/whitman-calamus.html"

# The six-edition example: manuscript → typescript → proofs → GB → US → Uniform, with a cross-page move.
$BIN run --format html --order MS,TS,PR,GB1,US1,UNI --dir $C/16-six-editions --all > "$OUT/six-editions.html"

# Verne, French original + two English translations, peer merge with a translation lexicon (cross-language).
LEX="$(mktemp)"
python3 -c "import json,sys; [print(', '.join(g)) for g in json.load(open(sys.argv[1]))['lexicon']]" \
  $C/29-verne-trilingual-peer/meta.json > "$LEX"
$BIN run --format html --strategy peer-msa --lexicon "$LEX" \
  $C/29-verne-trilingual-peer/{fr-5097,en-mercier,en-walter}.txt > "$OUT/verne-trilingual.html"
rm -f "$LEX"

# Verne, Journey to the Centre of the Earth chapter 1: two competing 19th-century English translations
# (heavy rewording + moves; they even name the professor differently). Public domain.
$BIN run --format html --strategy peer-msa $V/journey-centre-earth/{malleson,ward}.txt > "$OUT/verne-journey-ch1.html"

# Not published (≈28 MB): the whole novel of Journey to the Centre of the Earth. Reproduce locally with
#   .build/release/collate run corpus/verne/journey-centre-earth/full/{malleson,ward}.txt --out ./results

ls -la "$OUT"
