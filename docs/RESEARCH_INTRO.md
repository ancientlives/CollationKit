# CollationKit — a research introduction

This is a general introduction to the project: its scope, its intellectual problem, what has already been
accomplished, and where the open research questions lie. It is worth reading in full before the more detailed
project documentation, as background rather than as a task list.

## 1. What the project is

Scholars who study a work surviving in several forms — a manuscript, a typescript, corrected proofs, a first
edition, a later authorial revision, rival translations — need to know precisely how those versions differ.
This is the discipline of **textual collation**, and its product is an *apparatus criticus*: a scholarly,
citable record of every variant, located by page, line, and word.

This is a materially different problem from the line-based `diff` you may already know. A line is not the right
unit, because prose revision happens at the level of the word or the phrase, and prose reflows; a paragraph can
move, sometimes across a page boundary, and be revised in the course of moving; not every difference is equally
interesting, since a spelling variant is noise while a change of wording is the finding; and the required
output is not a patch but a citation — page 12, line 4, words 3 to 5.

Solving this properly requires several things a generic sequence-comparison tool does not provide: an alignment
method that tolerates rewording rather than treating it as delete-and-insert; a means of recognising that a
passage has moved rather than been separately deleted and reinserted; a principled separation between genuine
changes of wording and mere spelling, punctuation, or case variation (the classical distinction between
*substantive* and *accidental* variants); and a citation attached to every finding. The project's position is
that these are domain constraints, not incidental engineering details, and that a solution ignorant of them is
solving a different, easier problem.

CollationKit was originally developed as a standalone prototype of a collation engine intended for a native macOS markdown editor. It is deliberately built as an isolated, pure component — no interface code, no file I/O, a pure function of its
inputs — precisely so that it can serve as a research vehicle: something you can test, benchmark, instrument,
and reason about without an application around it. Two papers are being developed from the work in progress:
one on the collation algorithms and their evaluation, and one on the visual presentation of a collation result
to a human reader.

## 2. What has been achieved

The project is not a green-field proposal; it is a working, evaluated system, and that is what makes the open
questions below tractable rather than speculative.

- A substantial automated test suite and a byte-exact conformance corpus pin the engine's behaviour precisely,
  rather than leaving it merely plausible.
- The engine has been validated on genuinely difficult real texts: complete novels collated across independent
  translations of the same source, where two translations share meaning but very little sentence-level
  wording, as well as material in verse and in a non-Latin script.
- Two strategies exist for merging more than two witnesses: one that aligns every witness against a single
  privileged base text, and one with no privileged base, suited to competing translations or traditions with no
  authoritative source.
- Cross-language collation is supported through a bilingual equivalence mechanism, allowing witnesses in
  different languages to be anchored to one another despite differing word order.
- An interactive viewer presents a collation through several complementary views: an analytical overview, the
  annotated text of each witness, a variant graph, parallel linked columns, a track-changes rendering, a
  plain-prose story of the differences, a visual alignment map, and a traditional apparatus listing.
- The project keeps an honest record of approaches that did not work, including a sustained investigation into
  a class of false-positive "phantom move" errors, which concluded in a clear negative result: neither
  word-rarity nor phrase-rarity predicts a genuine textual move; only a purely geometric signal does. That
  negative result is itself a research finding, and it motivates one of the open questions discussed below.
- The project has also taken a considered, argued position on where machine learning should and should not be
  used within it — a position you should understand before proposing any learning-based work, discussed in
  §4.1.

In short, the deterministic, rule-based core of the engine is mature and well-evaluated. The frontier is not
whether the engine works — it does — but the semantic layer that could sit above it, and the human question of
how its output is understood and trusted by a reader.

## 3. Concepts worth knowing

A short vocabulary, sufficient to follow the discussion below without reading any source code:

- **Witness** — one surviving version of a work; each is given a short identifying label.
- **Copy-text (or base)** — the privileged witness against which others are compared, where one exists.
- **Apparatus criticus** — the scholarly output form: a base reading, its variants, and the witnesses attesting
  each.
- **Substantive vs. accidental** — a genuine change of wording, as opposed to spelling, case, or punctuation
  variation.
- **Transposition** — a passage that has moved, potentially across a page boundary.
- **Variant graph** — the structure formed when all witnesses are merged: agreement forms a common spine, and
  disagreement branches from it.
- **Confidence** — the engine grades some findings, particularly moves, by certainty, and deliberately reports
  its ambiguous residual cases rather than concealing them.
- **Determinism** — identical witnesses and identical declared settings must always produce an identical
  result. This is treated as a scholarly requirement, since an apparatus must be independently reproducible by
  another scholar, and it is the constraint against which every research proposal below should be judged.

## 4. Where research is heading

### 4.1 Machine learning and artificial intelligence

