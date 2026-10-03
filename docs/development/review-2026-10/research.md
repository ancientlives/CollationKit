# CollationKit: proposed research agenda for the next phase

*Prepared 2026-10-03. This was a read-only review of the repository (docs as of the 2026-07-24 log entries:
222 tests, 29 goldens, asserted false moves 0 with 11 unasserted `likely` residuals across the four Verne
full-novel pairs). The field survey used web sources, and every reference in §D was checked against a publisher,
ACL Anthology, PubMed or author page. §D marks which ones were fully fetched.*

---

## 0. The admissibility bar every topic below is held to

Every proposal has to pass the project's own constraints, taken from RESEARCH_INTRO §3/§4.1, PAPER_NOTES
Appendix A and ALGORITHM_SURVEY Part II:

1. **Pure function of (witnesses + declared configuration).** With a feature disabled, the output must be byte-identical
   to today's. If a feature changes alignments, it lands as an opt-in preset or strategy behind an existing seam
   (`CollationStrategy`, scoring presets).
2. **Measured vs. judged.** A model may *add anchoring evidence* or *grade confidence*. It may never add, remove
   or rewrite a reading.
3. **ML as a declared sidecar artifact.** This document recommends one architectural pattern for every ML
   topic, and it reuses the `TranslationLexicon` and `no_collate` precedent. Any model runs **offline,
   outside the engine**. It emits a versioned JSON artifact: scores quantised to integers, plus the model id,
   the weights SHA-256 and the runtime. The engine consumes that artifact as a declared input, just as it
   consumes a lexicon. The engine stays pure Swift with zero dependencies. Reproducibility then reduces to
   "same artifact in, same apparatus out", and the artifact can be audited and diffed. This sidesteps
   floating-point and batch non-determinism in model inference, which is real but fixable
   (Thinking Machines/He 2025, [R46]), because the engine never runs the model.
4. **Calibrate across corpora, not on one.** The 2026-07-24 recalibration showed what happens otherwise: a gate
   fit on earth-to-moon admitted all 48 moves on the other pairs. Any new tunable has to be validated
   leave-one-pair-out.

---

## A. Research topics

The ten topics are grouped by track. Each one lists its question, why it matters here, a first experiment,
effort, risk, what it builds on, and 2–4 references.

### Track 1: Engine / algorithms

#### E1. Locally-collinear blocks and maximal unique matches as one principled move criterion

- **Question.** Can the three hand-calibrated false-move gates be subsumed by a single
  structural criterion from comparative genomics? The three gates are the displacement gate, the rarity/locality
  gate (`localMoveTokens = 80`) and the distinctiveness gate (base 10 / free 14 / per 18). The candidate criterion is
  **locally collinear blocks (LCBs)** with a minimum block weight, as in Mauve's greedy breakpoint elimination, with
  anchors taken as **maximal unique matches (MUMs)** from a suffix array rather than fixed-n grams. The aim is to
  get there with fewer constants that are not specific to one corpus.
- **Why here.** The project's hardest-won algorithms are three gates whose constants were tuned on one corpus,
  then re-tuned on four (DEVELOPMENT_LOG 2026-07-15/16/24). The log's key finding is that *grown* block
  length plus locality is the only separating signal, and raw pin length does not separate. A MUM is
  essentially the grown exact block, known *at anchor time*. ALGORITHM_SURVEY Part II #5 already speculates that
  MUM length "might partially subsume the distinctiveness gate". Mauve's LCB weight is the genomics version of
  "a block must be long enough to justify a breakpoint". The engine's moves are block moves in Tichy's sense,
  and optimal edit distance with moves is NP-complete (Shapira & Storer). The research question is therefore
  which principled *heuristic* criterion to use, not whether an exact optimum exists.
- **First experiment (offline, no engine change).** Re-instrument the 2026-07-24 measurement pass to dump every
  anchor pin and grown block for the four `full/` pairs and the 29 goldens. In a script, compute (a) MUMs from a
  suffix array over interned tokens and (b) Mauve-style LCBs as a function of minimum weight *w*. Plot false moves
  (the labelled 48) and genuine moves (Calamus; cases 04/05/19/25; the sentence-swap) against *w*. Success means
  one *w*, ideally expressed relative to witness size, that keeps every genuine move, matches or beats 48→11,
  and survives leave-one-pair-out. A null result also has value: it would show that the gates' extra structure is necessary.
- **Effort.** 3–4 weeks for the offline study, plus 4–6 weeks if it graduates to an opt-in preset.
- **Risk.** Medium. It reshapes the anchor set, so goldens would move, and the work has to land behind a preset.
  The offline study is risk-free.
- **Builds on.** ALGORITHM_SURVEY #5 (suffix automaton), #10 (the gates); PAPER_NOTES §4.5–4.6; B15 (witness
  profiles: the MUM index is a natural part of the profile).
- **Refs.** Darling et al. 2004 (Mauve, LCBs) [R16]; Delcher et al. 1999 (MUMmer) [R17]; Tichy 1984 [R18];
  Shapira & Storer 2002 [R19]. Bourdaillet & Ganascia 2007 [R20] is the closest *textual* precedent (MEDITE,
  block alignment with moves, now an experimental CollateX algorithm [R2]).

#### E2. Partial-order alignment (POA) as a third merge strategy, with guide-tree order and affine gaps

- **Question.** Does aligning each witness against the *whole* growing token graph, using partial-order alignment
  (Lee et al.), close the documented gap between `.peerMSA` and CollateX? Today `.peerMSA` aligns against the *linear
  consensus spine*. Two further questions follow: does a neighbour-joining guide-tree merge order beat sorted-id
  order, and do affine gaps (Gotoh) reduce fragmentation on large cuts?
