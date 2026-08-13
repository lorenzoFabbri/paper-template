#!/usr/bin/env bash
# init-paper.sh — turn a fresh clone of the template into a paper.
#
# Writes paper.yml from the answers given, replaces the template's README with
# one about the paper, and removes the scaffolding that exists only to develop
# the template: CLAUDE.md, .claude/, CHANGELOG.md, the init block in the
# Makefile, and this directory. engine/ stays: it is a submodule, and a paper
# owns nothing inside it.
#
# Answers are read from stdin in the order prompted, so the script can be
# driven by a heredoc as well as by hand.
#
# Four phases, in this order, because the failure that matters is not any one
# command failing — it is one failing after the filesystem has been rewritten
# and this script deleted:
#
#   0. every check that can fail, before the first mutation
#   1. the prompts, and validation of the answers
#   2. the filesystem
#   3. git
#
# Within phase 3 the commit is still recoverable; the first ref deletion is
# not. The ERR trap prints the one command that undoes everything up to there.

set -euo pipefail

ROOT="${1:?paper root required}"

# Set once phase 3 has made a commit that a checkout would undo.
recover_hint=""
die() {
    echo "[init] ERROR: $*" >&2
    [[ -n "$recover_hint" ]] && echo "[init]        $recover_hint" >&2
    exit 2
}

############################  Phase 0 — checks  ###############################

cd "$ROOT"

[[ -f "$ROOT/Makefile" ]] || die "$ROOT does not look like the template (no Makefile)."

# Not `git -C engine rev-parse --git-dir`: that exits 0 whether engine/ is a
# real submodule, an ordinary directory whose .git was removed, or an empty
# one, because it walks up and finds the superproject's. Every later
# `git -C engine ...` would then answer about the paper — the pin check below
# read the paper's own HEAD and passed on it. Asking which working tree the
# engine considers its superproject distinguishes all three.
_top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)
_sup=$(git -C "$ROOT/engine" rev-parse --show-superproject-working-tree 2>/dev/null || true)
if [[ -z "$_sup" || "$_sup" != "$_top" ]]; then
    die "engine/ is not an initialised submodule. Run 'git submodule update --init' first."
fi
[[ -f "$ROOT/engine/run-pipeline.sh" ]] || die "engine/ is incomplete; run 'git submodule update --init'."

in_git=0
branch=""
drop_origin=0
skip_gc=0

if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
    in_git=1

    # --quiet, or a detached HEAD makes this assignment fail and set -e kills
    # the script. Reachable from `git clone --branch <tag>` or a bisect.
    branch=$(git -C "$ROOT" symbolic-ref --quiet --short HEAD || true)
    [[ -n "$branch" ]] || branch=$(git -C "$ROOT" config --get init.defaultBranch || echo main)

    # useConfigOnly, or git synthesises an identity from $USER@$HOSTNAME and
    # this check passes while the commit is authored by someone who does not
    # exist.
    git -C "$ROOT" -c user.useConfigOnly=true var GIT_COMMITTER_IDENT >/dev/null 2>&1 \
        || die "set user.name and user.email before running init."

    if git -C "$ROOT" show-ref --verify --quiet refs/heads/__paper_init; then
        die "a branch named __paper_init already exists; delete it and try again."
    fi

    # Replacing the history deletes every ref, so anything the author made
    # themselves would go with the template's. A fresh clone has one branch and
    # nothing else; more than that means work only they can judge, and this
    # script is not entitled to weigh it.
    own_refs=$(git -C "$ROOT" for-each-ref --format='%(refname)' \
                   refs/heads refs/tags refs/stash \
                 | { grep -vxF "refs/heads/$branch" || true; })
    if [[ -n "$own_refs" ]]; then
        echo "[init] ERROR: this repository holds refs besides '$branch':" >&2
        while IFS= read -r r; do echo "[init]          $r" >&2; done <<< "$own_refs"
        echo "[init]        Replacing the history would delete them, and a stash or a" >&2
        echo "[init]        branch of your own is not the template's to remove." >&2
        echo "[init]        Delete or merge them yourself, then run init again." >&2
        exit 2
    fi

    if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
        die "the working tree has uncommitted changes; commit or discard them first."
    fi

    # The pin has to be reachable from a ref the engine's remote advertises, or
    # `git clone --recurse-submodules` of this paper fails for everyone except
    # this machine — and it will keep building here, so nobody notices. Answered
    # from refs already on disk, so this needs no network.
    sha=$(git -C "$ROOT/engine" rev-parse HEAD)
    if [[ -z "$(git -C "$ROOT/engine" branch -r --contains "$sha" 2>/dev/null)" ]] &&
       [[ -z "$(git -C "$ROOT/engine" tag --points-at "$sha" 2>/dev/null)" ]]; then
        echo "[init] ERROR: engine/ is pinned to $sha," >&2
        echo "[init]        which is on no branch or tag of the engine's remote." >&2
        echo "[init]        Nobody else could clone this paper. Run" >&2
        echo "[init]        'git submodule update --init' to return to the recorded pin." >&2
        exit 2
    fi

    # If THIS repository borrows objects from another, `gc --prune=now` can
    # delete objects the lender's other borrowers still need; git does not
    # protect them. The engine's own alternates file is irrelevant here:
    # superproject gc never touches the submodule's object database.
    alternates="$(git -C "$ROOT" rev-parse --absolute-git-dir)/objects/info/alternates"
    [[ -e "$alternates" ]] && skip_gc=1

    # Whether origin belongs to the template or to the author decides whether
    # dropping the remotes is a favour or a theft. The URL says; the commit
    # count does not.
    #
    # Matched on the repository name, so a fork keeping that name is read as the
    # template. A fork is the author's own, so the match is deliberately narrow:
    # the exact upstream path, not the word anywhere in the URL.
    # Both separators: HTTPS puts a slash before the owner, SSH a colon.
    origin_url=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
    case "${origin_url%.git}" in
        *[:/]lorenzoFabbri/paper-template) drop_origin=1 ;;
    esac
