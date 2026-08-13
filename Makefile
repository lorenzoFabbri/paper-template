# Build targets for a paper. Run `make help` for the list.
#
# Every setting comes from paper.yml. There are no variables to pass on the
# command line and none to edit here.
#
# engine/ is a git submodule pinned to a tagged release. It is not part of this
# repository's history beyond the commit it points at, so a paper builds the
# same way in five years as it does today.

# CURDIR rather than $(abspath $(MAKEFILE_LIST)): make's path functions split
# their argument on whitespace, so a paper kept under "My Papers/" would
# otherwise resolve to nothing.
ROOT := $(CURDIR)
ENGINE := $(ROOT)/engine
BUILD := $(ROOT)/build

PAPER_YML := $(ROOT)/paper.yml
MAIN_MD := $(ROOT)/main.md
REFERENCES_BIB := $(ROOT)/references.bib

DRIVER := $(ENGINE)/run-pipeline.sh
PACKAGER := $(ENGINE)/rename_for_submission.py
PIPELINE_YML := $(ENGINE)/pipeline.yml

# Read once, with := rather than =, so yq runs a fixed number of times instead
# of once per expansion.
JOURNAL := $(shell yq -r '.build.journal // ""' "$(PAPER_YML)" 2>/dev/null)
CSL_NAME := $(shell yq -r '.build.csl // ""' "$(PAPER_YML)" 2>/dev/null)
TYPST_THEME := $(shell yq -r '.build.typst-theme // ""' "$(PAPER_YML)" 2>/dev/null)
ZOTERO_COLLECTION := $(shell yq -r '.build.zotero-collection // ""' "$(PAPER_YML)" 2>/dev/null)

CSL_FILE := $(ENGINE)/styles/$(CSL_NAME).csl

# A reference-doc.docx beside paper.yml overrides the engine's; without either,
# pandoc's built-in DOCX styles are used. Which of the three applies is decided
# by the driver, which can test a path containing spaces and make cannot.
REFERENCE_DOCX := $(ROOT)/reference-doc.docx

# Pinned: unpinned, uvx resolves to whatever is newest, so the same tree
# passes on one machine and fails on another as default rule sets grow.
SHELLCHECK := shellcheck-py==0.11.0.1
YAMLLINT := yamllint@1.38.0

DOCX_MAIN := $(BUILD)/main.docx
DOCX_SUPP := $(BUILD)/supplement.docx
PDF := $(BUILD)/main.pdf

.PHONY: help docx docx-live pdf bib submit check lint clean precheck engine-present

help:
	@echo "make docx       build main.docx + supplement.docx"
	@echo "make docx-live  same, with live Zotero citations you can refresh in Word"
	@echo "make pdf        build main.pdf via Typst (main text and supplement in one file)"
	@echo "make bib        refresh references.bib from your Zotero collection"
	@echo "make submit     package a journal-ready bundle for build.journal"
	@echo "make check      build the engine's test papers and check them against their manuscripts"
	@echo "make lint       yamllint over paper.yml"
	@echo "make clean      remove build/"
	@test -f "$(ROOT)/.template/init-paper.sh" \
		&& echo "make init       turn this template into your paper (run once, first)" \
		|| true

# Cloning without --recurse-submodules leaves engine/ an empty directory, and
# every target below would otherwise fail with a bare "No such file or
# directory" from the shell.
engine-present:
	@test -f "$(DRIVER)" || { \
		echo "[paper] ERROR: engine/ is empty — the engine is a git submodule." >&2; \
		echo "[paper]        Run: git submodule update --init" >&2; exit 1; }

# yq reads build.journal and build.csl, so a missing yq surfaces as an empty
# setting and an error blaming paper.yml. Every target that reads it says so.
have-yq:
	@command -v yq >/dev/null || { \
		echo "[paper] ERROR: yq not on PATH; paper.yml cannot be read." >&2; \
		echo "[paper]        Install mikefarah/yq v4: https://github.com/mikefarah/yq" >&2; exit 1; }

precheck: engine-present have-yq
	@test -f "$(PAPER_YML)" || { echo "[paper] ERROR: paper.yml missing" >&2; exit 1; }
	@test -f "$(MAIN_MD)" || { echo "[paper] ERROR: main.md missing" >&2; exit 1; }
	@yq -e '.build' "$(PAPER_YML)" >/dev/null 2>&1 || { echo "[paper] ERROR: paper.yml has no build: block, or is not valid YAML" >&2; exit 1; }
	@mkdir -p "$(BUILD)"

