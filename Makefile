APP := build/DerivedData/Build/Products/Debug/Leftover.app

XCODEBUILD = xcodebuild -project Leftover.xcodeproj -scheme Leftover \
	-derivedDataPath build/DerivedData

.PHONY: gen build run release clean

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -configuration Debug build

run: build
	-pkill -x Leftover
	@while pgrep -x Leftover >/dev/null; do sleep 0.1; done
	open "$(APP)"

# Notarized DMG in dist/ for GitHub Releases and the Homebrew cask.
release:
	Scripts/release.sh

clean:
	rm -rf build dist
