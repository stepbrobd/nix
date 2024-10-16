# The version of Nix used to generate the doc. Can also be
# `$(nix_INSTALL_PATH)` or just `nix` (to grap ambient from the `PATH`),
# if one prefers.
doc_nix = $(nix_PATH)

MANUAL_SRCS := \
	$(call rwildcard, $(d)/source, *.md) \
	$(call rwildcard, $(d)/source, */*.md)

man-pages := $(foreach n, \
	nix-env.1 nix-store.1 \
	nix-build.1 nix-shell.1 nix-instantiate.1 \
	nix-collect-garbage.1 \
	nix-prefetch-url.1 nix-channel.1 \
	nix-hash.1 nix-copy-closure.1 \
	nix.conf.5 nix-daemon.8 \
	nix-profiles.5 \
, $(d)/$(n))

# man pages for subcommands
# convert from `$(d)/source/command-ref/nix-{1}/{2}.md` to `$(d)/nix-{1}-{2}.1`
# FIXME: unify with how nix3-cli man pages are generated
man-pages += $(foreach subcommand, \
	$(filter-out %opt-common.md %env-common.md, $(wildcard $(d)/source/command-ref/nix-*/*.md)), \
	$(d)/$(subst /,-,$(subst $(d)/source/command-ref/,,$(subst .md,.1,$(subcommand)))))

