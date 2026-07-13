# Note: ad-hoc signing (--sign -) changes the code hash on every rebuild,
# so macOS may re-ask for Reminders permission after rebuilds. Acceptable
# for development.

APP = build/Kivodo.app
ICON = Assets/icon/Kivodo.icns
ICON_MASTER = Assets/icon/masters/kivodo-2b-frosted-panel.svg

.PHONY: app run test clean icon

# Regenerate the app icon (.icns) from the frosted master. Committed to the
# repo, so this only needs re-running when the master changes; needs an SVG
# rasterizer (brew install librsvg).
$(ICON): $(ICON_MASTER) Assets/icon/make-icns.sh
	Assets/icon/make-icns.sh masters/kivodo-2b-frosted-panel.svg Kivodo

icon: $(ICON)

# The app is built with the Swift Build engine (--build-system swiftbuild)
# because its generated Bundle.module accessor looks for package resource
# bundles in Contents/Resources, so the .app stays self-contained and
# relocatable. The default (native) engine bakes in an absolute .build path
# instead, which breaks once the app is separated from this repo.
app: $(ICON)
	swift build -c release --build-system swiftbuild
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	BIN="$$(swift build -c release --build-system swiftbuild --show-bin-path)"; \
	cp "$$BIN/Kivodo" $(APP)/Contents/MacOS/Kivodo && \
	cp -R "$$BIN"/*.bundle $(APP)/Contents/Resources/
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp $(ICON) $(APP)/Contents/Resources/Kivodo.icns
	codesign --force --sign - $(APP)

run: app
	-pkill -x Kivodo
	open $(APP)

test:
	swift test

clean:
	rm -rf build .build
