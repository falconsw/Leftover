APP := build/DerivedData/Build/Products/Debug/Leftover.app
RELEASE_APP := build/DerivedData/Build/Products/Release/Leftover.app
VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)

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

# Developer ID-signed Release build, zipped for the Homebrew cask. Notarize
# the zip before publishing it.
release: gen
	@test -f Local.xcconfig || { echo "release needs Local.xcconfig (see Local.xcconfig.example)"; exit 1; }
	$(XCODEBUILD) -configuration Release build
	ditto -c -k --keepParent "$(RELEASE_APP)" build/Leftover-$(VERSION).zip
	@echo build/Leftover-$(VERSION).zip

clean:
	rm -rf build
