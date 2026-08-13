# Changelog

Changes to the template. A paper cloned from it does not carry this file; `make init` removes it.

The engine has its own changelog, at `engine/CHANGELOG.md`, and its own version.

## 1.0.0

Split out of manuscript-engine, which was a GitHub template and so copied the build machinery into every paper permanently. This repository is the paper; the machinery arrives as a submodule.

- **`engine/` is a git submodule** pinned to a tagged engine release, following the engine's `release` branch. A paper opts into a fix with `git submodule update --remote engine`, and one that never opts in stays reproducible at the commit its gitlink records. The URL is absolute, so a paper still resolves it after `make init` replaces `origin`.
- **Clone with `--recurse-submodules`.** Every target checks that `engine/` is populated and says what to run if it is not, rather than failing with "No such file or directory" — and `make lint` no longer reports itself clean when it linted nothing.
- **`make init` no longer deletes `.git`.** With a submodule that also destroyed `.git/modules/engine`. It now collapses the history onto an orphan commit, sweeps every ref rather than the branch and tags alone, and leaves the submodule intact. It refuses, before touching anything, on a detached HEAD, an uninitialised or non-repository `engine/`, an engine pinned to a commit no clone could fetch, a missing git identity, or a journal or citation style that names no file in the engine.
- **`make check-regenerate` is gone from the paper.** It rewrote files the engine owns. Goldens are regenerated in the engine's own repository.
- `make init` writes a `build.limits` block, which it never did although everything documented it; prints a title containing a backtick or `$` instead of expanding it; leaves the Makefile mode 644 rather than 600; and removes its target through one self-contained block instead of a positional `.PHONY` edit that a reordering would have defeated.
- The template carries no `LICENSE`: a paper's licence is its author's decision. `engine/` is licensed separately.
