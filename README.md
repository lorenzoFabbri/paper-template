# paper-template

A template for writing a paper. Clone it, fill in one config file, write Markdown, and get a submission-ready DOCX, a Typst PDF, and a journal-shaped bundle.

It exists because the alternatives all lose something. Word loses reproducibility and version control. LaTeX loses your co-authors. Google Docs loses the bibliography. Writing in Markdown and building the rest keeps the source in git, keeps the citations in Zotero, and still hands your co-authors a Word file they can track-change.

## Start a paper

```sh
git clone --recurse-submodules https://github.com/lorenzoFabbri/paper-template.git my-paper
cd my-paper
make init
```

`--recurse-submodules` matters: the build machinery is a submodule, and without it `engine/` arrives empty. Every target that needs the engine says so rather than failing obscurely — `make help` and `make clean` do not need it and still work — and `git submodule update --init` fixes it.

`make init` asks nine questions — title, short title, first author with email and ORCID, affiliation, target journal, citation style, Zotero collection — then writes `paper.yml`, replaces this README with one about your paper, and removes the scaffolding that exists only to develop the template. It then offers to replace the template's commit history with a single commit for your paper. From then on the repo is your paper.

## Write

Prose lives in `main.md`. Everything after the `{#sec:supp}` heading is supplementary material and becomes its own document at build time.

Metadata lives in `paper.yml` and nowhere else: title, authors, affiliations, ORCIDs, target journal, citation style, Zotero collection. Change the title there and every output follows.

`main.md` starts as section headings and the supplement marker, and nothing else — no worked example to delete, and no invented numbers that could reach a submission bundle by being forgotten. This table is where the syntax lives, and `make init` carries it into the README it writes for your paper:

| To write | Use |
|---|---|
| a citation | `[@key]`, `[@one; @two]`, or `@key` in text |
| a figure | `![Caption.](figures/flow.png){#fig:flow}`, referenced as `@fig:flow` |
| a table | a `::: {#tbl:baseline}` div holding the caption, referenced as `@tbl:baseline` |
| the supplement boundary | `# Supplementary Material {#sec:supp}` |
| a checklist anchor | `{.checklist-strobe-4}` on a heading, or a `::: {.checklist-record-6}` div — any instrument |
| a Word paragraph style | `::: {.style-abstract}` |
| a note to a co-author | `[text]{.coauthor-comment author="AL" date="2026-08-12"}` — highlighted in every output, never mistakable for prose |

Figures are files you drop in `figures/`. Tables are files you drop in `tables/`, produced by whatever makes your tables. Neither is authored inline, and both directories start empty.

Numbering is automatic and consistent across both documents: main items are `Figure 1`, supplementary items are `Figure S1`, and a reference from the main text to a supplementary figure resolves correctly because both builds see the whole manuscript.

## Build

```sh
make docx       # build/main.docx and build/supplement.docx
make pdf        # build/main.pdf, double-spaced and line-numbered for review
make bib        # refresh references.bib from your Zotero collection
make submit     # a journal-ready bundle for the journal in paper.yml
make check      # build the engine's four test papers, checked against their sources
make lint       # yamllint over paper.yml, and shellcheck while the scaffolding is here
make clean      # remove build/
```

Everything in `build/` is reproducible from `main.md` and `paper.yml`, so none of it is tracked.

## Citations

`make docx` renders citations with citeproc from the committed `references.bib`. It needs no Zotero and no network, so a co-author who clones the repo can build it.

`make bib` refreshes `references.bib` from the Zotero collection named in `paper.yml`. Give the full path from the library root, as the collection is nested in Zotero:

```yaml
build:
  zotero-collection: "Projects/Bladder/Incidence"
```

## Revision, and the Word problem

Once reviews come back, the document usually stops being Markdown and becomes a `.docx` passed between co-authors. That is fine, but citations added in Word during that phase have to be real Zotero citations, or the numbering and the bibliography come apart.

`make docx-live` builds for that handoff. Its citations are Zotero field codes rather than formatted text, so anyone with Zotero and the Word plugin can insert, refresh and restyle references inside the document. It needs Zotero running with Better BibTeX, and it is the one build that is not reproducible offline.

