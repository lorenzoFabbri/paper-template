# Changelog

Changes to the template. A paper cloned from it does not carry this file; `make init` removes it.

The engine has its own changelog, at `engine/CHANGELOG.md`, and its own version.

## 1.0.0

Split out of manuscript-engine, which was a GitHub template and so copied the build machinery into every paper permanently. This repository is the paper; the machinery arrives as a submodule.

- **`engine/` is a git submodule** pinned to a tagged engine release, following the engine's `release` branch. A paper opts into a fix with `git submodule update --remote engine`, and one that never opts in stays reproducible at the commit its gitlink records. The URL is absolute, so a paper still resolves it after `make init` replaces `origin`.
- **Clone with `--recurse-submodules`.** Every target checks that `engine/` is populated and says what to run if it is not, rather than failing with "No such file or directory" — and `make lint` no longer reports itself clean when it linted nothing.
- **`make init` no longer deletes `.git`.** With a submodule that also destroyed `.git/modules/engine`. It now collapses the history onto an orphan commit, sweeps every ref rather than the branch and tags alone, and leaves the submodule intact. It refuses, before touching anything, on an uninitialised or non-repository `engine/`, an engine pinned to a commit no clone could fetch, a git identity that exists only because git synthesised one from the hostname, an existing `__paper_init` branch, or a journal or citation style that names no file in the engine. A detached HEAD is survived rather than refused, where it previously aborted the script after the filesystem had been rewritten.
- **`make check-regenerate` is gone from the paper.** It rewrote files the engine owns. Goldens are regenerated in the engine's own repository.
- `make init` writes a `build.limits` block, which it never did although everything documented it; prints a title containing a backtick or `$` instead of expanding it; leaves the Makefile mode 644 rather than 600; and removes its target through one self-contained block instead of a positional `.PHONY` edit that a reordering would have defeated.
- **`LICENSE` is CC0**, covering the scaffolding only. What you write with it was never covered by anything, and `engine/` is licensed separately.
- **What ships is a skeleton, not a worked example.** `main.md` is section headings and the supplement marker; `figures/`, `tables/` and `checklists/` are empty; `references.bib` has no entries. Nothing invented ships, so no fabricated cohort, estimate or table can reach a submission bundle by being forgotten. The authoring syntax lives in `README.md`, and init carries that table into the README it writes.
- **The ref sweep needs no particular git.** It used `for-each-ref --exclude`, which arrived in git 2.42 — newer than Debian 12 or Ubuntu 22.04 ship — and on those the sweep failed *after* the branch had been renamed, while the error handler still claimed nothing was lost and printed a recovery command that did nothing. The sweep runs before the rename now, and past that point the message says what is actually true.
- **Init refuses when the repository holds anything but the template's own branch** — another branch, a tag, a stash — or when the working tree is dirty. Replacing the history deletes every ref, and a stash of the author's is not the template's to remove. The prompt no longer calls the author's commits the template's history.
- `make submit` and `make bib` name `yq` when `yq` is what is missing, rather than blaming `paper.yml`. `make help` lists `init` while `init` exists. The generated README carries the authoring conventions, names a real clone URL when one is known, and says what to run after a pull that moves the pin. The remote heuristic matches the upstream path in both URL forms rather than a word anywhere in the URL.
- **CI on Ubuntu**, building the paper as a co-author receives it, plus a job that clones without submodules and asserts every engine-dependent target refuses clearly. The linters are pinned, so the same tree cannot pass here and fail there.