- **Why here.** COMPARISON.md and PAPER_NOTES §5.3/§11 name "linear consensus spine vs full-graph alignment" as
  the honest remaining shortfall relative to CollateX, and nested moves stay single-level. POA is exactly the
  "DP directly against a DAG" algorithm. It is deterministic, it has a modern exact gap-affine A* form
  (POASTA 2025), and it slots in as a **third `CollationStrategy`**, so no existing golden moves. The guide tree
  approximates a stemma, which gives it a second payoff for textual scholarship (ALGORITHM_SURVEY #6).
- **First experiment.** Prototype POA (linear gaps first) behind the seam. Run a **controlled three-strategy
  ablation** (base-anchored / peer / POA) on the N-witness goldens (08, 16, 22/29, 23, 28) and on all four Verne
  chapter-1 excerpts. Report agreement-group purity, apparatus entry count, and recurring-word move confidence.
  Then add Gotoh affine gaps as a POA option and measure fragmentation on the Whitman 1855→1891 stanza insertion
  and on Mercier's abridgement cuts against Walter.
- **Effort.** 6–8 weeks.
- **Risk.** Contained, because it is a new strategy pinned by its own strategy-tagged goldens. Neighbour-joining
  ties must break deterministically, as ALGORITHMS §9 requires.
- **Builds on.** B13/B14 seam; ALGORITHM_SURVEY #4 (affine), #6 (guide tree); B18 (nested moves would live here).
- **Refs.** Lee, Grasso & Sharlow 2002 [R21]; van Dijk et al. 2025 (POASTA) [R22]; Gotoh 1982 [R23];
  Saitou & Nei 1987 [R24] / Thompson, Higgins & Gibson 1994 (progressive MSA with a guide tree) [R25].

### Track 2: ML / semantic layer (additive and auditable only)

#### M1. Sentence-aligned anchor layer for French↔English (B17): classical first, embeddings second

- **Question.** Does aligning sentences before aligning tokens remove the `TranslationLexicon` residual?
  The residual is noun–adjective inversions that tie in NW (`phénomène inexpliqué` / `mysterious phenomenon`).
  Does it also make full-novel French↔English collation feasible? And how much does an embedding aligner buy over
  a deterministic length+lexicon aligner on *literary, abridged* translation?
- **Why here.** This is the documented route to the Verne digital corpus (CASE_STUDY Case 6, "an instructive
  negative"; BACKLOG B17). The 2023 CHR study of literary and classical translations is a sharp warning that
  carries over directly. In that study, LaBSE+Vecalign worked best, but all aligners degraded when the translation was not
  mostly 1:1 and order-preserving. Mercier's 1872 translation is a heavy abridgement, so the classical baseline
  matters. LERA's two-stage design (segment alignment, then detailed comparison) and its 2025 resegmentation
  result show that this architecture is established in collation tooling.
- **First experiment.** (1) Add the full French *Vingt mille lieues* (PG #5097, already used in conformance case 21)
  to `editions/corpus/20000-leagues/full/`. (2) Hand-align a gold set covering two chapters of French with Mercier
  and with Walter (about 300 French sentences, and n:m links allowed). Two annotators give an agreement figure.
  (3) Compare Gale–Church, Hunalign (seeded with the existing `TranslationLexicon` as its dictionary),
  Vecalign+LaBSE, Bertalign and SentAlign, using strict/lax link F1 and recall on 1–0 (omitted) sentences.
  (4) Feed the best aligner's output to the peer merge **as a sidecar seeding-anchor artifact** (§0.3) and count
  inversion-tie errors on case 29 and a sampled chapter. Gate for adoption: improvement without any reading change.
- **Effort.** 6–8 weeks, including gold annotation.
- **Risk.** Medium. Abridgement may cap recall for every aligner, which would itself be a publishable negative.
  Because the layer is additive, a nil artifact gives byte identity.
- **Builds on.** B10/B17; ALGORITHM_SURVEY #7; CASE_STUDY Cases 4–6; `editions/` build scripts.
- **Refs.** Gale & Church 1993 [R26]; Varga et al. 2005 (Hunalign) [R27]; Thompson & Koehn 2019 (Vecalign)
  [R28]; Liu & Zhu 2023 (Bertalign, literary zh–en) [R29]; Feng et al. 2022 (LaBSE) [R30]; Craig et al. 2023
  (limits on literary/classical translations) [R31]; Dähne, Ritter & Molitor 2025 (LERA resegmentation) [R7].

#### M2. Adjudicating the irreducible near-diagonal residual: containing-unit correspondence

- **Question.** For a short block that passes the gates only because it sits near the diagonal, does an
  **independent** signal separate genuine local hops from coincidences when geometry cannot? Examples are
  "firearms" (genuine) and "off the rocks" / "imagine that the" (coincidences). The proposed signal is
  *containing-unit correspondence*: do the sentences (or clauses) containing the block in A and in B correspond to
  each other, measured on the tokens *outside* the block?
- **Why here.** RESEARCH_INTRO §4.1 and ALGORITHM_SURVEY #9 frame this as the one defensible place for a learned
  signal, with a documented negative result to beat. Word rarity, phrase rarity, flank context, co-move,
  dev/len and content-word ratio are all ruled out (log 2026-07-24). Containing-unit correspondence is a *different
  measurement* from the ruled-out flank context. Flank context compares the block's token neighbours, which a
  genuine relocation also loses. This signal asks whether the enclosing *unit* is the same unit. In a coincidence it is not:
  "we ought always to *treat an adversary*…" vs "we ought always to *put a little art*…". In a within-sentence
  hop it is. Long relocations like Calamus are already `certain` by length, so the signal only has to work on
  short blocks, which is exactly the residual.
- **First experiment.** Build it in three tiers, cheapest and most deterministic first. **Tier 0:** a purely lexical
  score with no ML, the Jaccard similarity of comparable keys in the two containing sentences minus the
  block, using sentence boundaries from the tokeniser's punctuation. **Tier 1:** the M1 sentence aligner's verdict
  on whether the two containing sentences are linked. **Tier 2:** cosine similarity of pinned SBERT/LaBSE
  embeddings, delivered as a sidecar artifact. Evaluate all three on the V1 gold move set with AUROC and with the
  separation margin at a threshold, using leave-one-pair-out. Adopt only as a **confidence refinement**, and
  only for the `likely` residual. A signal may raise or lower a move's confidence and must show its evidence
  (for example, "containing sentences correspond: 0.82"). It never creates or deletes a move. Prefer the
  simplest tier that works, and an interpretable rule over a fitted model.
- **Effort.** 4–6 weeks, after V1 exists.
- **Risk.** High scientific risk, since it may fail like rarity did, but low engineering risk because it is additive and
  only touches confidence. The positive class (genuine short local moves in long witnesses) is tiny, which is why
  V1 and V2 come first.
- **Builds on.** ALGORITHM_SURVEY #9; PAPER_NOTES §4.5.2; `anchorMoveIsCertain`; B16 (corpus commonness is a
  complementary, explicitly confidence-only signal).
- **Refs.** Rudin 2019 (prefer interpretable models in high-stakes settings) [R32]; Reimers & Gurevych 2019 (SBERT)
  [R33]; Guo et al. 2017 (calibration: a score is not a probability until calibrated) [R34]; He / Thinking
  Machines 2025 (sources of inference non-determinism) [R46].

#### M3. Meaning-preserving vs. meaning-changing substitutions: evaluation first, model second

- **Question.** Can a substitution be labelled reliably as paraphrase (same sense, reworded) or as a change of sense,
  and what *is* ground truth for this in an edition? The question splits into two parts: first, whether
  trained annotators agree; second, whether any pinned embedding or STS score tracks that agreement.
- **Why here.** This is the flagship semantic layer, specified but not built (PAPER_NOTES §11; ALGORITHM_SURVEY #10).
  RESEARCH_INTRO §4.1 says plainly that "the most difficult and most publishable part … is evaluation". The project
  already has ideal material: coalesced phrase-level substitutions across translations (Case 4's 13; ~21.5k
  variants on the 20,000 Leagues full pair) and authorial revisions (Frankenstein, Whitman).
- **First experiment.** Adapt a published paraphrase typology (Vila et al.) to a 3–5-way editorial scheme, for
  example identical-sense / register-or-style / inflection-or-morphology / sense-shift / addition-omission. Then
  annotate a stratified sample of about 300 substitutions from the Verne full pair and the Whitman/Frankenstein
  goldens, with two or three annotators, ideally one textual scholar, and report Krippendorff's α. *Only then* score
  pinned SBERT/LaBSE cosine and a lexical baseline against the adjudicated labels. The deliverable is a sidecar
  score column, never a change of variant type.
- **Effort.** 6–10 weeks, dominated by annotation and adjudication.
- **Risk.** Medium–high. Low α would be a legitimate finding, because it would mean that "paraphrase" needs to
  be a graded score and not a label. Determinism risk is nil under the sidecar pattern.
- **Builds on.** ALGORITHM_SURVEY #10, #11 (the morphological/lemma subclass belongs in the normaliser, which
  is a deterministic sub-result worth splitting out); TranslationLexicon pattern.
- **Refs.** Vila, Martí & Rodríguez 2014 [R35]; Vila et al. 2015 (paraphrase-type annotation and agreement) [R36];
  Wahle, Gipp & Ruas 2023 (models detect paraphrase but not fine-grained types) [R37]; Artstein & Poesio 2008
  [R38].

### Track 3: Visualisation / HCI

#### H1. Communicating calibrated move uncertainty to an expert who can overrule it

- **Question.** How should the viewer present a `likely` move, and does the presentation change *appropriate reliance*?
  Appropriate reliance here means accepting genuine moves and rejecting coincidences, rather than simply raising trust.
- **Why here.** RESEARCH_INTRO §4.3 calls this "the most demanding single question" and notes that the viewer renders the
  certain/likely distinction "quite thinly". The project has an unusual asset for a study like this: **stimuli with
  known ground truth**. These are the 11 audited residual coincidences, the genuine moves, and the per-move geometry
  (block length, diagonal deviation, earned tolerance, witness-floor rule) that explains *why* each is `likely`.
  HCI work warns against a naive "show confidence plus explanation" design. Confidence scores calibrate trust but do
  not by themselves improve joint accuracy (Zhang et al.). Explanations raise acceptance whether or not the AI is
  right (Bansal et al.). Cognitive forcing (asking for the user's judgement first) reduces over-reliance (Buçinca et al.).
- **First experiment.** A within-subjects study with 12–20 participants, ideally a few textual scholars plus
  graduate students. Each participant judges about 30 proposed moves drawn from the Verne pairs, under three conditions:
  (a) the current badge; (b) an evidence card showing block length, deviation vs earned tolerance as a small
  dot-on-diagonal glyph from the Alignment map, the confidence rule in plain language, and both containing sentences;
  (c) the same card plus forcing, where the participant commits a judgement before the engine's confidence is revealed. Measures: accuracy against ground
  truth, over- and under-reliance rates, time, and self-reported confidence calibration. Design the evaluation with
  the Hullman et al. taxonomy so it is not only a satisfaction study.
- **Effort.** 5–7 weeks: 2 weeks to build, 1 week to pilot, 2–3 weeks to run and analyse. Needs ethics approval if run at a university.
- **Risk.** Recruitment of real editors is the main risk. Students make a reasonable pilot population, but the paper must
  state that limitation.
- **Builds on.** PAPER_NOTES §8.1 (Alignment map, confidence metric); `anchorMoveIsCertain`; VIEWER_UX_PLAN.
- **Refs.** Lee & See 2004 [R39]; Zhang, Liao & Bellamy 2020 [R40]; Bansal et al. 2021 [R41]; Buçinca et al.
  2021 [R42]. For uncertainty display and evaluation design: Hullman et al. 2019 [R43] and Kay et al. 2016 [R44].

#### H2. Task-based evaluation of the eight views, the Alignment-map trust claim, and accessibility

- **Question.** For defined tasks, which views do readers actually use, and with what success? The tasks are: find the
  largest revision, verify that an alignment is sound, and say what changed in passage X. Does the Alignment map let
  a reader *detect a bad alignment*, or does it merely reassure them? And can the viewer meet WCAG 2.2 Level A
  for its colour-heavy encodings?
- **Why here.** RESEARCH_INTRO §4.2 states that no view has been evaluated with users and that accessibility is
  "largely unexamined". VIEWER_UX_PLAN contains no accessibility work. The field's own surveys report the same gap:
  Yousef & Jänicke catalogue 40 text-alignment visualisations, and Birnbaum & Haentjens Dekker's 2024 alignment-ribbon
  paper includes no user evaluation. A CHI'26 survey of humanities visualisation evaluation finds that studies
  over-rely on a single method and recommends triangulating several.
- **First experiment.** (1) **Seeded misalignment stimuli with known truth.** Regenerate `collation.html` for one
  Verne pair using the pre-displacement-gate engine (pre-2026-07-08, max deviation 722k chars) and the current
  engine. Participants judge which alignment is sound and point to where it fails, comparing the map, parallel and
  graph views. (2) A task battery of 6–8 tasks across the views, with time and accuracy logged and a think-aloud
  protocol. (3) An accessibility audit against WCAG 2.2 SC 1.4.1 (use of colour) and 2.1.1 (keyboard). Recode variant
  types with an Okabe–Ito/Wong palette *plus* a redundant non-colour channel such as underline style or a glyph,
  and check reading order with VoiceOver. Frame the design claims with Munzner's nested model, so that the
  claims about abstraction and encoding are kept separate from the claims about algorithms.
- **Effort.** 4–6 weeks, with the accessibility fixes run in parallel at about 1–2 weeks.
- **Risk.** Low. The accessibility fixes are pure rendering changes, so goldens are unaffected because the HTML is not in
  the conformance corpus. The study design takes care.
- **Builds on.** PAPER_NOTES §8.1; VIEWER_UX_PLAN; the data-viz paper outline (log 2026-07-13b).
- **Refs.** Munzner 2009 [R45]; Lam et al. 2012 (seven scenarios) [R47]; Yousef & Jänicke 2021 [R12];
  Benito-Santos et al. 2026 [R48]. Also W3C WCAG 2.2 [R49] and Wong 2011 [R50]. For collation visualisation
  specifically: Bleeker et al. 2019 [R10], Birnbaum & Haentjens Dekker 2024 [R11] and Jänicke et al. 2015
  (TRAViz) [R9].

### Track 4: Interoperability / standards

#### I1. TEI P5 apparatus export (and later import) that is faithful to located transpositions and confidence (B12)

- **Question.** How can CollationKit's distinctive results be encoded in TEI P5 parallel segmentation without loss?
  Those results are the located, page-aware transposition, `withinTransposition` edits, `certain`/`likely`
  confidence, and page·line·word citation. Can an export→import round trip be byte-stable?
- **Why here.** BACKLOG and ALGORITHM_SURVEY #8 call this the biggest interoperability win. Two facts make it a research
  question as well as an engineering one. First, the TEI chapter itself says parallel segmentation "cannot … deal very
  gracefully with variants which overlap without nesting". For transpositions it suggests mutually exclusive `<app>`s
  linked by `@exclude` (and `copyOf`), which is exactly the category CollationKit's contribution lives in. Second, the
  RIDE review of Juxta Web Service, LERA and Variance Viewer found that every tool's TEI needed hand revision, and that
  "transposition is obviously an interpretative issue". CollateX itself keeps transpositions as links "superimposed" on
  the variant graph.
- **First experiment.** Export all 29 goldens to TEI (`<listWit>`, `<app>/<lem>/<rdg>`, `<rdgGrp>` for
  normalised-form groups, and `@exclude` pairs for moves). Carry confidence in a TEI-native attribute such as
  `@cert`, verifying the attribute class against the current ODD before relying on it. Carry the citation in
  `<witDetail>` or `@loc`. Validate against the TEI P5 4.12 schema, run the TEI Critical Apparatus Toolbox's
  "check your encoding", and render in the Versioning Machine. Then run CollateX on the same witnesses and
  compare the two TEI apparatuses mechanically. That turns COMPARISON.md's "where we differ" into numbers. Import
  comes later, with a round-trip property test (`import(export(c)) == c`).
- **Effort.** 4–6 weeks for export and the cross-tool comparison; 3–4 more weeks for import.
- **Risk.** Low, since this is a new renderer. Expect some judgement calls about encoding that need a TEI-literate reviewer.
- **Builds on.** B12; the `Apparatus`/`Synopsis` render models; `collation.schema.json`.
- **Refs.** TEI Consortium, P5 Guidelines ch. 13 (v4.12.0, 2026) [R1]; CollateX documentation [R2]; Roeder 2020
  (RIDE) [R5]; Dumont 2022 (RIDE, TEI CAT) [R6].

> **Side track (engineering, not research): B6 CJK tokenisation.** Use UAX #29 word boundaries with ICU's dictionary
> segmentation for Chinese and Japanese [R51, R52]. Treat the *segmenter version as declared configuration*:
> ICU dictionary updates change segmentation, which would silently change goldens. Pin the ICU data version in
> run metadata, or accept a user-supplied pre-segmented witness. The first option is convenient. The second is the
> purer choice and fits Appendix A.

### Track 5: Evaluation / benchmarks

#### V1. A labelled move-and-alignment gold standard with cross-corpus calibration protocol

- **Question.** What are the engine's move precision and recall on real text, by length and distance class? And do
  the current gate constants survive **leave-one-pair-out** validation?
- **Why here.** Every move decision since July is backed by hand-labelled populations scattered through the
  log: 26 + 90 + 48 + 11 cases and a handful of genuine moves. The 2026-07-24 entry draws the methods lesson
  ("a gate calibrated on a single corpus can encode that corpus's accidental geometry"). The field has the same gap. Nury & Spadini [R4] trace
  sixty years of collation tools, and none of the tools reviewed here (CollateX, LERA, Juxta, TRAViz) publishes a
  shared, machine-readable gold collation with move labels that could serve as a common benchmark. That is my
  reading of the sources, not a claim any of them makes. Turning the scattered labels into one versioned
  dataset is the precondition for E1, M2 and H1.
- **First experiment.** (1) Consolidate every move candidate the engine has ever emitted on the four full pairs. That
  means re-running the 2026-07-08, -16 and -24 constant sets to recover the historical candidates, and adding a
  sample of *rejected* near-diagonal blocks. (2) Two annotators label each candidate genuine, coincidence or
  unclear, with a short rationale, and report agreement. (3) Add genuine authorial-move sources so the positive class
  is not just Calamus. Candidates are the Whitman cluster editions, Frankenstein 1818/1831 full texts, and selected
  chapters of Darwin's *Origin* (six editions, 1859–1872), whose Online Variorum gives a scholarly cross-check.
  (4) Publish the set as `docs/conformance/moves/` with a JSON Schema, and add a harness that reports precision and
  recall by stratum, using leave-one-pair-out for every tunable.
- **Effort.** 4–5 weeks.
- **Risk.** Low. The main risk is scarce positives, which V2 compensates for.
- **Builds on.** B1/B2 (conformance and schema discipline), B4 (case studies), the 2026-07-24 instrumentation pass.
- **Refs.** Nury & Spadini 2020 [R4]; Artstein & Poesio 2008 [R38]; Bordalejo, Online Variorum of Darwin's
  *Origin* [R53].

#### V2. A synthetic "known-history" benchmark that maps the irreducible region (and closes B19)

- **Question.** Over a grid of (block length L, displacement D, witness size N, background substitution
  rate), where exactly does move detection fail? Is the "irreducible near-diagonal residual" a sharp boundary or
  a gradient?
- **Why here.** The irreducibility claim (PAPER_NOTES §11) is currently argued from a few points. A
  controlled surface would let the paper *show* it as a detection-probability heatmap over L×D, with the gate
  boundary overlaid. It is also the cheapest way to get thousands of known-positive moves for M2. Stemmatology has
  used artificial benchmark traditions since Roos & Heikkilä [R13] for exactly this reason: real ground truth is
  scarce. The same harness can add the adversarial all-repetition point the benchmarks lack (B19).
- **First experiment.** Extend `collate-bench` with a mutator over *real* Verne chapter text. The mutator relocates a
  block of L tokens by D, applies k random substitutions drawn from the other translation's vocabulary to mimic
  translation drift, and records the ground truth. Sweep L∈{1..30}, D∈{1..2000}, N∈{1k, 10k, 60k}. Record detected,
  `certain` and `likely` for each cell, plus false moves elsewhere. Add the B19 tiny-vocabulary point.
- **Effort.** 2–3 weeks.
- **Risk.** Low. Synthetic moves can be easier than real ones, so report results alongside V1 and never instead of it.
- **Builds on.** B3/B19; BENCHMARKS.md "honest limitations"; ALGORITHM_SURVEY Tier 1 #2.
- **Refs.** Roos & Heikkilä 2009 [R13]; Shapira & Storer 2002 [R19] (explains why the problem is defined
  heuristically).

---

## B. Recommended ordering

The principle is **measurement before mechanism**. The project's own record shows that its gates were right
only after a multi-corpus measurement. The first months should therefore build the instruments, and only then
spend effort on new algorithms or models.

| Phase | Weeks | Work | Why this order |
|---|---|---|---|
| **0: Instruments** | 1–5 | **V2** (synthetic benchmark plus B19), **V1** (gold move set and leave-one-pair-out harness), and **B15** witness profiles (cheap, and gives E1 its MUM/profile index) | Every later claim needs a labelled population and a cross-corpus protocol. V2 is quick and de-risks V1's scarce positives. |
| **0′: In parallel** | 1–6 | **I1** TEI export and **H2-a11y** (palette, redundant encoding, keyboard) | No golden risk, independent of everything else. I1 is the adoption win, and a11y is low-hanging and a prerequisite for any user study. |
| **1: Cheapest science** | 5–10 | **E1** offline LCB/MUM study, and the **M2 Tier 0** lexical containing-unit signal, both scored on V1 and V2 | Both are deterministic and zero-ML, and either may resolve part of the residual without a model. They directly test the open hypotheses in ALGORITHM_SURVEY #5 and #9. |
| **2: The additive-ML pattern, once** | 8–16 | **M1** sentence alignment (classical, then embedding), built as the first *sidecar artifact* with a pinned model hash | It establishes and reviews the §0.3 artifact pattern once, on the most clearly bounded ML problem. M2 Tier 1/2 and M3 then reuse it. |
| **2′: Human studies** | 10–18 | **H2** task study, then **H1** uncertainty study (stimuli from V1) | H1 needs V1's ground truth and H2's improved, accessible viewer. Run H2 first so H1 is not confounded by usability problems. |
| **3: Deeper engine and semantics** | 16+ | **E2** POA strategy (+ guide tree, affine), **M2 Tier 1/2**, **M3** paraphrase annotation | These are the largest and riskiest items, and they are better informed by Phases 0–2. M3's annotation can start earlier if an annotator is available. |

If only **three** things get done, do **V1, I1 and H1**. They yield one dataset paper, one adoption-enabling standard
export, and one HCI result that sits squarely on the project's stated intersection (RESEARCH_INTRO §4.3).

---

## C. What not to pursue yet, and why

1. **LLMs inside the collation loop.** That covers LLM-adjudicated readings, LLM-generated apparatus entries, and
   "ask the model if this is a move" at run time. All three violate the measured/judged separation and the
   pure-function contract. Batch-invariant kernels show that bitwise reproducibility is *achievable* [R46], but the
   project would then depend on a hosted model's version and serving stack for every future reproduction of an
   edition. If LLMs appear at all, they belong only *offline*, for example drafting annotation rationales for
   V1/M3 that humans adjudicate, and never in the artifact path.
2. **Learning gate constants or an end-to-end learned aligner.** Appendix A.2 points 3–4 apply: witness sets are
   unique to each work, and the data is tiny. The 2026-07-24 episode already showed a single-corpus fit
   failing. Constants should be *validated* across corpora (V1), not *learned*.
3. **Rarity, commonness or stop-word filters as move detectors.** This is a documented negative result: the phantoms
   were the *rarest* phrases. B16 commonness is acceptable only as a confidence refinement, as the backlog
   already says. Do not reopen it as a detector.
4. **Exact edit-distance-with-moves optimisation, or a full CollateX-style A* decision-graph search.** The exact
   problem is NP-complete [R19]. POA (E2) is the tractable, deterministic step toward full-graph alignment and
   should be tried first.
5. **Nested-move recovery (B18).** There is no real case in the corpus. Revisit it only if V1 or a new
   corpus surfaces one, and then inside E2's POA strategy.
6. **Stemmatology or phylogenetic inference as a product feature.** The available corpus consists of independent
   translations and authorial revisions, not scribal copying traditions, so a "stemma" of Verne translations is
   not meaningful. Phylogenetic methods [R13–R15] assume copying with shared errors. Use the guide tree only as a
   *merge order* (E2). Revisit if a manuscript tradition with many witnesses enters the corpus.
7. **Performance work: Rust port, SIMD, Fenwick LIS.** The performance work is not a bottleneck. Full novels collate in 2–15 s (editions README), and none of it
   advances either paper. The Fenwick LIS remains a good *onboarding* task, but it is not research.
8. **A native viewer, before the HTML viewer is evaluated.** H2 should first establish which views earn their place.
   Porting unevaluated views duplicates unknowns.
9. **In-witness revision layers (HyperCollate-style `<add>/<del>/<subst>`).** The hypergraph model [R8] is
   attractive, but it presupposes TEI *import* and diplomatic transcriptions that the corpus lacks. Defer until
   I1's import half exists and a manuscript use case appears.
10. **Image or OCR-level collation.** This is out of scope for a text engine whose inputs are clean witnesses.

---

## D. Bibliography

**Verification key.** **[F]** means the page or PDF was fetched and its metadata and content checked in this
review. **[S]** means the metadata (authors, title, venue, year, pages/DOI) was confirmed from publisher, ACL
Anthology, PubMed or author-page listings via web search, but the full text was not read. Nothing here is
cited from memory alone. One figure seen in a search snippet could not be traced to a primary source: a claimed
CollateX transposition-accuracy percentage on Darwin. It is therefore **not** cited.

### Collation tools, standards, visualisation of variance
- **[R1] [F]** TEI Consortium. *TEI P5: Guidelines for Electronic Text Encoding and Interchange*, ch. 13 "Critical
  Apparatus", Version 4.12.0 (2026-07-28). https://www.tei-c.org/release/doc/tei-p5-doc/en/html/TC.html
- **[R2] [F]** CollateX documentation (Dekker / Needleman–Wunsch / MEDITE algorithms; TEI, GraphML, JSON output;
  transpositions as superimposed links). https://collatex.net/doc/
- **[R3] [F]** Haentjens Dekker, R., van Hulle, D., Middell, G., Neyt, V., van Zundert, J. (2015). "Computer-supported
  collation of modern manuscripts: CollateX and the Beckett Digital Manuscript Project." *Digital Scholarship in the
  Humanities* 30(3):452–470. https://doi.org/10.1093/llc/fqu007
- **[R4] [S]** Nury, E., Spadini, E. (2020). "From giant despair to a new heaven: The early years of automatic
  collation." *it – Information Technology* 62(2):61–73. https://doi.org/10.1515/itit-2019-0047
- **[R5] [F]** Roeder, T. (2020). "Juxta Web Service, LERA, and Variance Viewer. Web based collation tools for TEI."
  *RIDE* 11. https://ride.i-d-e.de/issues/issue-11/web-based-collation-tools/
- **[R6] [F]** Dumont, B. (2022). "TEI Critical Apparatus Toolbox: Web-based tools for ongoing XML-TEI editions."
  *RIDE* 15. https://ride.i-d-e.de/issues/issue-15/teicat/ (tool by M. Burghart: http://teicat.huma-num.fr/)
- **[R7] [F]** Dähne, J., Ritter, J., Molitor, P. (2025). "Improving text collations by local text resegmentation."
  *Digital Scholarship in the Humanities* 40(2):477–486. https://doi.org/10.1093/llc/fqaf033
  (LERA: https://lera.uzi.uni-halle.de/)
- **[R8] [F]** Bleeker, E., Buitendijk, B., Haentjens Dekker, R., Neyt, V., Van Hulle, D. (2022). "Layers of Variation:
  a Computational Approach to Collating Texts with Revisions." *DHQ* 16(1).
  https://dhq.digitalhumanities.org/vol/16/1/000583/000583.html
- **[R9] [S]** Jänicke, S., Geßner, A., Franzini, G., Terras, M., Mahony, S., Scheuermann, G. (2015). "TRAViz: A
  Visualization for Variant Graphs." *DSH* 30(suppl_1):i83–i99. https://academic.oup.com/dsh/article/30/suppl_1/i83/365029
- **[R10] [S]** Bleeker, E., Buitendijk, B., Haentjens Dekker, R. (2019). "From graveyard to graph: Visualisation of
  textual collation in a digital paradigm." *International Journal of Digital Humanities*.
  https://link.springer.com/article/10.1007/s42803-019-00012-w
- **[R11] [F]** Birnbaum, D. J., Haentjens Dekker, R. (2024). "Visualizing textual collation: Exploring structured
  representations of textual alignment." *Balisage: The Markup Conference 2024*, Balisage Series vol. 29.
  https://balisage.net/Proceedings/vol29/html/Birnbaum01/BalisageVol29-Birnbaum01.html
- **[R12] [S]** Yousef, T., Jänicke, S. (2021). "A Survey of Text Alignment Visualization." *IEEE TVCG* 27(2).
  https://doi.org/10.1109/TVCG.2020.3028975
- Also consulted: **[F]** Nury, E. (2019). "Visualizing Collation Results." *Variants* 14.
  https://journals.openedition.org/variants/950 · **[S]** Schmidt, D., Colomb, R. (2009). "A data structure for
  representing multi-version texts online." *Int. J. Human-Computer Studies* 67(6):497–514.
  https://doi.org/10.1016/j.ijhcs.2009.02.001 · **[S]** Jänicke, S., Franzini, G., Cheema, M. F., Scheuermann, G.
  (2015). "On Close and Distant Reading in Digital Humanities: A Survey and Future Challenges." EuroVis STARs.
  https://doi.org/10.2312/eurovisstar.20151113 · **[S]** Versioning Machine 5.0 (Schreibman et al.).
  http://v-machine.org/documentation/ · **[S]** Classical Text Editor (S. Hagel). https://wiki.tei-c.org/index.php/Classical_Text_Editor
  · **[F]** Alrahabi, M., Wainstain, T. (2025). "Versus: an automatic text comparison tool for the digital humanities."
  LM4DH 2025, pp. 32–37. https://aclanthology.org/2025.lm4dh-1.3/

### Stemmatology / phylogenetics of texts
- **[R13] [S]** Roos, T., Heikkilä, T. (2009). "Evaluating methods for computer-assisted stemmatology using artificial
  benchmark data sets." *Literary and Linguistic Computing* 24(4):417–433. https://academic.oup.com/dsh/article/24/4/417/956763
- **[R14] [S]** Barbrook, A. C., Howe, C. J., Blake, N., Robinson, P. (1998). "The phylogeny of The Canterbury Tales."
  *Nature* 394:839. https://dora.dmu.ac.uk/items/e9910434-6aee-4d82-a011-9797da014277
- **[R15] [S]** Andrews, T. L., Macé, C. (2013). "Beyond the tree of texts: building an empirical model of scribal
  variation through graph analysis of texts and stemmata." *LLC* 28(4):504–521. https://doi.org/10.1093/llc/fqt032

### Sequence alignment, moves, MSA (transferable from bioinformatics and string algorithms)
- **[R16] [S]** Darling, A. C. E., Mau, B., Blattner, F. R., Perna, N. T. (2004). "Mauve: Multiple Alignment of Conserved
  Genomic Sequence With Rearrangements." *Genome Research* 14(7):1394–1403. https://genome.cshlp.org/content/14/7/1394
- **[R17] [S]** Delcher, A. L., Kasif, S., Fleischmann, R. D., Peterson, J., White, O., Salzberg, S. L. (1999).
  "Alignment of whole genomes." *Nucleic Acids Research* 27(11):2369–2376. https://mummer4.github.io/publications/MUMmer.pdf
- **[R18] [S]** Tichy, W. F. (1984). "The string-to-string correction problem with block moves." *ACM TOCS*
  2(4):309–321. https://doi.org/10.1145/357401.357404
- **[R19] [S]** Shapira, D., Storer, J. A. (2002). "Edit Distance with Move Operations." *CPM 2002*, LNCS 2373:85–98.
  https://link.springer.com/chapter/10.1007/3-540-45452-7_9
- **[R20] [S]** Bourdaillet, J., Ganascia, J.-G. (2007). "Practical block sequence alignment with moves." *LATA 2007*.
  https://www.researchgate.net/publication/220836141_Practical_block_sequence_alignment_with_moves
- **[R21] [S]** Lee, C., Grasso, C., Sharlow, M. F. (2002). "Multiple sequence alignment using partial order graphs."
  *Bioinformatics* 18(3):452–464. https://academic.oup.com/bioinformatics/article/18/3/452/236691
- **[R22] [F]** van Dijk, L. R., Manson, A. L., Earl, A. M., Garimella, K. V., Abeel, T. (2025). "Fast and exact gap-affine
  partial order alignment with POASTA." *Bioinformatics* 41(1):btae757. https://academic.oup.com/bioinformatics/article/41/1/btae757/7942505
- **[R23] [S]** Gotoh, O. (1982). "An improved algorithm for matching biological sequences." *J. Mol. Biol.*
  162(3):705–708. https://doi.org/10.1016/0022-2836(82)90398-9
- **[R24] [S]** Saitou, N., Nei, M. (1987). "The neighbor-joining method: a new method for reconstructing phylogenetic
  trees." *Mol. Biol. Evol.* 4:406–425.
- **[R25] [S]** Thompson, J. D., Higgins, D. G., Gibson, T. J. (1994). "CLUSTAL W: improving the sensitivity of progressive
  multiple sequence alignment…" *Nucleic Acids Research* 22:4673–4680.

### Sentence alignment for translations; embeddings; NLP tooling
- **[R26] [S]** Gale, W. A., Church, K. W. (1993). "A Program for Aligning Sentences in Bilingual Corpora."
  *Computational Linguistics* 19(1):75–102. https://aclanthology.org/J93-1004/
- **[R27] [S]** Varga, D., Németh, L., Halácsy, P., Kornai, A., Trón, V., Nagy, V. (2005). "Parallel corpora for medium
  density languages." *RANLP 2005*, 590–596. (Hunalign: https://github.com/danielvarga/hunalign)
- **[R28] [S]** Thompson, B., Koehn, P. (2019). "Vecalign: Improved Sentence Alignment in Linear Time and Space."
  *EMNLP-IJCNLP 2019*, 1342–1348. https://aclanthology.org/D19-1136/
- **[R29] [S]** Liu, L., Zhu, M. (2023). "Bertalign: Improved word embedding-based sentence alignment for Chinese–English
  parallel corpora of literary texts." *DSH* 38(4) (online Dec 2022). https://github.com/bfsujason/bertalign
- **[R30] [S]** Feng, F., Yang, Y., Cer, D., Arivazhagan, N., Wang, W. (2022). "Language-agnostic BERT Sentence
  Embedding." *ACL 2022*, 878–891. https://aclanthology.org/2022.acl-long.62/
- **[R31] [F]** Craig, C., Goyal, K., Crane, G., Shamsian, F., Smith, D. A. (2023). "Testing the Limits of Neural Sentence
  Alignment Models on Classical Greek and Latin Texts and Translations." *CHR 2023*, CEUR-WS Vol-3558.
  https://ceur-ws.org/Vol-3558/paper6193.pdf
- **[R33] [S]** Reimers, N., Gurevych, I. (2019). "Sentence-BERT: Sentence Embeddings using Siamese BERT-Networks."
  *EMNLP-IJCNLP 2019*, 3982–3992. https://aclanthology.org/D19-1410/
- Also consulted: **[S]** Steingrímsson, S., Loftsson, H., Way, A. (2023). "SentAlign: Accurate and Scalable Sentence
  Alignment." *EMNLP 2023 Demos*, 256–263. https://aclanthology.org/2023.emnlp-demo.22/ · **[F]** Levchenko, M. (2024).
  "Automatic Translation Alignment Pipeline for Multilingual Digital Editions of Literary Works." *CHR 2024*.
  https://arxiv.org/abs/2410.13255 · **[F]** Thai, K. et al. (2022). "Exploring Document-Level Literary Machine
  Translation with Parallel Paragraphs from World Literature" (PAR3). *EMNLP 2022*. https://arxiv.org/abs/2210.14250 ·
  **[S]** Qi, P., Zhang, Y., Zhang, Y., Bolton, J., Manning, C. D. (2020). "Stanza: A Python NLP Toolkit for Many Human
  Languages." *ACL 2020 Demos*, 101–108. https://aclanthology.org/2020.acl-demos.14/ (a pinnable parser for M2 if a
  constituent/clause signal is tried)

### Paraphrase, annotation agreement, interpretability, calibration
- **[R32] [S]** Rudin, C. (2019). "Stop explaining black box machine learning models for high stakes decisions and use
  interpretable models instead." *Nature Machine Intelligence* 1(5):206–215. https://doi.org/10.1038/s42256-019-0048-x
- **[R34] [S]** Guo, C., Pleiss, G., Sun, Y., Weinberger, K. Q. (2017). "On Calibration of Modern Neural Networks."
  *ICML 2017*, PMLR 70:1321–1330. https://proceedings.mlr.press/v70/guo17a.html
- **[R35] [S]** Vila, M., Martí, M. A., Rodríguez, H. (2014). "Is This a Paraphrase? What Kind? Paraphrase Boundaries
  and Typology." *Open Journal of Modern Linguistics* 4:205–218. https://doi.org/10.4236/ojml.2014.41016
- **[R36] [S]** Vila, M., Bertran, M., Martí, M. A., Rodríguez, H. (2015). "Corpus annotation with paraphrase types: new
  annotation scheme and inter-annotator agreement measures." *Language Resources and Evaluation* 49:77–105.
  https://doi.org/10.1007/s10579-014-9272-5
- **[R37] [F]** Wahle, J. P., Gipp, B., Ruas, T. (2023). "Paraphrase Types for Generation and Detection." *EMNLP 2023*,
  12148–12164. https://aclanthology.org/2023.emnlp-main.746/
- **[R38] [S]** Artstein, R., Poesio, M. (2008). "Inter-Coder Agreement for Computational Linguistics." *Computational
  Linguistics* 34(4):555–596. https://aclanthology.org/J08-4004/
- **[R46] [F]** He, H., and Thinking Machines Lab (2025-09-10). "Defeating Nondeterminism in LLM Inference."
  https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/

### Human–AI interaction, trust and uncertainty
- **[R39] [S]** Lee, J. D., See, K. A. (2004). "Trust in automation: Designing for appropriate reliance." *Human Factors*
  46(1):50–80.
- **[R40] [S]** Zhang, Y., Liao, Q. V., Bellamy, R. K. E. (2020). "Effect of Confidence and Explanation on Accuracy and
  Trust Calibration in AI-Assisted Decision Making." *FAT\* '20*. https://arxiv.org/abs/2001.02114
- **[R41] [S]** Bansal, G., Wu, T., Zhou, J., Fok, R., Nushi, B., Kamar, E., Ribeiro, M. T., Weld, D. S. (2021). "Does the
  Whole Exceed its Parts? The Effect of AI Explanations on Complementary Team Performance." *CHI 2021*.
  https://doi.org/10.1145/3411764.3445717
- **[R42] [S]** Buçinca, Z., Malaya, M. B., Gajos, K. Z. (2021). "To Trust or to Think: Cognitive Forcing Functions Can
  Reduce Overreliance on AI in AI-assisted Decision-making." *Proc. ACM HCI* 5(CSCW1), Art. 188.
  https://doi.org/10.1145/3449287
- **[R43] [S]** Hullman, J., Qiao, X., Correll, M., Kale, A., Kay, M. (2019). "In Pursuit of Error: A Survey of
  Uncertainty Visualization Evaluation." *IEEE TVCG* 25(1):903–913.
- **[R44] [S]** Kay, M., Kola, T., Hullman, J. R., Munson, S. A. (2016). "When (ish) is My Bus? User-centered
  Visualizations of Uncertainty in Everyday, Mobile Predictive Systems." *CHI 2016*, 5092–5103.
  https://doi.org/10.1145/2858036.2858558
- Also consulted: **[S]** Amershi, S. et al. (2019). "Guidelines for Human-AI Interaction." *CHI 2019*.
  https://doi.org/10.1145/3290605.3300233

### Visualisation evaluation and accessibility
- **[R45] [S]** Munzner, T. (2009). "A Nested Model for Visualization Design and Validation." *IEEE TVCG* 15(6):921–928.
  https://www.cs.ubc.ca/labs/imager/tr/2009/NestedModel/NestedModel.pdf
- **[R47] [S]** Lam, H., Bertini, E., Isenberg, P., Plaisant, C., Carpendale, S. (2012). "Empirical Studies in Information
  Visualization: Seven Scenarios." *IEEE TVCG* 18(9):1520–1536. https://doi.org/10.1109/TVCG.2011.279
- **[R48] [F]** Benito-Santos, A., Windhager, F., Horaniet Ibañez, A., Kleymann, R., Abdul-Rahman, A., Mayr, E. (2026).
  "Chasing Meaning and/or Insight? A Survey on Evaluation Practices at the Intersection of Visualization and the
  Humanities." CHI '26 (accepted). https://arxiv.org/abs/2601.20464
- **[R49] [F]** W3C (2023; current version 12 Dec 2024). *Web Content Accessibility Guidelines (WCAG) 2.2*, W3C
  Recommendation. SC 1.4.1, 2.1.1. https://www.w3.org/TR/WCAG22/
- **[R50] [S]** Wong, B. (2011). "Points of view: Color blindness." *Nature Methods* 8:441. https://doi.org/10.1038/nmeth.1618

### Segmentation and corpora
- **[R51] [S]** Unicode Consortium. *UAX #29: Unicode Text Segmentation*. https://www.unicode.org/reports/tr29/
- **[R52] [S]** ICU User Guide, "Boundary Analysis" (dictionary-based word breaking for Chinese, Japanese, Thai, …).
  https://unicode-org.github.io/icu/userguide/boundaryanalysis/
- **[R53] [F]** Bordalejo, B. (2009). "Introduction to the Online Variorum of Darwin's *Origin of Species*." *Darwin
  Online*. https://darwin-online.org.uk/Variorum/Introduction.html

*(Reference numbers are stable labels, not a reading order. Some R-numbers are referenced only in this list.)*