fi

############################  Phase 1 — answers  ##############################

ask() {
    local prompt="$1" default="${2:-}" reply
    if [[ -t 0 ]]; then
        read -r -p "  $prompt${default:+ [$default]}: " reply || reply=""
    else
        read -r reply || reply=""
    fi
    printf '%s' "${reply:-$default}"
}

# Filenames without their extension, for an error message that says what the
# valid answers are instead of only that this one was not.
keys_of() {
    local f out=""
    for f in "$@"; do
        [[ -e "$f" ]] && out+="$(basename "${f%.*}") "
    done
    printf '%s' "${out% }"
}

echo "Setting up your paper. Press enter to accept a default."
echo
title=$(ask "Title" "Untitled manuscript")
short_title=$(ask "Short title" "Untitled")
author_name=$(ask "First author")
author_email=$(ask "First author email")
author_orcid=$(ask "First author ORCID")
institute=$(ask "Affiliation")
journal=$(ask "Target journal key" "aje")
csl=$(ask "Citation style" "vancouver")
collection=$(ask "Zotero collection path")

# Both name a file in the engine. Unchecked, a wrong answer surfaces two builds
# later as a packaging error or a silently reformatted bibliography.
[[ -f "$ROOT/engine/styles/submission-rules/$journal.yml" ]] || die "no journal profile '$journal'.
       Available: $(keys_of "$ROOT"/engine/styles/submission-rules/*.yml)"
[[ -f "$ROOT/engine/styles/$csl.csl" ]] || die "no citation style '$csl'.
       Available: $(keys_of "$ROOT"/engine/styles/*.csl)"

##########################  Phase 2 — filesystem  #############################

# Every answer is written as a double-quoted YAML scalar, so an affiliation
# containing a colon, or a title containing a quote, stays valid YAML.
yq_quote() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

cat > "$ROOT/paper.yml" <<YAML
# The only file this paper needs you to edit.
#
# Read twice: Pandoc consumes the whole file as --metadata-file, and the
# Makefile reads the \`build:\` block with yq.

title: $(yq_quote "$title")
short-title: $(yq_quote "$short_title")

# Author keys, all rendered: name, institute (ids from the block below),
# correspondence, email, equal_contributor, orcid.
author:
  - name: $(yq_quote "$author_name")
    institute: [inst1]
    correspondence: true
    email: $(yq_quote "$author_email")
    orcid: $(yq_quote "$author_orcid")

institute:
  - id: inst1
    name: $(yq_quote "$institute")

keywords: []

build:
  journal: $(yq_quote "$journal")
  csl: $(yq_quote "$csl")
  typst-theme: "default"
  zotero-collection: $(yq_quote "$collection")

  # Limits for the journal above, copied from its author instructions when you
  # choose it. \`make submit\` checks the manuscript against them and refuses to
  # package a paper that exceeds one. Omit a limit to leave it unchecked.
  #
  # They live here rather than in the journal profile because a limit read from
  # a publisher's page goes stale, and the person who can tell whether it is
  # still right is the one about to submit.
  limits:
    abstract: ~
    main_text: ~
    references: ~
YAML

# The clone line names a real repository when one is known. When init has just
# dropped the template's remote, this paper has no URL yet, and inventing one
# would be worse than saying so. Each branch carries its own lead-in, so neither
# leaves a colon introducing the wrong kind of thing.
if [[ $drop_origin -eq 0 && -n "${origin_url:-}" ]]; then
    clone_block="Co-authors clone it with:

\`\`\`sh
git clone --recurse-submodules $origin_url
\`\`\`"
else
    clone_block="This paper has no remote yet. Once it has one, co-authors clone it with \\\`git clone --recurse-submodules\\\`, giving that URL."
fi

# The title is printed, not interpolated: an unquoted heredoc would execute a
# backtick and substitute a $ in someone's title.
{
    printf '# %s\n' "$title"
    cat <<'MARKDOWN'

## Writing

Prose lives in `main.md`. Everything after the `{#sec:supp}` heading is supplementary material and is split into its own document at build time.

Metadata — title, authors, affiliations, target journal, citation style — lives in `paper.yml`, and nowhere else.

| To write | Use |
|---|---|
| a citation | `[@key]`, `[@one; @two]`, or `@key` in text |
| a figure | `![Caption.](figures/flow.png){#fig:flow}`, referenced as `@fig:flow` |
| a table | a `::: {#tbl:baseline}` div holding the caption, referenced as `@tbl:baseline` |
| the supplement boundary | `# Supplementary Material {#sec:supp}` |
| a checklist anchor | `{.checklist-strobe-4}` on a heading, or a `::: {.checklist-record-6}` div — any instrument |
| a Word paragraph style | `::: {.style-abstract}` |
| a note to a co-author | `[text]{.coauthor-comment author="AL" date="2026-08-12"}` — highlighted in every output, never mistakable for prose |

Figures go in `figures/`, tables in `tables/`, produced by whatever makes your tables. Neither is authored inline. Numbering is automatic: main items are `Figure 1`, supplementary items are `Figure S1`, and a reference from the main text to a supplementary figure resolves because both builds see the whole manuscript.

## Building

```sh
make docx       # main.docx + supplement.docx
make pdf        # main.pdf via Typst
make bib        # refresh references.bib from Zotero
make submit     # journal-ready bundle
make check      # confirm the engine still produces the same documents
make lint       # yamllint over paper.yml
make clean      # remove build/
```

Outputs land in `build/`, which is not tracked.

## Revision

`make docx-live` builds a DOCX whose citations are real Zotero fields rather than formatted text, so co-authors can add and refresh references in Word. Open Zotero's document preferences once before the first Refresh. It needs Zotero running with Better BibTeX.

## The engine

`engine/` is a git submodule holding the build machinery, pinned to one tagged release. It is not part of this repository beyond the commit it points at, so this paper builds the same way in five years as it does today.

**Co-authors clone with submodules**, or `engine/` arrives empty and every target that needs it refuses to run. Someone who has already cloned without it can run `git submodule update --init`, and after any `git pull` that moves the pin, `git submodule update --init --recursive` — a plain pull leaves the old engine in place and the paper still builds, silently, against it.

MARKDOWN
    printf '%s\n' "$clone_block"
    cat <<'MARKDOWN'

To move this paper to a newer engine — a deliberate act, never something a build does:

```sh
git submodule update --remote engine
git -C engine describe --tags        # what you moved to
git add engine && git commit -m "Engine $(git -C engine describe --tags)"
```

`engine/CHANGELOG.md` says what changed. `make check` builds the engine's own test papers and tells you whether your output would move with it.

## Requirements

pandoc, pandoc-crossref, yq, typst, and python3 with PyYAML. `make lint` uses uvx.
MARKDOWN
} > "$ROOT/README.md"

# Drop the init block. It carries its own .PHONY, so this one edit removes the
# target, its lint companion and both declarations, with nothing left to patch.
tmp=$(mktemp)
sed '/^# >>> template-init$/,/^# <<< template-init$/d' "$ROOT/Makefile" > "$tmp"
# Command substitution strips the trailing blank line the deleted block leaves.
printf '%s\n' "$(cat "$tmp")" > "$tmp.out"
# mktemp creates 0600, and mv within a volume is a rename that keeps the mode.
chmod 644 "$tmp.out"
mv "$tmp.out" "$ROOT/Makefile"
rm -f "$tmp"

rm -rf "$ROOT/CLAUDE.md" "$ROOT/.claude" "$ROOT/CHANGELOG.md"

# Last, and never anything under engine/: deleting a file the engine tracks
# would leave the submodule permanently modified in every clone. Bash keeps
# reading this script through its open descriptor after the unlink.
rm -rf "$ROOT/.template"

echo
echo "  wrote    paper.yml"
echo "  wrote    README.md"
echo "  removed  CLAUDE.md .claude/ CHANGELOG.md"
echo "  removed  the init target and the template's scaffolding"
echo "  kept     engine/ at $(git -C "$ROOT/engine" describe --tags 2>/dev/null || echo 'its pinned commit')"

##############################  Phase 3 — git  ################################

# A clone carries the template's commit history, and with it the record of how
# the template was written. That belongs to the template, not to the paper.
#
# Phase 0 has already refused if any ref but the current branch exists, so what
# this offers to delete is that branch and its commits, and nothing else.
if [[ $in_git -eq 1 ]]; then
    commits=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)
    echo
    printf '  Branch %s has %s commit(s), all of them the clone'"'"'s history.\n' "$branch" "$commits"
    printf '  Replace with a single commit for this paper? This cannot be undone. [y/N]: '
    read -r answer || answer=""

    if [[ "${answer:-n}" =~ ^[Yy] ]]; then
        trap 'echo "[init] FAILED before the history was replaced. Nothing is lost — restore with:" >&2
              echo "[init]        git -C \"$ROOT\" checkout -f $branch" >&2' ERR

        # --orphan leaves the index and working tree exactly as they are, so the
        # engine gitlink is inherited rather than rebuilt, and .git/modules/ is
        # never touched. submodule.recurse=false in case the user set it globally.
        git -C "$ROOT" -c submodule.recurse=false checkout -q --orphan __paper_init
        git -C "$ROOT" add -A
        # --no-verify: this keeps the template clone's .git, so its hooks and any
        # global core.hooksPath came with it, and they belong to the template.
        git -C "$ROOT" commit -q --no-verify -m "Start $title"
        recover_hint="Nothing is lost — restore with: git -C \"$ROOT\" checkout -f $branch"

        # A newly added, globally ignored paper file would be missing from the
        # paper's only commit and say nothing. Checked while that commit is
        # still undoable.
        for f in paper.yml main.md references.bib Makefile .gitmodules; do
            git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
                || die "$f did not reach the commit. Check core.excludesfile."
        done

        # Everything above this line is undoable by the command the trap prints,
        # and nothing below it is. The message has to change with the fact.
        trap 'echo "[init] FAILED while replacing the history." >&2
              echo "[init]        Your paper is committed on __paper_init and the working tree is intact." >&2
              echo "[init]        The template refs may be partly deleted; finish with:" >&2
              echo "[init]        git -C \"$ROOT\" branch -M '"'"'$branch'"'"'" >&2' ERR

        ############ point of no return: the first ref deletion ############
        if [[ $drop_origin -eq 1 ]]; then
            for r in $(git -C "$ROOT" remote); do
                git -C "$ROOT" remote remove "$r"
            done
        fi
        # Every ref except the one being kept: refs/stash, notes, refs/original
        # and refs/bisect each hold the old history alive on their own.
        #
        # Filtered with grep -vxF rather than for-each-ref --exclude, which
        # needs git 2.42 — newer than Debian 12 or Ubuntu 22.04 ship. -x -F
        # matches the whole line literally, so a branch name containing regex
        # metacharacters is compared as text; `|| true` covers grep's exit 1
        # when it filters everything out.
        git -C "$ROOT" for-each-ref --format='%(refname)' refs \
          | { grep -vxF "refs/heads/__paper_init" || true; } \
          | awk '{ print "option no-deref"; print "delete " $0 }' \
          | git -C "$ROOT" update-ref --stdin

        # The sweep ran while HEAD was still __paper_init, so the rename is the
        # last step and cannot leave the branch pointing at deleted refs.
        git -C "$ROOT" branch -q -M "$branch"

        # Not reachability roots — gc prunes the old history with these in place.
        # Removed so none is left printing a sha that no longer resolves.
        gitdir=$(git -C "$ROOT" rev-parse --absolute-git-dir)
        rm -f "$gitdir/ORIG_HEAD" "$gitdir/FETCH_HEAD" "$gitdir/MERGE_HEAD" "$gitdir/AUTO_MERGE"
        trap - ERR

        # Hygiene, not the mechanism: the refs are already gone, so a push sends
        # only reachable objects whether or not this succeeds.
        git -C "$ROOT" reflog expire --expire=now --all || true
        if [[ $skip_gc -eq 0 ]]; then
            git -C "$ROOT" gc --prune=now --quiet || true
        fi

        echo "  replaced the template's history with one commit"
        [[ $drop_origin -eq 1 ]] && echo "  removed  the template's remotes — origin pointed at the template"
    else
        echo "  kept the existing history"
        echo
        # No title in the suggested command: an apostrophe in it would end the
        # quoting and hand the reader something that does not run.
        echo "  Still to do: commit the files this just wrote,"
        echo "               git add -A && git commit"
        [[ $drop_origin -eq 1 ]] && echo "               and repoint origin, which is still the template's."
    fi
fi

echo
echo "Next: write main.md, then 'make docx'."