clean-files += $(d)/*.1 $(d)/*.5 $(d)/*.8

# Provide a dummy environment for nix, so that it will not access files outside the macOS sandbox.
# Set cores to 0 because otherwise `nix config show` resolves the cores based on the current machine
dummy-env = env -i \
	HOME=/dummy \
	NIX_CONF_DIR=/dummy \
	NIX_SSL_CERT_FILE=/dummy/no-ca-bundle.crt \
	NIX_STATE_DIR=/dummy \
	NIX_CONFIG='cores = 0'

nix-eval = $(dummy-env) $(doc_nix) eval --experimental-features nix-command -I nix=doc/manual --store dummy:// --impure --raw

# re-implement mdBook's include directive to make it usable for terminal output and for proper @docroot@ substitution
define process-includes
	while read -r line; do \
		set -euo pipefail; \
		filename="$$(dirname $(1))/$$(sed 's/{{#include \(.*\)}}/\1/'<<< $$line)"; \
		test -f "$$filename" || ( echo "#include-d file '$$filename' does not exist." >&2; exit 1; ); \
		matchline="$$(sed 's|/|\\/|g' <<< $$line)"; \
		sed -i "/$$matchline/r $$filename" $(2); \
		sed -i "s/$$matchline//" $(2); \
	done < <(grep '{{#include' $(1))
endef

$(d)/nix-env-%.1: $(d)/source/command-ref/nix-env/%.md
	@printf "Title: %s\n\n" "$(subst nix-env-,nix-env --,$$(basename "$@" .1))" > $^.tmp
	$(render-subcommand)

$(d)/nix-store-%.1: $(d)/source/command-ref/nix-store/%.md
	@printf -- 'Title: %s\n\n' "$(subst nix-store-,nix-store --,$$(basename "$@" .1))" > $^.tmp
	$(render-subcommand)

# FIXME: there surely is some more deduplication to be achieved here with even darker Make magic
define render-subcommand
  @cat $^ >> $^.tmp
	@$(call process-includes,$^,$^.tmp)
	$(trace-gen) lowdown -sT man --nroff-nolinks -M section=1 $^.tmp -o $@
	@# fix up `lowdown`'s automatic escaping of `--`
	@# https://github.com/kristapsdz/lowdown/blob/edca6ce6d5336efb147321a43c47a698de41bb7c/entity.c#L202
	@sed -i 's/\e\[u2013\]/--/' $@
	@rm $^.tmp
endef


$(d)/%.1: $(d)/source/command-ref/%.md
	@printf "Title: %s\n\n" "$$(basename $@ .1)" > $^.tmp
	@cat $^ >> $^.tmp
	@$(call process-includes,$^,$^.tmp)
	$(trace-gen) lowdown -sT man --nroff-nolinks -M section=1 $^.tmp -o $@
	@rm $^.tmp

$(d)/%.8: $(d)/source/command-ref/%.md
	@printf "Title: %s\n\n" "$$(basename $@ .8)" > $^.tmp
	@cat $^ >> $^.tmp
	$(trace-gen) lowdown -sT man --nroff-nolinks -M section=8 $^.tmp -o $@
	@rm $^.tmp

$(d)/nix.conf.5: $(d)/source/command-ref/conf-file.md
	@printf "Title: %s\n\n" "$$(basename $@ .5)" > $^.tmp
	@cat $^ >> $^.tmp
	@$(call process-includes,$^,$^.tmp)
	$(trace-gen) lowdown -sT man --nroff-nolinks -M section=5 $^.tmp -o $@
	@rm $^.tmp

$(d)/nix-profiles.5: $(d)/source/command-ref/files/profiles.md
	@printf "Title: %s\n\n" "$$(basename $@ .5)" > $^.tmp
	@cat $^ >> $^.tmp
	$(trace-gen) lowdown -sT man --nroff-nolinks -M section=5 $^.tmp -o $@
	@rm $^.tmp

$(d)/source/SUMMARY.md: $(d)/source/SUMMARY.md.in $(d)/source/SUMMARY-rl-next.md $(d)/source/store/types $(d)/source/command-ref/new-cli $(d)/source/development/experimental-feature-descriptions.md
	@cp $< $@
	@$(call process-includes,$@,$@)

$(d)/source/store/types: $(d)/nix.json $(d)/utils.nix $(d)/generate-store-info.nix  $(d)/generate-store-types.nix $(d)/source/store/types/index.md.in $(doc_nix)
	@# FIXME: build out of tree!
	@rm -rf $@.tmp
	$(trace-gen) $(nix-eval) --write-to $@.tmp --expr 'import doc/manual/generate-store-types.nix (builtins.fromJSON (builtins.readFile $<)).stores'
	@# do not destroy existing contents
	@mv $@.tmp/* $@/

$(d)/source/command-ref/new-cli: $(d)/nix.json $(d)/utils.nix $(d)/generate-manpage.nix $(d)/generate-settings.nix $(d)/generate-store-info.nix $(doc_nix)
	@rm -rf $@ $@.tmp
	$(trace-gen) $(nix-eval) --write-to $@.tmp --expr 'import doc/manual/generate-manpage.nix true (builtins.readFile $<)'
	@mv $@.tmp $@

$(d)/source/command-ref/conf-file.md: $(d)/conf-file.json $(d)/utils.nix $(d)/generate-settings.nix $(d)/source/command-ref/conf-file-prefix.md $(d)/source/command-ref/experimental-features-shortlist.md $(doc_nix)
	@cat doc/manual/source/command-ref/conf-file-prefix.md > $@.tmp
	$(trace-gen) $(nix-eval) --expr 'import doc/manual/generate-settings.nix { prefix = "conf"; } (builtins.fromJSON (builtins.readFile $<))' >> $@.tmp;
	@mv $@.tmp $@

$(d)/nix.json: $(doc_nix)
	$(trace-gen) $(dummy-env) $(doc_nix) __dump-cli > $@.tmp
	@mv $@.tmp $@

$(d)/conf-file.json: $(doc_nix)
	$(trace-gen) $(dummy-env) $(doc_nix) config show --json --experimental-features nix-command > $@.tmp
	@mv $@.tmp $@

$(d)/source/development/experimental-feature-descriptions.md: $(d)/xp-features.json $(d)/utils.nix $(d)/generate-xp-features.nix $(doc_nix)
	@rm -rf $@ $@.tmp
	$(trace-gen) $(nix-eval) --write-to $@.tmp --expr 'import doc/manual/generate-xp-features.nix (builtins.fromJSON (builtins.readFile $<))'
	@mv $@.tmp $@

$(d)/source/command-ref/experimental-features-shortlist.md: $(d)/xp-features.json $(d)/utils.nix $(d)/generate-xp-features-shortlist.nix $(doc_nix)
	@rm -rf $@ $@.tmp
	$(trace-gen) $(nix-eval) --write-to $@.tmp --expr 'import doc/manual/generate-xp-features-shortlist.nix (builtins.fromJSON (builtins.readFile $<))'
	@mv $@.tmp $@

$(d)/xp-features.json: $(doc_nix)
	$(trace-gen) $(dummy-env) $(doc_nix) __dump-xp-features > $@.tmp
	@mv $@.tmp $@

$(d)/source/language/builtins.md: $(d)/language.json $(d)/generate-builtins.nix $(d)/source/language/builtins-prefix.md $(doc_nix)
	@cat doc/manual/source/language/builtins-prefix.md > $@.tmp
	$(trace-gen) $(nix-eval) --expr 'import doc/manual/generate-builtins.nix (builtins.fromJSON (builtins.readFile $<))' >> $@.tmp;
	@cat doc/manual/source/language/builtins-suffix.md >> $@.tmp
	@mv $@.tmp $@

$(d)/language.json: $(doc_nix)
	$(trace-gen) $(dummy-env) $(doc_nix) __dump-language > $@.tmp
	@mv $@.tmp $@

# Generate "Upcoming release" notes (or clear it and remove from menu)
$(d)/source/release-notes/rl-next.md: $(d)/rl-next $(d)/rl-next/*
	@if type -p changelog-d > /dev/null; then \
		echo "  GEN   " $@; \
		changelog-d doc/manual/rl-next > $@; \
	else \
		echo "  NULL  " $@; \
		true > $@; \
	fi

$(d)/source/SUMMARY-rl-next.md: $(d)/source/release-notes/rl-next.md
	$(trace-gen) true
	@if [ -s $< ]; then \
		echo '  - [Upcoming release](release-notes/rl-next.md)' > $@; \
	else \
	  true > $@; \
	fi

# Generate the HTML manual.
.PHONY: manual-html
manual-html: $(docdir)/manual/index.html

# Open the built HTML manual in the default browser.
manual-html-open: $(docdir)/manual/index.html
	@echo "  OPEN  " $<; \
	  xdg-open $< \
		  || open $< \
			|| { \
		echo "Could not open the manual in a browser. Please open '$<'" >&2; \
		false; \
		}
install: $(docdir)/manual/index.html

# Generate 'nix' manpages.
.PHONY: manpages
manpages: $(mandir)/man1/nix3-manpages
install: $(mandir)/man1/nix3-manpages
man: doc/manual/generated/man1/nix3-manpages
all: doc/manual/generated/man1/nix3-manpages

# FIXME: unify with how the other man pages are generated.
# this one works differently and does not use any of the amenities provided by `/mk/lib.mk`.
$(mandir)/man1/nix3-manpages: doc/manual/generated/man1/nix3-manpages
	@mkdir -p $(DESTDIR)$$(dirname $@)
	$(trace-install) install -m 0644 $$(dirname $<)/* $(DESTDIR)$$(dirname $@)

doc/manual/generated/man1/nix3-manpages: $(d)/source/command-ref/new-cli
	@mkdir -p $(DESTDIR)$$(dirname $@)
	$(trace-gen) for i in doc/manual/source/command-ref/new-cli/*.md; do \
		name=$$(basename $$i .md); \
		tmpFile=$$(mktemp); \
		if [[ $$name = SUMMARY ]]; then continue; fi; \
		printf "Title: %s\n\n" "$$name" > $$tmpFile; \
		cat $$i >> $$tmpFile; \
		lowdown -sT man --nroff-nolinks -M section=1 $$tmpFile -o $(DESTDIR)$$(dirname $@)/$$name.1; \
		rm $$tmpFile; \
	done
	@touch $@

# the `! -name 'documentation.md'` filter excludes the one place where
# `@docroot@` is to be preserved for documenting the mechanism
# FIXME: maybe contributing guides should live right next to the code
# instead of in the manual
$(docdir)/manual/index.html: $(MANUAL_SRCS) $(d)/book.toml $(d)/anchors.jq $(d)/custom.css $(d)/source/SUMMARY.md $(d)/source/store/types $(d)/source/command-ref/new-cli $(d)/source/development/experimental-feature-descriptions.md $(d)/source/command-ref/conf-file.md $(d)/source/language/builtins.md $(d)/source/release-notes/rl-next.md $(d)/source/figures $(d)/source/favicon.png $(d)/source/favicon.svg
	$(trace-gen) \
		tmp="$$(mktemp -d)"; \
		cp -r doc/manual "$$tmp"; \
		find "$$tmp" -name '*.md' | while read -r file; do \
			$(call process-includes,$$file,$$file); \
		done; \
		find "$$tmp" -name '*.md' ! -name 'documentation.md' | while read -r file; do \
			docroot="$$(realpath --relative-to="$$(dirname "$$file")" $$tmp/manual/source)"; \
			sed -i "s,@docroot@,$$docroot,g" "$$file"; \
		done; \
		set -euo pipefail; \
		( \
		    cd "$$tmp/manual"; \
		    RUST_LOG=warn \
		        MDBOOK_SUBSTITUTE_SEARCH=$(d)/source \
		        mdbook build -d $(DESTDIR)$(docdir)/manual.tmp 2>&1 \
			    | { grep -Fv "because fragment resolution isn't implemented" || :; } \
		); \
		rm -rf "$$tmp/manual"
	@rm -rf $(DESTDIR)$(docdir)/manual
	@mv $(DESTDIR)$(docdir)/manual.tmp/html $(DESTDIR)$(docdir)/manual
	@rm -rf $(DESTDIR)$(docdir)/manual.tmp