# An empty setting in paper.yml must not reach the driver as a bare flag.
# Paths are passed whether or not they exist; the driver resolves them.
_DOCX_OPTS = $(if $(CSL_NAME),--csl-name "$(CSL_NAME)" --csl "$(CSL_FILE)",)
_DOCX_OPTS += --reference-doc "$(REFERENCE_DOCX)"

docx: precheck
	@test -f "$(REFERENCES_BIB)" || { echo "[paper] ERROR: references.bib missing; run 'make bib'" >&2; exit 1; }
	@"$(DRIVER)" --input "$(MAIN_MD)" --metadata-file "$(PAPER_YML)" \
		--pipeline "$(PIPELINE_YML)" --format docx --bib-mode static \
		$(_DOCX_OPTS) --bibliography "$(REFERENCES_BIB)" \
		--out-main "$(DOCX_MAIN)" --out-supplement "$(DOCX_SUPP)"
	@echo "[paper] $(DOCX_MAIN)"
	@echo "[paper] $(DOCX_SUPP)"

# Citations become Zotero fields rather than formatted text, so co-authors can
# add and refresh references in Word during revision.
docx-live: precheck
	@"$(DRIVER)" --input "$(MAIN_MD)" --metadata-file "$(PAPER_YML)" \
		--pipeline "$(PIPELINE_YML)" --format docx --bib-mode live \
		$(_DOCX_OPTS) --bibliography "$(REFERENCES_BIB)" \
		--out-main "$(DOCX_MAIN)" --out-supplement "$(DOCX_SUPP)"
	@echo "[paper] $(DOCX_MAIN) — open Zotero's document preferences once, then Refresh"

pdf: precheck
	@test -f "$(REFERENCES_BIB)" || { echo "[paper] ERROR: references.bib missing; run 'make bib'" >&2; exit 1; }
	@"$(DRIVER)" --input "$(MAIN_MD)" --metadata-file "$(PAPER_YML)" \
		--pipeline "$(PIPELINE_YML)" --format typst --bib-mode static \
		$(if $(TYPST_THEME),--theme "$(TYPST_THEME)",) \
		$(if $(CSL_NAME),--csl-name "$(CSL_NAME)" --csl "$(CSL_FILE)",) \
		--bibliography "$(REFERENCES_BIB)" --out "$(PDF)"
	@echo "[paper] $(PDF)"

bib: engine-present have-yq
	@test -n "$(ZOTERO_COLLECTION)" || { echo "[paper] ERROR: set build.zotero-collection in paper.yml" >&2; exit 1; }
	@"$(ENGINE)/refresh-bib.sh" "$(ZOTERO_COLLECTION)" "$(REFERENCES_BIB)"

# The journal is checked before the build, so a missing key fails in a second
# rather than after two pandoc runs.
submit: engine-present have-yq
	@test -n "$(JOURNAL)" || { echo "[paper] ERROR: set build.journal in paper.yml" >&2; exit 1; }
	@test -f "$(ENGINE)/styles/submission-rules/$(JOURNAL).yml" || { echo "[paper] ERROR: no profile for journal '$(JOURNAL)'" >&2; exit 1; }
	@$(MAKE) --no-print-directory docx
	@python3 "$(PACKAGER)" --paper-root "$(ROOT)" --journal "$(JOURNAL)" \
		--out "$(BUILD)/submission-$(JOURNAL).zip"

# The engine's own suite: it builds four complete papers with this same driver
# and checks each against its manuscript. Run it after a pandoc upgrade, or
# after moving to a newer engine, to see whether your output would change.
#
# Recording the goldens again is `make check-regenerate` in the engine's own
# repository. It rewrites files this paper does not own.
check: engine-present
	@"$(ENGINE)/tests/run-tests.sh"

lint: engine-present
	@uvx --quiet "$(YAMLLINT)" -c "$(ENGINE)/.yamllint" "$(PAPER_YML)" "$(ROOT)/.github/workflows/"
	@echo "[paper] lint clean"

clean:
	@rm -rf "$(BUILD)"
	@echo "[paper] removed $(BUILD)"

# >>> template-init
# Turns the template into your paper: writes paper.yml, replaces the README,
# and removes the template's own scaffolding along with this whole block. The
# block is self-contained, so deleting it leaves no target and no .PHONY entry
# behind — which is why `init` is absent from the .PHONY line above.
.PHONY: init lint-init
lint: lint-init
lint-init:
	@uvx --quiet --from "$(SHELLCHECK)" shellcheck --shell=bash "$(ROOT)/.template/init-paper.sh"
init: engine-present
	@"$(ROOT)/.template/init-paper.sh" "$(ROOT)"
# <<< template-init
