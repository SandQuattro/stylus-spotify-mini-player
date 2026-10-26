APP_NAME := Stylus
APP_ID   := com.kass.stylus
BIN_NAME := stylus
DEST     := /Applications/$(APP_NAME).app
MACOS    := src-tauri/target/release/bundle/macos
OUT      := /tmp/stylus-build
# release builds (make dmg) also make the signed update archive Stylus.app.tar.gz + .sig for the
# auto-updater (src-tauri/src/updater.rs) when the key file is here (empty password); plain builds
# (install, run) leave createUpdaterArtifacts off and need no key.
UPD_KEY  := ~/.config/stylus/updater.key
UPD_CONF := {\"bundle\":{\"createUpdaterArtifacts\":true}}
# the app under its old names (Needle, rust-spotify): quit it too, it shares the Connect device id
OLD_APP_IDS   := com.kass.needle com.kass.rustspotify
OLD_BIN_NAMES := Needle needle rust-spotify

.PHONY: install run stop test dmg release

## node_modules: npm ci again whenever package-lock.json is newer
node_modules: package-lock.json
	npm ci --silent

## test: frontend (vitest) and backend (cargo) tests
test: node_modules
	npx vitest run
	cargo test --manifest-path src-tauri/Cargo.toml --quiet

## install: release Stylus.app built here, put into /Applications (the old copy goes to /tmp/trash), then opened
install: node_modules
	npx tauri build --bundles app
	$(MAKE) stop
	@if [ -d "$(DEST)" ]; then mkdir -p /tmp/trash && mv "$(DEST)" "/tmp/trash/$(APP_NAME).app.$$(date +%Y%m%d-%H%M%S)"; fi
	@# the app under its old names: a second copy would be a second "This Mac" speaker
	@for old in Needle rust-spotify; do if [ -d "/Applications/$$old.app" ]; then mkdir -p /tmp/trash && mv "/Applications/$$old.app" "/tmp/trash/$$old.app.$$(date +%Y%m%d-%H%M%S)"; fi; done
	ditto "$(MACOS)/$(APP_NAME).app" "$(DEST)"
	@# LaunchServices refuses (-600) while the old copy is still exiting: wait, then retry once
	@sleep 2; open "$(DEST)" || { sleep 3; open "$(DEST)"; }

## run: fresh release build, run as a bare binary: no .app, so no Dock icon = the dev build
run: node_modules
	npx tauri build --no-bundle
	$(MAKE) stop
	src-tauri/target/release/$(BIN_NAME)

## dmg: $(OUT)/dmg/Stylus.dmg. With the updater key also the signed update archive a release needs
## (make release DMG=local); without it a DMG to install by hand.
## hdiutil, not Tauri's bundle_dmg.sh: that script drives Finder over AppleScript.
dmg: node_modules
	rm -rf $(OUT)/dmg $(OUT)/dmg-src
	mkdir -p $(OUT)/dmg $(OUT)/dmg-src
	@if [ -s $(UPD_KEY) ]; then \
		TAURI_SIGNING_PRIVATE_KEY="$$(cat $(UPD_KEY))" TAURI_SIGNING_PRIVATE_KEY_PASSWORD= npx tauri build --bundles app --config "$(UPD_CONF)" && \
		cp $(MACOS)/$(APP_NAME).app.tar.gz $(MACOS)/$(APP_NAME).app.tar.gz.sig $(OUT)/dmg/; \
	else \
		echo "no updater key $(UPD_KEY): the DMG comes without the update archive"; \
		npx tauri build --bundles app; \
	fi
	cp -R $(MACOS)/$(APP_NAME).app $(OUT)/dmg-src/
	ln -s /Applications $(OUT)/dmg-src/Applications
	hdiutil create -volname $(APP_NAME) -srcfolder $(OUT)/dmg-src -ov -format UDZO $(OUT)/dmg/$(APP_NAME).dmg
	rm -rf $(OUT)/dmg-src
	shasum -a 256 $(OUT)/dmg/$(APP_NAME).dmg

## release: version bump, tag, DMG, release notes and Homebrew cask in one run (scripts/release.py).
## V=0.3.1 NOTES=<file of "- " highlight lines> [DMG=local: build the DMG here (make dmg), not in CI] [DRY=1: change nothing]
release:
	@test -n "$(V)" -a -n "$(NOTES)" || { echo 'usage: make release V=0.3.1 NOTES=/tmp/notes.md [DMG=local] [DRY=1]'; exit 2; }
	python3 -u scripts/release.py $(V) --notes $(NOTES) --dmg $(or $(DMG),ci) $(if $(DRY),--dry-run)

## stop: quit every copy, installed (binary may be named Stylus) or dev, new name or old (two copies = two "This Mac" speakers with one device id)
stop:
	-@osascript -e 'if application id "$(APP_ID)" is running then tell application id "$(APP_ID)" to quit' >/dev/null 2>&1
	-@for id in $(OLD_APP_IDS); do osascript -e "if application id \"$$id\" is running then tell application id \"$$id\" to quit" >/dev/null 2>&1; done
	-@sleep 1; for p in $(APP_NAME) $(BIN_NAME) $(OLD_BIN_NAMES); do pkill -x $$p || true; done
