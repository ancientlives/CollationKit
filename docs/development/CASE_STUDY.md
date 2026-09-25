# Case studies — real multi-edition works (BACKLOG B4)

Backlog **B4** asked for *"at least one genuine multi-witness work (not crafted fixtures)… the biggest
credibility gap for the paper; stress-tests the engine on prose it didn't grow up on."* This is that
study: the engine run on **real, public-domain** passages — across an author's revised editions, across
competing translations, and across languages — with the results, favourable and unfavourable, reported
honestly.

Nine cases, chosen to exercise different variant types, different *kinds* of variation (authorial
revision, translation, cross-language), different *witness counts* (pairwise and N-witness), and three
scripts:

| # | author / work | witnesses | what it stress-tests | corpus case |
|---|---------------|-----------|----------------------|-------------|
| 1 | Mary Shelley, *Frankenstein* (creation scene) | 1818 vs 1831 editions | accidental-heavy revision; **false-positive resistance** | `17-frankenstein-creation-scene` |
| 2 | Walt Whitman, *Song of Myself* (opening) | 1855 vs 1891 editions | genuine substantive **insertion** (one word + two whole stanzas) | `18-whitman-song-of-myself` |
| 3 | Walt Whitman, *Song of Myself* (two stanzas) | 1891 vs relocated-line | **transposition** (a moved line, semi-synthetic — see caveat) | `19-whitman-transposition` |
| 4 | Jules Verne, *20,000 Leagues* (Pt 1 Ch 1) | Mercier (1872) vs Walter translations | **translation collation** — heavy substantive substitution | `20-verne-translation` |
| 5 | Jules Verne, *Vingt mille lieues* (Pt 1 Ch 1) | two French editions | **French tokenisation** (accents, elision apostrophes) | `21-verne-french-editions` |
| 6 | Jules Verne, *20,000 Leagues* (Pt 1 Ch 1) | **3 witnesses**: French + Mercier + Walter | **N-witness cross-language graph** — exposes the base-anchored limit | `22-verne-trilingual-graph` |
| 7 | Walt Whitman, *Song of Myself* (3 stanzas) | **3 editions**: 1855 / 1860 / 1891 | **N-witness edition evolution** — real "one author, many editions" graph | `23-whitman-three-editions` |
| 8 | Alexander Pushkin, *Я вас любил* (1829) | canonical vs controlled variant | **Cyrillic tokenisation** (third script family) | `24-pushkin-cyrillic` |
| 9 | Walt Whitman, *Calamus* cluster | 1860 vs 1867 cluster order | **found poem-cluster transposition** — a whole poem relocated between editions | `27-whitman-calamus-cluster` |

Three authors, three kinds of variation (revision, translation, cross-language), two witness counts
(pairwise + N-witness), and three scripts (Latin/English, Latin/French-diacritics, Greek earlier in the
corpus, and now Cyrillic). Cases 1–2 bracket authorial revision; case 3 the transposition feature at
line-scale; cases 4–5 extend to translation and French; cases 6–7 stress the **N-witness variant graph**
on real text (one cross-language, one true multi-edition); case 8 adds a third script; **case 9 supplies
the *found* poem/cluster-scale transposition** the Case-3 caveat left as future work. Several cases also
surface concrete limitations (collected in *Implications*, below) — the honest "tested in the wild" outcome.

> **Project context — a Verne digital corpus.** Cases 4, 5 and 6 are also *pilots* for a larger goal: a
> collated digital corpus of Verne's works across all French editions and English translations. The
> trilingual graph (Case 6) is the first probe of what French↔English collation needs at scale — and its
> result (below) already points at the answer: cross-language collation needs translation-aware anchoring,
> not the shared-word-form anchoring the substantive engine uses today.

---

## Case 1 — Mary Shelley, *Frankenstein* (1818 vs 1831)

### The witnesses

