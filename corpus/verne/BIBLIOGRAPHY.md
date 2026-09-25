# Jules Verne — collation-corpus bibliography

A working bibliography of Jules Verne's *Voyages extraordinaires*, built to support **collation testing of
variant editions and competing translations** with CollationKit. Its job is not to be a complete descriptive
bibliography of every print edition (that is the domain of Taves & Michaluk's *Jules Verne Encyclopedia* and
Butcher's checklists — see [Sources](#sources)); it is to record, per work, **which texts we can actually obtain,
clean, and collate**, with enough verified metadata to cite and to reason about *what kind of variation* a given
pair exercises.

> **Data-integrity rule (read before adding a row).** Every factual field here must be **either verified against a
> cited source or explicitly marked unverified.** Publication dates, publishers, translators, and especially
> **page counts** are exactly where an unsourced guess looks plausible and is wrong — which for a scholarly corpus
> is worse than a blank. Fields we have not confirmed carry `⟨TO VERIFY: where to look⟩`. Do **not** silently fill
> them in without a source. The verified data below was gathered 2026-07-24 from the sources listed at the end; the
> per-novel translation tables ultimately derive from Taves & Michaluk (1996) via the cited Wikipedia articles.

Legend: **PG###** = Project Gutenberg eBook ID (public domain in the US unless marked otherwise — PG2488 is in copyright). **⟨TO VERIFY⟩** = not yet sourced. A ✅ in
"corpus" means we already hold cleaned witnesses (see the per-work `<work>/meta.json`).

---

## 1. How this maps to the corpus

The corpus (`corpus/verne/<work>/`) currently holds **4 works**, each as a competing-translation pair (Ch.1 excerpt +
full novel). This bibliography extends that: for each work it lists *all* obtainable public-domain English
translations (candidate future witnesses), the French source text (for eventual French-French or French↔English
collation), and the verified publication metadata that lets us describe a pair scholarly.

| work | in corpus | witnesses held | French source text |
|------|:---------:|----------------|--------------------|
| Twenty Thousand Leagues Under the Sea | ✅ | `mercier` (PG164), `walter` (PG2488) | PG5097 (*Vingt mille lieues*, complete) |
| From the Earth to the Moon | ✅ | `towle`→Mercier&King (PG83), `moonvoyage`→Linklater? (PG12901) | PG38674 (*De la terre à la lune*) |
| Journey to the Centre of the Earth | ✅ | `malleson` (PG3748), `ward` (PG18857) | PG4791 (*Voyage au centre de la Terre*) |
| The Mysterious Island | ✅ | `kingston` (PG1268), `white` (PG8993) | PG14287 (*L'île mystérieuse*) |
| Around the World in Eighty Days | ☐ | — (PG103 = Towle available) | ⟨FR id unresolved — PG20973 404s⟩ |
| Five Weeks in a Balloon | ☐ | — (PG3526 available) | ⟨TO VERIFY: PG French ID⟩ |

> **French source texts downloaded (2026-07-24).** The French originals for the four corpus works are fetched
> into `raw/` (not committed; rebuilt by the build script) — **PG5097** (*Vingt mille lieues*), **PG38674** (*De la terre à la lune*), **PG4791** (*Voyage au centre
> de la Terre* — a Gallica/BnF OCR text with a bilingual preface), **PG14287** (*L'île mystérieuse*). The cleaner
> preserves accents; `scripts/build_corpus.sh` fetches them and carries a **commented-out French-witness section**
> (using `fr-` sigla) ready to uncomment for French↔English (needs a translation lexicon / peer-MSA at collate
> time) or French–French work. The French *Le Tour du monde* id is unresolved (PG20973 404s).

✅ **Corpus discrepancy RESOLVED (2026-07-24).** Our `earth-to-moon/meta.json` labelled the PG83 witness "Towle
lineage" — **wrong**. Per the Evans and Sherwood/ibiblio bibliographies (and the Internet Archive source record),
**PG83 is the Lewis (Louis) Page Mercier & Eleanor E. King translation** (Sampson Low, Oct. 1873); George M. Towle
translated *Around the World in Eighty Days*, not this novel. **PG12901 ("The Moon-Voyage,"** Ward, Lock & Co., ill.
Henry Austin**) is a different translation — most likely T. H. Linklater's** (George Routledge & Sons, 1877, *From
the Earth to the Moon Direct and Round the Moon*), reissued under the *Moon-Voyage* title (title/publisher differ,
so this last identification is *probable*, not confirmed). The corpus `meta.json` has been corrected; the siglum
`towle` is kept as an opaque legacy id (renaming would ripple through filenames + `build_corpus.sh`). So the pair is
really **Mercier & King (1873) ↔ Linklater? (1877)** — two *named* Victorian translations, which is a *better*
provenance story than before. ⟨remaining: confirm PG12901 == Linklater's Routledge text⟩

---

## 2. Detailed entries — the works we can collate

Each entry: the French original (verified), then the English translations that matter for collation, with
translator · first-publication year · publisher, and the Gutenberg ID where a public-domain text exists. "Collation
value" notes what *kind* of variation a pairing exercises (the reason it earns a place in the corpus).

### 2.1 Twenty Thousand Leagues Under the Sea — *Vingt mille lieues sous les mers*

- **French original.** Serialised in Hetzel's *Magasin d'éducation et de récréation*, March 1869 – June 1870;
  first book (deluxe octavo, illustrated by de Neuville & Riou, 111 plates), **November 1871**, publisher
  **Pierre-Jules Hetzel** (Paris). Public-domain French text: **PG5097**.
- **English translations:**

  | translator | year | publisher | PG | notes / collation value |
  |---|---|---|:--:|---|
  | Lewis Page Mercier ("Mercier Lewis") | **Nov. 1872** | Sampson Low (London) | **PG164** | Sampson Low's *first* Verne. The notorious "standard": cut ~¼ of the text, many errors (*scaphandre*→"cork-jacket"). The *abridging* base — a heavy-substitution/deletion witness. **Held.** |
  | Anthony Bonner | 1962 | Bantam Classics | — | intro by Ray Bradbury. In copyright. |
  | Walter James Miller | 1966 | Washington Square Press | — | corrected Mercier; restored cuts. In copyright. |
  | Miller & Frederick Paul Walter | 1993 | Naval Institute Press | — | "Completely Restored & Annotated." In copyright. |
  | William Butcher | 1998 | Oxford University Press | — | annotated. In copyright. |
  | Frederick Paul Walter | 2010 | SUNY Press (*Amazing Journeys*) | **PG2488** | fully restored/unabridged. The *faithful* counter-witness to Mercier. **In copyright** (© 1999 F. P. Walter; on PG under its licence) — **held locally only**: rebuilt by `scripts/build_corpus.sh`, not committed. |
  | David Coward | 2017 | Penguin Classics | — | in copyright. |

  *Collation value:* Mercier ↔ Walter is the flagship abridged-vs-complete pair (~21.8k variants on the full novel).

### 2.2 From the Earth to the Moon — *De la Terre à la Lune*

- **French original.** **1865**, publisher **Hetzel** (Paris). (Its sequel *Autour de la Lune* / *Around the
  Moon*, 1870, is frequently bound with it in English.) Public-domain French text: **PG38674**.
- **English translations** (per the sourced list; publishers mostly unrecorded there — ⟨TO VERIFY: publishers⟩):

  | translator | year | publisher | PG | notes / collation value |
  |---|---|---|:--:|---|
  | Anonymous | 1867 | ⟨TO VERIFY⟩ | — | earliest English. |
  | J. K. Hoyt | 1869 | ⟨TO VERIFY⟩ | — | |
  | **Lewis (Louis) P. Mercier & Eleanor E. King** | **1873** | **Sampson Low** | **PG83** | the "standard" 19th-c. English — **= corpus witness `towle`** (legacy misattributed siglum, corrected 2026-07-24). **Held.** |
  | Edward Roth | 1874 | ⟨TO VERIFY⟩ | — | notably free adaptation. |
  | **Thomas H. Linklater** | **1877** | **George Routledge & Sons** | **PG12901?** | *From the Earth to the Moon Direct and Round the Moon*. **Probably = corpus witness `moonvoyage`** ("The Moon-Voyage," Ward Lock reissue, ill. Henry Austin) — title/publisher differ, so *probable* not confirmed. **Held.** |
  | I. O. Evans | 1959 | ⟨TO VERIFY⟩ | — | in copyright. |
  | Lowell Bair | 1967 | ⟨TO VERIFY⟩ | — | in copyright. |
  | J. & R. Baldick | 1970 | ⟨TO VERIFY⟩ | — | in copyright. |
  | Harold Salemson | 1970 | ⟨TO VERIFY⟩ | — | in copyright. |
  | Walter James Miller | 1996 | ⟨TO VERIFY⟩ | — | annotated. |
  | Frederick Paul Walter | 2010 | SUNY Press | — | in *Amazing Journeys*. |
  | William Butcher | 2025 | Oxford University Press | — | most recent. |

  - Gutenberg holds the two public-domain English texts we use: **PG83** = the **Mercier & King** translation (our
    `towle` witness); **PG12901** (*The Moon-Voyage*) = **probably Linklater** (our `moonvoyage` witness). A third,
    **PG28918** (*From the Earth to the Moon*), the Internet Archive record attributes to **Lewis Page Mercier**
    ⟨confirm; may duplicate PG83's text⟩.
  - *Collation value:* PG83 ↔ PG12901 is our mid-difficulty pair (~7.4k full-novel variants) — now properly
    describable as **Mercier & King (1873) ↔ Linklater? (1877)**, two named Victorian translations.

### 2.3 Journey to the Centre of the Earth — *Voyage au centre de la Terre*

- **French original.** First **1864**; **revised & expanded 1867** (the version most later texts follow),
  publisher **J. Hetzel et Cie** (Paris). *Two French states (1864 vs 1867) are themselves a French-French
  collation opportunity.* Public-domain French text: **PG4791**.
- **English translations:**

  | translator | year | publisher | PG | notes / collation value |
  |---|---|---|:--:|---|
  | Anonymous ("Prof. Hardwigg") | 1871 | Griffith & Farran (London) | **PG18857** | *drastically rewritten* — renamed characters (Hardwigg/Harry/Gretchen), added chapter titles. The "Von Hardwigg" witness. **Held.** |
  | Frederick A. Malleson ("Liedenbrock") | 1877 | Ward, Lock & Co. (London) | **PG3748** | more faithful; kept Liedenbrock; added chapter titles. **Held.** |
  | Robert Baldick | 1965 | Penguin Classics | — | in copyright. |
  | William Butcher | 1992 | Oxford World's Classics | — | in copyright. |
  | Frank Wynne | 2009 | Penguin Classics | — | in copyright. |
  | Matthew Jonas | 2022 | Birch Hill Publishing | — | in copyright. |
  | *(also on PG)* | — | — | **PG19513** | *A Journey to the Center of the Earth* — a further public-domain English text; ⟨TO VERIFY: which translation⟩. |

  *Collation value:* Malleson ↔ Ward is our **structural-divergence** case — the Griffith & Farran text is a
  near-rewrite (~16% longer, characters renamed), so the pair is a genuine two-*edition* (not just two-wording)
  test.

### 2.4 The Mysterious Island — *L'Île mystérieuse*

- **French original.** Serialised August 1874 – September 1875; book **November 1875**, publisher **Hetzel**
  (Paris). Public-domain French text: **PG14287**.
- **English translations:**

  | translator | year | publisher | PG | notes / collation value |
  |---|---|---|:--:|---|
  | Agnes Kinloch Kingston & W. H. G. Kingston | 1875 | Sampson Low (UK); Scribner (US, Nov 1875) | **PG1268** | the century-standard English (credited to W.H.G.K.; largely his wife's work). **Held.** |
  | Stephen W. White | 1876 | *Evening Telegraph* (Philadelphia), then reprint | **PG8993** | ~175,000 words; a fuller, independent rendering. **Held.** |
  | I. O. Evans (abridged) | 1959 | Associated Booksellers (Fitzroy) | — | ~90k words; in copyright. |
  | Lowell Bair (abridged) | 1970 | Bantam | — | ~90k words; in copyright. |
  | Sidney Kravitz | 2001 | Wesleyan University Press | — | unabridged, illustrated; in copyright. |
  | Jordan Stump | 2001 | Random House / Modern Library | — | unabridged; in copyright. |

  *Collation value:* Kingston ↔ White is our **largest** pair (~195k/167k words, ~31.8k variants) — a scale +
  substantive-divergence stress test.

### 2.5 Around the World in Eighty Days — *Le Tour du monde en quatre-vingts jours* *(not yet in corpus)*

- **French original.** Serialised in *Le Temps* from **6 Nov 1872**; book **30 Jan 1873**, publisher **Hetzel**
  (Paris). Public-domain French text: ⟨TO VERIFY: PG id unresolved — PG20973 404s⟩.
- **English translations:** George Makepeace Towle, **1873**, **James Osgood (Boston), reprinted by Sampson Low** —
  public-domain, **PG103** (also **PG28947**, a second English text ⟨TO VERIFY: translator⟩); William Butcher, 1995,
  Oxford World's Classics (in copyright). *Candidate next corpus work — Towle (PG103) vs the other PG English text
  would be a clean two-translation pair.*

### 2.6 Five Weeks in a Balloon — *Cinq semaines en ballon* *(not yet in corpus)*

- **French original.** **1863**, publisher **Hetzel** (Paris) — Verne's first *Voyage extraordinaire*.
  ⟨TO VERIFY: PG French ID⟩.
- **English translations:** "William Lackland," **1869** ⟨TO VERIFY: publisher; and confirm this is PG3526's
  text⟩; Frederick Paul Walter (ed. Arthur B. Evans), 2015, unabridged (in copyright). Public-domain English:
  **PG3526**.

---

## 3. Canonical index — the full *Voyages extraordinaires* (French dates verified)

The complete series of novels published in Verne's lifetime, with English title, French title, and **first French
publication year** (all verified from the Wikipedia bibliography, sourced to Taves & Michaluk). English-translation
detail and Gutenberg IDs are filled in per work **only as verified** — the six works in §2 are done; the rest carry
⟨TO VERIFY⟩ and are the backlog for expanding the corpus. This index is the scaffold: pick a row, source its
translations, promote it to a §2 entry.

| # | English title | French title | Fr. year |
|--:|---|---|:--:|
| 1 | Five Weeks in a Balloon | *Cinq semaines en ballon* | 1863 |
| 2 | Journey to the Center of the Earth | *Voyage au centre de la Terre* | 1864 (rev. 1867) |
| 3 | From the Earth to the Moon | *De la Terre à la Lune* | 1865 |
| 4 | The Adventures of Captain Hatteras | *Voyages et aventures du capitaine Hatteras* | 1866 |
| 5 | In Search of the Castaways | *Les Enfants du capitaine Grant* | 1867–68 |
| 6 | Twenty Thousand Leagues Under the Seas | *Vingt mille lieues sous les mers* | 1869–70 |
| 7 | Around the Moon | *Autour de la Lune* | 1870 |
| 8 | A Floating City | *Une ville flottante* | 1871 |
| 9 | The Adventures of Three Englishmen and Three Russians… | *Aventures de trois Russes et de trois Anglais…* | 1872 |
| 10 | The Fur Country | *Le Pays des fourrures* | 1873 |
| 11 | Around the World in Eighty Days | *Le Tour du monde en quatre-vingts jours* | 1873 |
| 12 | The Mysterious Island | *L'Île mystérieuse* | 1874–75 |
| 13 | The Survivors of the Chancellor | *Le Chancellor* | 1875 |
| 14 | Michael Strogoff | *Michel Strogoff* | 1876 |
| 15 | Off on a Comet (Hector Servadac) | *Hector Servadac* | 1877 |
| 16 | The Child of the Cavern | *Les Indes noires* | 1877 |
| 17 | Dick Sand, A Captain at Fifteen | *Un capitaine de quinze ans* | 1878 |
| 18 | The Begum's Fortune | *Les Cinq Cents Millions de la Bégum* | 1879 |
| 19 | Tribulations of a Chinaman in China | *Les Tribulations d'un Chinois en Chine* | 1879 |
| 20 | The Steam House | *La Maison à vapeur* | 1880 |
| 21 | The Giant Raft (Eight Hundred Leagues on the Amazon) | *La Jangada* | 1881 |
| 22 | Godfrey Morgan (The School for Robinsons) | *L'École des Robinsons* | 1882 |
| 23 | The Green Ray | *Le Rayon vert* | 1882 |
| 24 | Kéraban the Inflexible | *Kéraban-le-têtu* | 1883 |
| 25 | The Vanished Diamond (The Star of the South) | *L'Étoile du sud* | 1884 |
| 26 | The Archipelago on Fire | *L'Archipel en feu* | 1884 |
| 27 | Mathias Sandorf | *Mathias Sandorf* | 1885 |
| 28 | The Lottery Ticket | *Un billet de loterie* | 1886 |
| 29 | Robur the Conqueror (The Clipper of the Clouds) | *Robur-le-Conquérant* | 1886 |
| 30 | North Against South | *Nord contre Sud* | 1887 |
| 31 | The Flight to France | *Le Chemin de France* | 1887 |
| 32 | Two Years' Vacation | *Deux ans de vacances* | 1888 |
| 33 | Family Without a Name | *Famille-sans-nom* | 1889 |
| 34 | The Purchase of the North Pole (Topsy-Turvy) | *Sans dessus dessous* | 1889 |
| 35 | César Cascabel | *César Cascabel* | 1890 |
| 36 | Mistress Branican | *Mistress Branican* | 1891 |
| 37 | Carpathian Castle | *Le Château des Carpathes* | 1892 |
| 38 | Claudius Bombarnac | *Claudius Bombarnac* | 1893 |
| 39 | Foundling Mick | *P'tit-Bonhomme* | 1893 |
| 40 | Captain Antifer | *Mirifiques Aventures de Maître Antifer* | 1894 |
| 41 | Propeller Island | *L'Île à hélice* | 1895 |
| 42 | Facing the Flag | *Face au drapeau* | 1896 |
| 43 | Clovis Dardentor | *Clovis Dardentor* | 1896 |
| 44 | An Antarctic Mystery (The Sphinx of the Ice Fields) | *Le Sphinx des glaces* | 1897 |
| 45 | The Mighty Orinoco | *Le Superbe Orénoque* | 1898 |
| 46 | The Will of an Eccentric | *Le Testament d'un excentrique* | 1899 |
| 47 | The Castaways of the Flag (Second Fatherland) | *Seconde Patrie* | 1900 |
| 48 | The Village in the Treetops | *Le Village aérien* | 1901 |
| 49 | The Sea Serpent (The Yarns of Jean-Marie Cabidoulin) | *Les Histoires de Jean-Marie Cabidoulin* | 1901 |
| 50 | The Kip Brothers | *Les Frères Kip* | 1902 |
| 51 | Travel Scholarships | *Bourses de voyage* | 1903 |
| 52 | A Drama in Livonia | *Un drame en Livonie* | 1904 |
| 53 | Master of the World | *Maître du monde* | 1904 |
| 54 | Invasion of the Sea | *L'Invasion de la mer* | 1905 |

> **Posthumous novels (Michel Verne edited/co-wrote; often two states exist — Jules's ms vs the published Hetzel
> version — a rich French-French collation seam):** *The Lighthouse at the End of the World* (1905), *The Golden
> Volcano* (1906), *The Thompson Travel Agency* (1907), *The Chase of the Golden Meteor* (1908, PG French
> **PG76724**), *The Danube Pilot* (1908), *The Survivors of the "Jonathan"* (1909), *The Secret of Wilhelm
> Storitz* (1910), *Yesterday and Tomorrow* (stories, 1910), *The Barsac Mission* (1919). ⟨TO VERIFY: exact dates
> & English translations⟩ — worth a dedicated pass because the ms/published divergence is *authorial-vs-editorial*
> variation, a distinct collation category.

---

## 4. Sources

- **Wikipedia bibliography of Jules Verne** — canonical work list & French dates:
  <https://en.wikipedia.org/wiki/Jules_Verne_bibliography> (retrieved 2026-07-24).
- **Per-novel Wikipedia articles** — translation tables (sourced there to Taves & Michaluk 1996), retrieved
  2026-07-24: [Twenty Thousand Leagues](https://en.wikipedia.org/wiki/Twenty_Thousand_Leagues_Under_the_Seas) ·
  [Journey to the Center of the Earth](https://en.wikipedia.org/wiki/Journey_to_the_Center_of_the_Earth) ·
  [From the Earth to the Moon](https://en.wikipedia.org/wiki/From_the_Earth_to_the_Moon) ·
  [The Mysterious Island](https://en.wikipedia.org/wiki/The_Mysterious_Island) ·
  [Around the World in Eighty Days](https://en.wikipedia.org/wiki/Around_the_World_in_Eighty_Days) ·
  [Five Weeks in a Balloon](https://en.wikipedia.org/wiki/Five_Weeks_in_a_Balloon).
- **Project Gutenberg — Jules Verne** (eBook IDs, public-domain texts): <https://www.gutenberg.org/ebooks/author/60>.
- **Scholarly references to acquire for authoritative per-edition detail (publishers, page counts, printings):**
  - Arthur B. Evans, *"Jules Verne's English Translations: A Bibliography"* (Science Fiction Studies) — the
    academic gold standard for translator/edition detail. ⟨obtain via library/JSTOR⟩.
  - Brian Taves & Stephen Michaluk Jr., *The Jules Verne Encyclopedia* (Scarecrow Press, 1996) — lists nearly all
    English translations to 1995.
  - William Butcher, *Jules Verne: The Definitive Biography* & his translation checklists.
  - The **Zvi Har'El "Jules Verne Collection"** and the **ibiblio "Jules Verne Project"** (Norman Wolcott) —
    online translation histories.

*All Gutenberg texts cited are public domain in the US, except PG2488 (F. P. Walter, in copyright). Retrieval date for the metadata above: 2026-07-24.*
