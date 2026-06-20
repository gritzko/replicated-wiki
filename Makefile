#   replicated.wiki — build the StrictMark wiki to static HTML for GitHub Pages.
#
#   Every **/*.mkd source renders to html/**/*.html via `mark`, the Beagle wiki
#   renderer (see wiki/Mark.mkd). `mark` rewrites inter-page .mkd links to .html,
#   so the html/ tree is self-contained and serves as a plain static site — no
#   Jekyll, no server-side build.
#
#   html/ is a git submodule — its own repo (gritzko/replicated.live), the
#   GitHub Pages site at replicated.live (this parent repo mirrors it at
#   replicated.wiki). `mark` is NOT on the Pages runners, so the committed
#   html/ tree IS the deployed site. Regenerate, then publish from the submodule
#   and bump the gitlink in this repo (or just `make publish`):
#
#       make
#       cd html && git add -A && git commit -m rebuild && git push && cd ..
#       git add html && git commit -m 'wiki: bump site'
#
#   Targets:
#       make            render everything into html/   (default)
#       make publish    render, commit+push the html/ submodule, bump the gitlink
#       make strict     render with StrictMark budget linting (fails on a breach)
#       make serve      preview the built site at http://localhost:8000
#       make clean      empty html/   (keeps the submodule checkout)

# MARK: the StrictMark renderer (override with `make MARK=/path/to/mark`).
# OUT:  output tree (a git submodule), served as the site root by GitHub Pages.
# HEAD: HTML snippet inlined into every page's <head> (stylesheet, favicon...).
# BODY: HTML snippet inlined after <body> on every page (the top banner).
# MARKFLAGS: `make strict` sets this to --strict.
# SITE_CNAME: domain baked into html/CNAME — the html submodule's OWN domain
#   (replicated.live). The parent's Pages workflow stamps replicated.wiki over it.
MARK ?= mark
OUT ?= html
HEAD ?= head.html
BODY ?= banner.html
MARKFLAGS ?=
SITE_CNAME ?= replicated.live

# Every StrictMark source, minus the output tree and git internals.
SRC  := $(shell find . -name '*.mkd' -not -path './$(OUT)/*' -not -path './.git/*')
HTML := $(patsubst ./%.mkd,$(OUT)/%.html,$(SRC))

# Image directories are copied verbatim beside their pages.
IMGDIRS := $(patsubst ./%,%,$(shell find . -type d -name img -not -path './$(OUT)/*' -not -path './.git/*'))

.PHONY: all publish strict serve clean indexes assets
all: $(HTML) indexes assets

# One page. `mark` only ever writes a sibling .html, so stage the source inside
# the output tree, render it in place, then drop the staged copy. --root=. is
# the `/` anchor for absolute `[/...]` links and the source tree probed to
# decide .mkd->.html; absolute hrefs are depth-independent, so the staged copy's
# location does not matter. --head inlines the shared <head> snippet and --body
# the top banner, so editing either re-renders every page.
$(OUT)/%.html: %.mkd $(HEAD) $(BODY)
	@mkdir -p $(@D)
	@cp $< $(@D)/
	@$(MARK) $(MARKFLAGS) --root=. --head=$(HEAD) --body=$(BODY) $(@D)/$(<F)
	@rm -f $(@D)/$(<F)

# Directory landing pages: Home (the wiki) and every README become index.html.
indexes: $(HTML)
	@[ -f $(OUT)/wiki/Home.html ] && cp $(OUT)/wiki/Home.html $(OUT)/wiki/index.html || true
	@find $(OUT) -name README.html -exec sh -c 'cp "$$1" "$$(dirname "$$1")/index.html"' _ {} \;

# Images, root-level dir symlinks (e.g. rule -> skill), the html site's custom
# domain (SITE_CNAME), and .nojekyll (tells Pages to serve raw, not via Jekyll).
assets: $(HTML)
	@for d in $(IMGDIRS); do mkdir -p $(OUT)/$$d && cp -r $$d/. $(OUT)/$$d/; done
	@mkdir -p $(OUT)/assets/css && cp assets/css/style.css $(OUT)/assets/css/
	@mkdir -p $(OUT)/assets/img && cp -r assets/img/. $(OUT)/assets/img/
	@for l in $$(find . -maxdepth 1 -type l); do t=$$(readlink $$l); n=$$(basename $$l); \
		[ -d $(OUT)/$$t ] && rm -rf $(OUT)/$$n && cp -r $(OUT)/$$t $(OUT)/$$n || true; done
	@printf '%s\n' '$(SITE_CNAME)' > $(OUT)/CNAME
	@touch $(OUT)/.nojekyll

# Lint every page against the StrictMark budgets; a full re-render so nothing is
# skipped as up-to-date. Fails (non-zero) on the first breach — use this in CI.
strict: clean
	@$(MAKE) MARKFLAGS=--strict all

serve: all
	@python3 -m http.server -d $(OUT) 8000

# Publish: html/ is its own repo (the GitHub Pages site). Clean-rebuild (so a
# deleted source's stale page can't linger), commit + push inside the submodule,
# then record the new tip as a gitlink bump here. MSG overrides the site message.
MSG ?= site: rebuild
publish:
	@$(MAKE) clean all
	@cd $(OUT) && git add -A && git commit -m "$(MSG)" && git push
	@git add $(OUT) && git commit -m "wiki: bump site"

# Empty the output tree WITHOUT removing html/.git (the submodule's gitdir
# pointer) — a plain `rm -rf html` would de-init the submodule. With no
# submodule yet this just clears html/'s contents, which `make` recreates.
clean:
	@[ -d $(OUT) ] && find $(OUT) -mindepth 1 -maxdepth 1 -name .git -prune -o -exec rm -rf {} + || true