**Mary Shelley, *Frankenstein; or, The Modern Prometheus*, Chapter 5 — the creation scene** ("It was on a
dreary night of November…"), first two paragraphs, in the two authorial editions:

| siglum | edition | source |
|--------|---------|--------|
| `1818` | 1818 first edition | [Project Gutenberg #41445](https://www.gutenberg.org/ebooks/41445) (photo-reprint of the 1818 edition) |
| `1831` | 1831 revised edition | [Project Gutenberg #84](https://www.gutenberg.org/ebooks/84) |

Both are public domain. The verbatim passages are committed as conformance case
[`17-frankenstein-creation-scene`](../conformance/cases/17-frankenstein-creation-scene/) (≈203 words each),
so the run below is reproducible and locked as a golden.

This passage was chosen because it is the single most-discussed point of difference between the two
editions, and because — crucially — it is *lightly* revised rather than wholly rewritten, so the two texts
remain genuinely alignable (unlike, e.g., the Elizabeth-origin paragraph, which Shelley replaced
wholesale and which would collate as one giant substitution).

### What actually changed between the editions

Reading the two passages side by side, the 1818→1831 differences in *this* passage are:

- **Punctuation only (accidental):** `dreary night of November, that` → `…November that` (comma dropped);
  `rushed out of the room, and` → `…room and`; `slept indeed, but` → `slept, indeed, but`;
  `in vain:` → `in vain;`; `complexion, and straight` → `complexion and straight`.
- **Hyphenation / spacing (accidental):** `dun white` → `dun-white` (now folded by B6 — splits to the same
  `dun`/`white` word tokens); `window-shutters` → `window shutters`; `down stairs` → `downstairs`.
- **One typographic dash → space (borderline):** `Beautiful!—Great God!` → `Beautiful! Great God!`.

There is **no substantive (wording) revision** in this passage — every change is an accidental. That is
itself a finding about the source: Shelley's 1831 hand on this paragraph is a *compositor's*-level
revision, not a rewriting.

### What the engine reported

Substantive collation (accidentals folded — the default scholarly view):

```
1818.txt vs 1831.txt: no variants.
```

> **History (a tested→fixed arc).** When this case was first added the engine reported **one** spurious
> `SUBSTITUTION`, `dun white` → `dun-white`: the hyphen fused two words into a single token, so the
> aligner saw a 2-tokens-vs-1-token difference. That was a *tokenisation* artifact, not a wording change.
> It motivated **BACKLOG B6**, which now treats intra-word hyphenation as an accidental of word-division
> (the tokeniser splits `dun-white` into `dun` / `white` under substantive normalisation, ALGORITHMS §2).
> With B6 in place the passage collates as **no variants** — the correct result, since every real change
> here is accidental. This case is the regression test that keeps it fixed.

### Reading the result

**What the engine got right (the load-bearing result).** Across ~203 words of real, century-old prose it
had never seen, the engine reports the two paragraphs as **substantively identical** — exactly the right
scholarly judgement, since every real 1818→1831 change in this passage is accidental. It does **not**
hallucinate variants out of the punctuation and hyphenation churn. For a collator the *absence* of false
positives on noisy real prose is the headline: a line- or character-diff of these two texts would report
dozens of differences.

**Why this case earns its place.** It is the *hard negative* — a passage where the right answer is "nothing
substantive changed" — and it is what surfaced (and now regression-guards) the B6 hyphenation fix.

**The limitation this exposes (the honest news).** The other accidental changes — comma drops, `:`→`;`,
the `—`→space — are **invisible to the engine, even with `--accidentals`**. The normaliser's
`dropPunctuation` step removes punctuation *before* alignment, so punctuation-only differences never
become tokens and cannot be reported. The `--accidentals` switch surfaces *spelling/case* folds
(colour/color, End/end), not punctuation. So on this passage `--accidentals` produces the *same* output as
the substantive view. For born-digital editorial work that is often the desired behaviour; for a
diplomatic transcription where punctuation is editorially significant, it is a gap.

Case 1 is deliberately the *hard negative*: a passage that is almost all accidentals, where the right
answer is "nearly nothing changed." Case 2 supplies the *positive* — genuine substantive revision the
engine must catch.

---

## Case 2 — Walt Whitman, *Song of Myself* (1855 vs 1891)

### The witnesses

**Walt Whitman, "Song of Myself" (*Leaves of Grass*), the opening (sections 1–2)**, in the first and last
authorial editions:

| siglum | edition | source |
|--------|---------|--------|
| `1855` | 1855 first edition | [Internet Archive `whitmanleavesofgrass`](https://archive.org/details/whitmanleavesofgrass) OCR, **hand-corrected** against the canonical 1855 transcription (Univ. of Pennsylvania / [Whitman Archive](https://whitmanarchive.org/)) |
| `1891` | 1891–92 "deathbed" edition | [Project Gutenberg #1322](https://www.gutenberg.org/ebooks/1322), verbatim |

Both public domain; committed as conformance case
[`18-whitman-song-of-myself`](../conformance/cases/18-whitman-song-of-myself/). The only machine-readable
1855 first edition is an OCR scan with errors (`’ CELEBRATE`, `perfumcs`, `hke it`); those scan errors were
corrected against the well-attested 1855 wording so the collation reflects *real revision, not OCR noise*.
The authentic 1855 four-dot ` . . . . ` ellipses are retained; the 1891 text's presentational indent,
soft-wrapping and CRLF are normalised. Whitman is the ideal complement to Shelley because he revised
*Leaves of Grass* continuously across nine editions — exactly the "one author, many variant editions"
shape this study wants.

### What actually changed between the editions

This passage carries **genuine substantive revision** (not just accidentals):

- **Word insertion:** 1855 `I celebrate myself,` → 1891 `I celebrate myself, and sing myself,` — the single
  most-cited revision in the poem.
- **Two whole stanzas inserted** in 1891, absent from 1855: `My tongue, every atom of my blood…` and
  `Creeds and schools in abeyance…` (eight lines), dropped in between "spear of summer grass" and "Houses
  and rooms are full of perfumes".
- **Accidentals:** the 1855 four-dot ellipses become spaces; a comma is added at `fragrance myself, and`.

### What the engine reported

```
1855.txt vs 1891.txt: 2 variant(s)
  [1] INSERTION
      1855.txt: ∅ (omitted) @ —
      1891.txt: “and sing myself” @ p.1 · line 1 · words 5–7
  [2] INSERTION
      1855.txt: ∅ (omitted) @ —
      1891.txt: “My tongue , every atom of my blood … Nature without check with original energy”
                @ p.1 · lines 6–13 · words 1…6
```

### Reading the result

This is the engine doing exactly what a collator should on real substantive revision:

- **The famous three-word insertion** (`and sing myself`) is caught and **located precisely** (line 1,
  words 5–7).
- **The eight-line, two-stanza addition is reported as one coherent insertion block** — *not* fragmented
  into dozens of spurious per-word variants. This is the anchor-based alignment working on real verse: it
  found the shared lines on both sides of the gap ("…spear of summer grass" before, "Houses and rooms…"
  after) and attributed the entire inserted passage as a single variant spanning lines 6–13.
- **No false positives, no churn**, and the right *type* (insertion, not substitution) throughout.

**One honest limitation surfaced here — now resolved (B6c).** As first written, the N-witness apparatus
printed "(no points of variance)" for this pair even though the located pairwise report was correct: the
variant **graph** was base-anchored and **pure insertions weren't anchored into it**. The pairwise engine saw
the insertions; the graph view didn't surface them. **B6c fixed this**: each pure insertion is now emitted as
an *inserted node* (anchored after the base token it follows), so the apparatus/synopsis show the added text
(the base and any witness without it read `∅`). This was the smallest, lowest-risk slice of the "fuller
token-graph merge" a native viewer would want, and it de-risks the larger B11 redesign.

---

## Case 3 — Walt Whitman, transposition (a moved line)

### The witnesses (and an honest caveat)

The engine's headline feature is **transposition** — detecting text that *moved* rather than reporting it
as a deletion here and an insertion there. To exercise that on real-derived text, witness **`A-1891`** is a
verbatim pair of stanzas from "Song of Myself" (1891, Gutenberg #1322); witness **`B-moved`** is built from
it by **relocating one intact line** (`We have had ducking and deprecating about enough,`) to an earlier
position. Committed as [`19-whitman-transposition`](../conformance/cases/19-whitman-transposition/).

> **Caveat — this is *semi-synthetic*, and deliberately so.** It is **not** a found authorial move. A
> survey of Whitman 1855 vs 1891 (the poet-of-the-body stanza, the "Walt Whitman, a kosmos" lines, the
> enumerative catalogues) turned up substitutions and line-*merges* but **no clean authorial transposition
> of an intact line/passage**. The textual scholarship explains why: Whitman's documented rearrangement
> across editions is at the level of **whole poems and clusters** ("the incessant rearrangement of his poems
> in various clusters", regrouped edition to edition), not lines within a passage. Line-level authorial
> *moves* are rare in the wild — itself a finding. So this case uses a **controlled, documented** move on
> real text to test the feature unambiguously; a genuine poem-cluster transposition would need multi-poem
> witnesses. **That future-work note is now discharged by [Case 9](#case-9--walt-whitman-calamus-cluster--a-found-poem-cluster-transposition)** — a *found* whole-poem relocation in the 1860→1867 "Calamus" cluster, which
> the engine detects as one `TRANSPOSITION`. This case remains as the *line-scale* control alongside it.

### What the engine reported

```
A-1891.txt vs B-moved.txt: 1 variant(s)
  [1] TRANSPOSITION (moved)
      A-1891.txt: “We have had ducking and deprecating about enough” @ p.1 · line 5 · words 1–8
      B-moved.txt: “We have had ducking and deprecating about enough” @ p.1 · line 2 · words 1–8
```

### Reading the result

Exactly right: **one `TRANSPOSITION`**, not a deletion + insertion. The engine recognised the relocated
line as the *same* reading in a new position (line 5 → line 2) and reported it as a single move. This is the
contribution-#1 behaviour (located transposition) demonstrated on real-text-derived input rather than a
crafted fixture.

---

## Case 4 — Jules Verne, *20,000 Leagues* — translation collation

### The witnesses

A different *kind* of variation: not one author revising, but **two competing English translations of the
same French original**. The opening paragraph of *Twenty Thousand Leagues Under the Seas* (Part 1, Ch. 1),
in:

| siglum | translation | source |
|--------|-------------|--------|
| `mercier` | Lewis Page Mercier (1872), the abridging "standard" | [Project Gutenberg #164](https://www.gutenberg.org/ebooks/164) |
| `walter` | F. P. Walter, complete/unabridged | [Project Gutenberg #2488](https://www.gutenberg.org/ebooks/2488) |

Committed as [`20-verne-translation`](../conformance/cases/20-verne-translation/). This extends the engine
beyond authorial revision to **translation collation** — a genuinely useful application (comparing renderings
of a source), and a much harder alignment because the two texts share *meaning* but diverge heavily in
*wording*.

### What the engine reported (abridged)

```
mercier.txt vs walter.txt: 13 variant(s)
  [1]  SUBSTITUTION  “signalised”                  → “marked”
  [2]  SUBSTITUTION  “remarkable incident , a mysterious” → “bizarre development , an unexplained”
  …
  [12] SUBSTITUTION  “deeply interested in”        → “all extremely disturbed by”
  [13] SUBSTITUTION  “matter”                      → “business”
```

(13 substitutions, each precisely located; full output is the committed golden.)

### Reading the result

This is the engine generalising well to an axis it wasn't designed for:

- It **anchored on the words the two translations share** (`year 1866 was`, `phenomenon`, `forgotten`,
  `captains of vessels , skippers`, `Europe and America`, `naval officers`, `two continents`) and aligned
  around them.
- It reported **phrase-level substitutions, coalesced** — e.g. `the Governments of several states` →
  `at their heels the various national governments` is *one* substitution, not seven word-variants. The
  reworded-clause-as-one-substitution behaviour (a crafted-corpus claim) holds on real divergent prose.
- Correct **locations** throughout, tracking the line drift between the two layouts.

That a substantive-collation engine produces a clean, located apparatus for *translation* variants — where a
character/line diff would be near-useless — is a strong, paper-worthy generalisation result.

---

## Case 5 — Jules Verne, *Vingt mille lieues* — French tokenisation

### The witnesses

The **same passage in the original French**, in two independent Project Gutenberg editions
([#5097](https://www.gutenberg.org/ebooks/5097) and [#54873](https://www.gutenberg.org/ebooks/54873)),
committed as [`21-verne-french-editions`](../conformance/cases/21-verne-french-editions/). The two editions
are textually identical here except one accidental — a comma (`continents, les gens` vs `continents les
gens`). The case's purpose is to exercise the **tokeniser on French**: accented characters (`é à È`) and
**elision apostrophes** (`L'année`, `n'a`, `l'esprit`, `l'intérieur`, `l'Europe`).

### What the engine reported

```
ed5097.txt vs ed54873.txt: no variants.
```

### Reading the result

Correct — and a *true* positive, not a no-op. The only real difference is the folded comma, so substantive
collation rightly reports **no variants**. To prove the French was genuinely tokenised (not skipped), a
control edit (`personne` → `quiconque`) was located correctly at `line 2 · word 5` — i.e. the engine counted
correctly *through* the elided words `L'année`, `n'a` to reach it. So:

- **French tokenisation works** across accents and elision apostrophes — encouraging for the
  cross-script/parity goal (B6), and the first non-English text in the corpus.
- It **re-confirms the B6b punctuation finding in a second language**: the comma-only edition difference is
  invisible because punctuation is folded before alignment.

---

## Case 6 — Jules Verne, *20,000 Leagues* — N-witness cross-language graph

### The witnesses

The first **N-witness real case** (three witnesses), and a deliberate probe for the Verne-corpus goal: the
opening paragraph as **the French original plus its two English translations**, base = French. Committed as
[`22-verne-trilingual-graph`](../conformance/cases/22-verne-trilingual-graph/) (`fr-5097`, `en-mercier`,
`en-walter`).

### What the engine reported (abridged apparatus, as first recorded)

```
CRITICAL APPARATUS  (base = fr-5097.txt)
0 L'année]  THE en-walter; The en-mercier
2 fut]      was en-mercier en-walter
3 marquée]  marked en-walter; signalised en-mercier
6 événement] bizarre en-walter; remarkable en-mercier
…
```

### Reading the result — an instructive *negative*

The graph is **deterministic and stable**, but it aligns the witnesses **positionally**, not semantically:
French `marquée` (position 3) is grouped with English `marked`/`signalised` because they sit at the same
*place*, not because the engine understands them as equivalents. This is the expected — and paper-worthy —
**limit of base-anchored progressive alignment when witnesses do not share a lexicon**: the anchors are
unique shared *word-forms*, and French and English share almost none, so the spine degrades to positional
correspondence.

**Why this matters (and for the Verne corpus specifically).** It says, concretely, that **cross-language
collation needs a different anchoring strategy** — translation-aware anchors (a bilingual lemma map, or
sentence-aligned parallel text) rather than shared surface forms. For a Verne corpus collating French
sources against English translations, the substantive engine as-is is the right tool *within* a language
(Case 5, and Case 4 across two translations of the *same* language) but not *across* the French↔English
boundary without that added alignment layer. A clean, early finding that shapes the corpus architecture.

> **Resolved (B10 + B14, 2026-07-06).** The prescription above is now implemented: a **`TranslationLexicon`**
> (bilingual equivalence groups, applied to alignment keys only) plus the **peer-MSA merge** re-collates these
> same three witnesses with correctly-paired slots — `L'année] year en-mercier en-walter`,
> `marquée] marked en-walter; signalised en-mercier` — each slot showing the per-witness renderings, and the
> two translations grouping onto shared readings where they agree. Pinned as conformance case
> [`29-verne-trilingual-peer`](../conformance/cases/29-verne-trilingual-peer/) (lexicon inline in its
> meta.json). This case (22) stays as recorded: it pins the honest *without-lexicon* negative the fix is
> measured against. *Residual:* single-token noun–adjective inversions (`phénomène inexpliqué` vs `mysterious
> phenomenon`) are an alignment tie and can pair one slot off.

---

## Case 7 — Walt Whitman, *Song of Myself* — N-witness across three editions

### The witnesses

The N-witness case the variant graph was actually *designed* for — **one author, three editions of one
work**: the shared opening three stanzas in **1855, 1860 and 1891**, base = 1855. Committed as
[`23-whitman-three-editions`](../conformance/cases/23-whitman-three-editions/). The text genuinely evolves
across the three: 1855 `I celebrate myself,` stays in 1860, then becomes `I celebrate myself, and sing
myself,` in 1891; the **1860 edition adds section numbers** (`1.`/`2.`/`3.`) and capitalises `Soul`; the
four-dot 1855 ellipses become an em-dash (1860) then a comma (1891). The 1855/1860 witnesses are
OCR-corrected against canonical transcriptions (authentic edition features retained); 1891 is verbatim.

### What the engine reported

The **pairwise** reports track the evolution exactly:

```
ed1855 vs ed1860: 3 variant(s)   — INSERTION “1”, “2”, “3”  (the 1860 section numbers)
ed1860 vs ed1891: 4 variant(s)   — DELETION “1”/“2”/“3” (numbers dropped) + INSERTION “and sing myself”
```

As first written, the **N-witness apparatus** printed `(no points of variance)`. **After B6c it now surfaces
the insertions as inserted nodes** — the 1860 section numbers and the 1891 `and sing myself`, each with the
base (and the editions that omit it) reading `∅`:

```
-1  ∅]  1  ed1860           (a section number inserted before all base text)
 2  ∅]  and sing myself  ed1891
22  ∅]  2  ed1860
47  ∅]  3  ed1860
```

### Reading the result

Two findings, one positive and one a limitation that this case motivated and B6c then closed:

- **Positive — real edition evolution tracked correctly.** Pairwise, the engine cleanly attributes the 1860
  section-number additions and their later removal, plus the 1891 `and sing myself` insertion — typed and
  located. (An incidental tokeniser observation: the numerals `1`/`2`/`3` are treated as word tokens, since
  they are alphanumeric.)
- **Limitation made concrete, then resolved — the pairwise/graph gap (B6c).** The shared spine agrees against
  the 1855 base, and the real *differences* here are either accidentals (the em-dash/comma/`Soul` are
  punctuation/case → folded) or **pure insertions/deletions**. Originally these weren't anchored into the
  base-anchored graph, so the apparatus under-reported what the pairwise engine plainly saw — the **same B6c
  gap as Case 2, on a genuine three-edition set**. **B6c now anchors pure insertions as inserted nodes**
  (above), so the apparatus surfaces them; the remaining generalisation (recurring-word/N-witness *moves*) is
  the full token-graph merge, B11.

---

## Case 8 — Alexander Pushkin, *Я вас любил* — Cyrillic tokenisation

### The witnesses

A **third script family**. Pushkin's eight-line *Я вас любил…* (1829) in Cyrillic: witness `canonical`
(verbatim, Russian Wikisource) and witness `variant` (one controlled, documented substitution,
`искренно`→`сердечно`, on line 7). Committed as [`24-pushkin-cyrillic`](../conformance/cases/24-pushkin-cyrillic/).

### What the engine reported

```
canonical.txt vs variant.txt: 1 variant(s)
  [1] SUBSTITUTION
      canonical.txt: “искренно” @ p.1 · line 7 · word 5
      variant.txt:   “сердечно” @ p.1 · line 7 · word 5
```

### Reading the result

The Cyrillic was **genuinely tokenised**: the engine counted through the Russian words to locate the
substitution at line 7, word 5, and typed it correctly. With Greek (earlier in the corpus) and French
diacritics/elisions, that is **three script families** the space-delimited tokeniser handles. The honest
boundary, stated in the case's `meta.json` and worth stating in the paper: this validates **alphabetic
non-Latin scripts**; **scriptio continua** scripts with no inter-word spaces (CJK) would collapse a line
into one token and remain a known tokeniser limitation (B6), not claimed here.

---

## Case 9 — Walt Whitman, *Calamus* cluster — a *found* poem-cluster transposition

### The witnesses

The genuine authorial move that Case 3 could only *approximate*. Whitman's documented rearrangement across
editions of *Leaves of Grass* is at the level of **whole poems and clusters** — "the incessant rearrangement
of his poems in various clusters," regrouped edition to edition — not lines within a passage. This case tests
the engine's transposition feature on exactly that granularity, on **verbatim** text.

Each poem of the 1860 "Calamus" cluster is represented by its intact real opening lines. Witness **`ed1860`**
is the 1860 (third-edition) order of the first five numbered *Calamus* poems:

| 1860 | poem (opening line) |
|------|---------------------|
| Calamus 1 | *In paths untrodden,* |
| Calamus 2 | *Scented herbage of my breast,* |
| Calamus 3 | *Whoever you are holding me now in hand,* |
| Calamus 4 | *These I singing in spring collect for lovers,* |
| Calamus 5 | *States! / Were you looking to be held together by lawyers?* (later titled "For You O Democracy") |

Witness **`ed1867`** is the same poems in Whitman's **resequenced** cluster: the whole *States!* / "For You
O Democracy" poem (1860 Calamus 5) is **relocated to follow the "In paths untrodden" proem**, the other four
poems intact and in order. That is a **found, poem-scale relocation** — not a constructed line move. Committed
as [`27-whitman-calamus-cluster`](../conformance/cases/27-whitman-calamus-cluster/).

### What the engine reported

```
ed1860 vs ed1867: 1 variant(s)
  [1] TRANSPOSITION (moved)
      ed1860: “States ! Were you looking to be held together by lawyers ? By an agreement on a paper ? Or by arms” @ p.1 · lines 13–15 · words 1…10
      ed1867: “States ! Were you looking to be held together by lawyers ? By an agreement on a paper ? Or by arms” @ p.1 · lines 4–6 · words 1…10
```

(Substantive apparatus: *(no points of variance)* — the text is identical; only the order changed.)

### Reading the result

Exactly right, and at the granularity the scholarship says is the *real* shape of Whitman's revision: **one
`TRANSPOSITION`** of the entire relocated poem (base lines 13–15 → compared lines 4–6), **`certain`**
confidence, reported as a single move rather than a deletion of three lines here + an insertion of three lines
there. Because nothing but the order changed, the substantive apparatus correctly shows no points of variance
— the located transposition carries the whole story. This is contribution-#1 behaviour (located
transposition) demonstrated on a **found, multi-poem** authorial rearrangement, discharging the future-work
note the Case-3 caveat left open: the poem/cluster move is not just describable, it is *detected*.

---

## Implications for the engine and the paper (across all nine cases)

1. **All four variant types verified on real text.** Across the nine cases the engine produced the correct
   typed result for *substitution* (Cases 1, 4, 8), *insertion* (Cases 2, 7), *transposition* (Case 3
   line-scale, **Case 9 poem/cluster-scale — a found authorial move**), and the correct *null* result where
   witnesses agree substantively (Case 5, and Case 9's identical-text-reordered apparatus) — on prose, verse,
   two translations, three editions, and three scripts. The crafted-corpus claims (typed variants,
   reworded-clause-as-one-substitution, located transposition) **hold on out-of-distribution text**, with no
   false positives or churn.
2. **The engine generalises beyond authorial revision — within a language.** It produces a clean, located
   apparatus for **translation collation** (Case 4) and handles **three scripts** — Greek (earlier), French
   diacritics/elisions (Case 5), and Cyrillic (Case 8). This broadens the applicability claim (edition
   collation *and* translation comparison *and* multilingual alphabetic text).
3. **…but cross-language N-witness collation needs translation-aware anchoring (Case 6).** The trilingual
   French+English graph aligns witnesses *positionally* because French and English share almost no
   word-forms to anchor on. A clear, paper-worthy **limit of base-anchored progressive alignment**: across
   a language boundary the engine needs bilingual/parallel-text anchors, not shared surface forms. (Within a
   language — Cases 4, 5, 7 — it is fine.) This directly shapes the planned Verne corpus architecture.
4. **The N-witness graph works on real editions; the insertion under-report it surfaced is now fixed (Cases
   7, 2 — B6c, resolved).** On a genuine three-edition Whitman set the *pairwise* engine tracks the evolution
   exactly (1860 section numbers added then dropped; `and sing myself` inserted). Originally the base-anchored
   *apparatus* printed "(no points of variance)" because pure insertions weren't graph-anchored — the case
   that motivated **B6c**. B6c now emits each pure insertion as an *inserted node* (anchored after the base
   token it follows; carriers read the text, everyone else `∅`), so the apparatus/synopsis surface the added
   passages. It was the smallest slice of — and de-risks — the fuller token-graph merge (B11), which
   remains the complete fix for the *move* classes.
5. **Genuine transposition is a matter of *granularity*, and the engine catches it at the granularity that
   actually occurs (Cases 3 + 9).** Surveying Whitman 1855/1860/1891 found substitutions and merges but no
   clean *line* move; the documented Whitman rearrangement is at **poem/cluster** granularity (the "Calamus"
   cluster resequenced between 1860 and 1867). Case 3 demonstrates the feature with a controlled line move as
   a bounded control; **Case 9 now supplies the *found* poem-cluster transposition** — a whole "Calamus" poem
   relocated between the 1860 and 1867 editions, which the engine reports as one `certain` `TRANSPOSITION`.
   So the feature is verified on both a controlled line move *and* a genuine authorial multi-poem move; the
   "needs multi-poem witnesses, future work" note from Case 3 is discharged.
   *(Engine fix, 2026-06-30: a reported case — `the well-known author` → `the author is well known`,
   where `author` MOVED — was mis-reported as delete+insert because the anchor pass needs n ≥ 2-gram
   landmarks and cannot see a lone move. A conservative displaced-reading post-pass now recovers single/short
   moves as transpositions, with a `certain`/`likely` confidence; corpus case `25-single-word-move` pins it,
   and it also corrected cases 04/05. The uniform fix for the whole move class is the token-graph redesign,
   backlog B11. See DEVELOPMENT_LOG 2026-06-30 and ALGORITHMS §6.1.)*
6. **Tokenisation hardening (B6 — done; scriptio continua still bounded).** Case 1's `dun white`→`dun-white`
   was a *tokenisation* artifact (a spurious substitution); **B6 fixed it** — intra-word hyphenation is now
   folded as an accidental (the tokeniser splits hyphenated compounds under substantive normalisation), and
   Case 1 now collates as *no variants*. Cases 5 and 8 show French elision and Cyrillic already handled. The
   remaining boundary is **scriptio continua** (CJK): the space-delimited tokeniser would collapse such a
   line into one token — explicitly bounded by the corpus rather than left vague.
7. **Punctuation as a first-class accidental — done (B6b, 2026-06-30).** Punctuation-only changes were
   invisible even with `--accidentals` (Case 1 commas/`:`→`;`/dash; Case 2 four-dot ellipses; Case 5 the
   French comma; Case 7's em-dash↔comma). The opt-in **`recordPunctuation`** overlay now reports them as
   accidentals without touching the substantive apparatus — on the Frankenstein passage it surfaces the four
   punctuation changes the substantive view hides (incl. the `dun white`→`dun-white` hyphen). Pinned as
   conformance case `26-frankenstein-diplomatic` beside the substantive case 17; see ALGORITHMS §6.2.

## Reproducing these studies

```sh
# Case 1 — Frankenstein 1818 vs 1831:
swift run collate-demo docs/conformance/cases/17-frankenstein-creation-scene/{1818,1831}.txt
# Case 2 — Whitman Song of Myself 1855 vs 1891:
swift run collate-demo docs/conformance/cases/18-whitman-song-of-myself/{1855,1891}.txt
# Case 3 — Whitman transposition (semi-synthetic moved line):
swift run collate-demo docs/conformance/cases/19-whitman-transposition/{A-1891,B-moved}.txt
# Case 4 — Verne translation collation (Mercier vs Walter):
swift run collate-demo docs/conformance/cases/20-verne-translation/{mercier,walter}.txt
# Case 5 — Verne French editions (tokeniser):
swift run collate-demo docs/conformance/cases/21-verne-french-editions/{ed5097,ed54873}.txt
# Case 6 — Verne N-witness cross-language graph (French + 2 English):
swift run collate-demo docs/conformance/cases/22-verne-trilingual-graph/{fr-5097,en-mercier,en-walter}.txt
# Case 7 — Whitman N-witness three editions (1855/1860/1891):
swift run collate-demo docs/conformance/cases/23-whitman-three-editions/{ed1855,ed1860,ed1891}.txt
# Case 8 — Pushkin Cyrillic tokenisation:
swift run collate-demo docs/conformance/cases/24-pushkin-cyrillic/{canonical,variant}.txt
# Case 9 — Whitman found poem-cluster transposition (Calamus, 1860 vs 1867):
swift run collate-demo docs/conformance/cases/27-whitman-calamus-cluster/{ed1860,ed1867}.txt
```

Each witness's provenance is recorded in the case's `meta.json` (including the OCR-correction notes for the
Whitman 1855/1860 witnesses and the controlled-edit caveats for Cases 3 and 8 — Case 9 is a *found* move,
no caveat). All nine are locked as conformance goldens.

> **On scope.** These nine cases *exercise* the engine across variant types, kinds of variation, witness
> counts, and three scripts, and they motivate B6/B6b/B6c; they are not a quantitative evaluation (the
> paper's measured numbers come from the benchmark harness, B3). Natural follow-ons, now sharpened by the
> findings above: (a) *done (Case 9)* — a **found** poem-cluster transposition (the 1860→1867 "Calamus"
> resequencing, the granularity at which authorial moves actually occur); (b) **translation-aware anchoring**
> for cross-language collation (Case 6's lesson), the key enabler for a French↔English Verne corpus; (c)
> *done (B6c)* — the N-witness apparatus now surfaces pure insertions (Cases 2/7) via inserted nodes; the
> remaining generalisation is the full **token-graph merge** (B11) for recurring-word/N-witness *moves*; and
> (d) a scriptio-continua (CJK) case once the tokeniser supports it.
