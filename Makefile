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

# Assemble, embed Sparkle into, and sign build/Kivodo.app. The heavy lifting
# lives in scripts/build_app.sh so local dev and CI share one build path.
app: $(ICON)
	CONFIGURATION=release scripts/build_app.sh

run: app
	-pkill -x Kivodo
	open $(APP)

test:
	swift test

clean:
	rm -rf build .build