The project's case for keeping the engine's deterministic core free of learned components rests on several
specific, evidence-based arguments, not a general suspicion of the technology: an apparatus must be exactly
reproducible from the witnesses alone, indefinitely; every variant must be defensible against an explicit rule,
whereas a bias learned across a corpus is not locally explainable; each witness set is idiosyncratic to its own
work, so there is no safe population to generalise from, and a pattern learned on one text may mislead on
another; and, in practice, the defects found in the engine to date have been errors of judgement correctable by
a better rule, not failures of capacity that more data or a larger model would have fixed.

This is a scoping argument, not a rejection of learning as such, and it leaves genuine openings for a layer that
respects it:

**A semantic layer for paraphrase.** The engine can currently tell you that one phrase has been substituted for
another, but not whether that substitution preserves meaning or changes it. This is a natural
sentence-embedding or lexical-semantics classification problem, made non-trivial by its required constraints:
any such layer must be strictly additive, never altering the underlying alignment; it must be deterministic and
version-pinned, so its output is as reproducible as the rest of the apparatus; and it must be inspectable,
presenting a score the scholar can see and overrule rather than a silent reclassification. The most difficult
and most publishable part of this problem is evaluation — establishing what should count as ground truth for
"paraphrase" in a scholarly edition, and validating against actual expert judgement.

**Sentence-level anchoring for cross-language collation.** The present cross-language mechanism anchors on
individual word pairs and has a known weakness with certain word-order inversions across a language boundary.
Aligning first at the sentence level, then within the sentence, is a richer approach well precedented in
machine translation research, and a corpus of source texts with independent translations already exists to
evaluate it against — provided any such layer, again, only ever adds anchoring information and never alters a
reported reading.

**A corpus-wide signal for move confidence.** A phrase that is a stock formula for a given author should be
weighed differently from one that is genuinely singular when the engine judges its confidence in a proposed
move. Any work here must engage with an established negative result: rarity, whether of a word or a phrase, has
already been shown not to predict whether a proposed move is genuine — the false positives observed were, if
anything, the rarest phrases — and only a geometric signal has proven reliable. A commonness measure should
sharpen the existing confidence judgement, not attempt to replace it as a standalone detector.

**An open question on the residual cases.** The project has demonstrated that a certain class of ambiguous move
is irreducible by geometry alone: a short passage sitting close to its original position cannot reliably be
distinguished from an unrelated short coincidence, and because at least one such short move is genuine in the
existing corpus, no simple length threshold can safely discard the ambiguous case. The engine's honest response
is to report these as merely likely rather than certain. Whether a learned signal can separate these cases where
geometry cannot, while remaining deterministic, auditable, and inspectable enough to be admissible in scholarly
use, is an open question with a clear baseline, a real corpus, and a documented negative result already
available to build on.

### 4.2 UI/UX and data visualisation

The principal gap here is empirical rather than conceptual: the viewer's design choices are argued from
established visualisation principles, but none has been evaluated with real users. This leaves several concrete
openings.

A task-based evaluation could establish which of the viewer's several views scholars and non-specialists
actually rely on for defined tasks — finding the largest revision, judging whether an alignment looks sound, or
establishing what changed in a given passage — rather than relying on design intuition about which view should
help. A closely related question is whether the visual alignment map, intended to let a reader verify that an
alignment is sound rather than simply accept it, actually achieves that in practice; this claim has not yet been
tested. Accessibility is largely unexamined: colour currently carries much of the meaning in the viewer, and
colour-blind-safe encoding, keyboard navigation, and a coherent reading order for assistive technology are all
open problems, made harder by the density of the material. A further open design question is legibility at
scale — how a collation with many thousands of variants should be presented without either overwhelming the
reader or concealing the finding they need. There is also a contained but genuine interface problem in how to
present a choice between two alignment strategies to a reader with no reason to understand the technical
distinction between them, where the project's existing position rules out a bare on/off toggle in favour of a
context-sensitive default with plain-language explanation still to be designed. Finally, for a student more
interested in native application interfaces than in web-based visualisation, building a native viewer is a
separate and open avenue.

### 4.3 Where the two tracks meet

The most demanding single question sits at the intersection of the two tracks above, and it is a live problem
in human-centred artificial intelligence rather than a purely technical one: how should a tool communicate
calibrated uncertainty to an expert who is entitled to overrule it? The engine already distinguishes certain
from merely likely findings and deliberately reports its irreducible ambiguous cases rather than hiding them,
but the viewer currently renders this distinction quite thinly. What should it look like to tell a scholar,
credibly and usefully, that a passage appears to have moved but that the evidence leaves room for doubt, when
that scholar is about to commit the answer to a published edition? Should the semantic layer discussed above
eventually be built, the question compounds further, since a reader would then need to distinguish a
model-judged claim from a rule-derived one at a glance. This is a coherent research project spanning both
tracks, grounded in a working system, a real evaluation corpus, and an already-documented negative result to
build upon.
