::: {.style-abstract}
**Background.** One or two sentences of context, ending in the gap this paper fills.

**Methods.** Design, setting, participants, exposure, outcome, and the estimator.

**Results.** The primary estimate with an interval, then the one secondary result that matters.

**Conclusions.** What a reader should now believe, and how confident they should be.
:::

# Introduction {.checklist-strobe-2}

Every element of this file is authored syntax the pipeline understands, so a fresh clone builds a non-empty document before a word of real prose is written. Delete it and write your paper.

A citation looks like this [@lovelace1843]. Two at once look like this [@lovelace1843; @babbage1864]. An in-text citation reads @hopper1952 showed the effect.

# Methods {.checklist-strobe-4}

Cross-references are written `@fig:` and `@tbl:` and resolve to numbers at build time: the flow diagram is @fig:flow and the cohort description is @tbl:baseline.

::: {.checklist-record-6}
A block tagged with a `checklist-` class carries a stable anchor into the built document, so `checklists/strobe.md` can cite a location that survives editing rather than a line number. Any instrument works: `checklist-strobe-2`, `checklist-consort-6a`, `checklist-arrive-10`.
:::

# Results

Tables are not authored inline. Produce `tables/baseline.docx` with whatever makes your tables, then reference it by id — the div below is a placeholder the engine fills:

::: {#tbl:baseline}
Baseline characteristics of the study population.
:::

Figures are image files under `figures/`:

![Participant flow through the study.](figures/flow.png){#fig:flow}

The estimate was 1.42 (95% CI 1.11 to 1.82), and it did not move under the sensitivity analysis in @tbl:sensitivity or the distribution shown in @fig:balance.

# Discussion {.checklist-strobe-18}

::: {.style-discussion}
Prose inside a `style-` div is mapped to the matching Word paragraph style, so a journal reference-doc can restyle the whole section without touching the source.
:::

A note to a co-author survives into the DOCX as highlighted text: [check whether the 2024 wave is included here]{.coauthor-comment author="AL" date="2026-08-12"}.

# References {.unnumbered}

::: {#refs}
:::

# Supplementary Material {#sec:supp}

Everything from this heading onwards is built into `supplement.docx` and removed from `main.docx`. Supplementary figures and tables are renumbered S1, S2, … automatically, and references to them from the main text resolve correctly because both builds see the whole document.

## Supplementary Methods

Detail that a reviewer wants and an editor does not.

## Supplementary Tables

::: {#tbl:sensitivity}
Sensitivity analyses under alternative exposure definitions.
:::

## Supplementary Figures

![Covariate balance after weighting.](figures/balance.png){#fig:balance}
