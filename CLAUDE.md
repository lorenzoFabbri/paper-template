# Working on this repository

This file is for developing the template. `make init` deletes it, so a paper cloned from here never carries it.

## What this is

A paper template. The repository root is the paper — `main.md`, `paper.yml`, `references.bib`, `figures/`, `tables/` — and `engine/` is [manuscript-engine](https://github.com/lorenzoFabbri/manuscript-engine) as a git submodule, pinned to a tagged release. Someone clones this with `--recurse-submodules`, runs `make init`, and writes.

Two properties are the point of the whole thing, and changes that weaken either are not worth making:

**`paper.yml` is the only file a paper edits.** If a new setting appears, it goes in `paper.yml`, read by the Makefile with `yq` and handed to pandoc as `--metadata-file`. Do not add a Make variable, an environment variable or a second config file.

**A build touches nothing but the local machine.** No fetching styles, no checking for updates, no network. `make docx-live` and `make bib` talk to Zotero on `127.0.0.1:23119` and are the only exceptions; both fail with a clear message when it is not running. `git submodule update --remote` is an act the author takes deliberately, never something a target does.

## The submodule boundary

Everything under `engine/` belongs to the other repository. This one cannot commit a change there, so:

- **Never write to `engine/`.** A build writing an unignored file inside it leaves the submodule dirty in every paper. `make check` writes only to `engine/tests/papers/*/build/`, which the engine's own `.gitignore` covers.
- **Never delete a file the engine tracks.** That is why `init-paper.sh` lives here, in `.template/`, and deletes itself rather than something in `engine/`.
- **`make check-regenerate` is not a target here.** Recording goldens rewrites files the engine owns; it belongs in the engine's own Makefile, where the filter change and the regenerated golden land in one commit.
- **A pipeline or filter change belongs in the engine**, followed by a release there and a submodule bump here.

Bumping the pin is three commands, and the tag it lands on must exist on the engine's remote — a pin nobody can fetch is a paper nobody can clone:

```sh
git submodule update --remote engine
git -C engine describe --tags
git add engine && git commit -m "Engine $(git -C engine describe --tags)"
```

## Before committing

```sh
make lint    # shellcheck over .template/init-paper.sh, yamllint over paper.yml
make check   # build the engine's four test papers and check them against their sources
```

`make check` takes about ten seconds and builds twelve documents. It is the engine's suite, run through the pinned engine, so it also tells you whether a bump changed anything.

## Testing a change to init

`make init` is destructive, removes itself, and can rewrite git history. Test it on a clone. Answers are read from stdin in the order prompted; the last one decides whether to replace the template's history, so `n` keeps it.

```sh
rm -rf /tmp/t && git clone --recurse-submodules -q . /tmp/t
cp .template/init-paper.sh /tmp/t/.template/
cd /tmp/t && old=$(git rev-parse HEAD)
./.template/init-paper.sh /tmp/t <<< $'Title\nShort\nName\nemail\norcid\nAffiliation\naje\nvancouver\ncollection\ny\n'
```

Clone rather than copy, and with `--recurse-submodules`, or neither the git branch nor the submodule checks are reached. Copy the working-tree `init-paper.sh` over the clone's, or you are testing the committed version instead of your change.

Running it proves nothing on its own. Assert:

```sh
git cat-file -e "$old^{commit}" 2>/dev/null && echo "FAIL: template commit survives"
[ "$(git rev-list --all --count)" -eq 1 ]                                    # one commit
[ "$(git cat-file --batch-all-objects --batch-check='%(objecttype)' | grep -c '^commit$')" -eq 1 ]
[ -z "$(git for-each-ref --exclude=refs/heads/main --format='%(refname)' refs)" ]
[ -z "$(git remote)" ]                                                       # origin was the template's
git ls-tree HEAD engine | grep -q '^160000 commit '                          # still a gitlink
git cat-file -p HEAD:.gitmodules | grep -q 'branch = release'
git submodule status | grep -q '^ [0-9a-f]\{40\} engine'                     # leading space: pin matches
[ -z "$(git status --porcelain)" ]
grep -c template-init Makefile                                               # 0
grep -n PHONY Makefile                                                       # no init, no lint-init
make docx && make lint
git clone --recurse-submodules . /tmp/t2 && make -C /tmp/t2 docx             # a co-author can build it
```

The third one is load-bearing: exactly one commit object in the whole store. The engine's commits live in `.git/modules/engine/objects`, a separate store, so they do not count.

Init refuses, before touching anything, on: no `Makefile` at the root, an uninitialised `engine/`, an `engine/` that is populated but not a repository, an engine pinned to a commit on no remote branch or tag, a `user.email` that only exists because git synthesised one from the hostname, a branch named `__paper_init` already existing, and a journal key or citation style that names no file in the engine. Each deserves its own clone and a `git status --porcelain` that comes back empty.

A detached HEAD is **not** a refusal. It is survived: `symbolic-ref --quiet` plus a fallback branch name is exactly what stops `set -e` killing the script there, and `git branch -M` then creates the branch that did not exist. Test it too — it is the path that used to abort after the filesystem had already been rewritten.

The commit itself is the last recoverable point. If it fails — a signing key that is not available, a hook — the ERR trap prints `git checkout -f <branch>`, which restores every file init wrote or deleted, `.template/` included.