Open Zotero's document preferences once in the delivered file before the first Refresh. Until you do, each citation shows as `<Do Zotero Refresh: …>`, which is the placeholder Word replaces.

Both citation forms convert: `[@key]` becomes a field, and the in-text `@key` becomes the author's name followed by a field. A key that is not in your library fails the build rather than passing quietly, because a citation that looks finished and cannot be refreshed is worse than no build at all.

Use `make docx` for everything else: it is faster, needs nothing running, and produces the plain formatted citations a journal expects.

## Submission

`make submit` reads the journal key from `paper.yml`, checks the manuscript against the limits you recorded there, renames every artefact to the journal's required filenames, and writes a ZIP.

Limits are checked before anything is copied, and all violations are reported at once:

```
[packager] ERROR: abstract is 341 words, limit 200
[packager] ERROR: 63 references cited, limit 50
```

The manuscript is measured from the parsed document rather than from the Markdown, so a cross-reference is never counted as a citation, and figures are numbered by where the manuscript uses them rather than by how their filenames sort.

The limits themselves live in `paper.yml`, under `build.limits`, because a number copied from a publisher's page goes stale and the person who can tell whether it is still right is the one about to submit:

```yaml
build:
  journal: aje
  limits:
    abstract: 200
    main_text: 4000
    references: ~
```

`engine/styles/submission-rules/` holds one file per journal, describing what the journal wants each file **called** and what it requires alongside the manuscript. Each carries a `verified` flag and the URL it was read from; packaging against an unverified profile warns.

## The engine

`engine/` is [manuscript-engine](https://github.com/lorenzoFabbri/manuscript-engine), carried as a git submodule and pinned to one tagged release. Pinning is the point: a change to the engine cannot reach a paper that did not ask for it. It fixes the engine, not the pandoc around it — `make check` is what tells you whether your toolchain has moved under you.

To ask for it:

```sh
git submodule update --remote engine
git -C engine describe --tags        # what you moved to
git add engine && git commit -m "Engine $(git -C engine describe --tags)"
```

That follows the engine's `release` branch, which only ever points at a tagged release, so a bump never lands on unreleased work. `engine/CHANGELOG.md` says what changed, and `make check` builds the engine's own four test papers and checks each against its manuscript — which is how you find out whether your output would move.

On the receiving end, a plain `git pull` leaves the old engine checked out and the paper still builds against it, silently. After any pull that moves the pin, run `git submodule update --init --recursive`. A later `git add -A` with a stale engine would quietly commit the pin backwards.

No build reaches the network or checks for updates. `make docx-live` and `make bib` talk to Zotero on `127.0.0.1:23119` and are the only exceptions; both fail with a clear message when it is not running.

## Requirements

`pandoc`, `pandoc-crossref`, [`yq`](https://github.com/mikefarah/yq) (mikefarah's, v4 — Debian and Ubuntu ship a different program under that name), `typst` for `make pdf`, `pdftotext` from poppler, `unzip`, `curl`, and `python3`. Nothing needs installing with pip. `make lint` uses `uvx`, which fetches its linters from PyPI and is the one command here that reaches the network. `make docx-live` and `make bib` need Zotero with Better BibTeX.

The engine records the pandoc and pandoc-crossref versions it was tested against; see `engine/README.md`.

## Layout

```
paper.yml          the only file you edit for a new paper
main.md            prose, main text and supplement
references.bib     empty until `make bib`, or maintained by hand
figures/ tables/ checklists/   empty; drop your files in
build/             outputs, untracked
engine/            the machinery, as a pinned submodule
LICENSE            CC0, for the scaffolding only
```

## Licence

The scaffolding — `main.md`, `paper.yml`, the `Makefile`, `.template/` — is CC0: public domain, no attribution, yours to relicense or delete. See `LICENSE`. What you write with it was never covered by anything. `engine/` is a separate repository under its own licence; see `engine/LICENSE`.

This template was built with [Claude Code](https://claude.com/claude-code), which wrote much of it under review. That applies to the tool, not to anything you write with it: nothing in a built manuscript, a PDF or a submission bundle records how the tool was made, and `make init` replaces this file with one about your paper.
