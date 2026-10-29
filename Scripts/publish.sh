#!/bin/zsh
# Publishes the version in project.yml: notarized DMG, git tag, GitHub Release
# and the Homebrew cask in falconsw/homebrew-tap.
#
#   make publish              # or Scripts/publish.sh
#   DRY_RUN=1 make publish    # checks and prints the release notes, publishes nothing
#
# Before running: bump MARKETING_VERSION in project.yml, add a ReleaseNote for
# it in Sources/Settings/ReleaseNotes.swift, commit and push.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=falconsw/Leftover
TAP=falconsw/homebrew-tap
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
TAG="v$VERSION"
DMG="dist/Leftover-$VERSION.dmg"
fail() { echo "publish: $*" >&2; exit 1; }

# Every check runs before anything is built or published.
[[ "$(git branch --show-current)" == main ]] || fail "not on main"
[[ -z "$(git status --porcelain)" ]] || fail "uncommitted changes"
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not pushed (or is behind origin)"
git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1 && fail "$TAG already exists; bump MARKETING_VERSION first"

# The release notes the app shows in What's New, as Markdown.
NOTES=$(python3 - "$VERSION" <<'EOF'
import re, sys
version = sys.argv[1]
src = open("Sources/Settings/ReleaseNotes.swift").read()
blocks = re.split(r"\n\s*ReleaseNote\(\n", src)
block = next((b for b in blocks if re.search(r'version:\s*"%s"' % re.escape(version), b)), None)
if block is None:
    sys.exit(f"no ReleaseNote for {version} in ReleaseNotes.swift")
t = lambda s: re.findall(r'%s:\s*L10n\.t\("((?:[^"\\]|\\.)*)"\)' % s, block)
headline = t("headline")
lines = [headline[0], ""] if headline else []
lines += [f"- **{title}.** {detail}" for title, detail in zip(t("title"), t("detail"))]
lines += ["", "Install with Homebrew:", "", "```sh", "brew install --cask falconsw/tap/leftover", "```",
          "", "Requires macOS 15 or later."]
print("\n".join(lines))
EOF
) || fail "release notes"

echo "Leftover $VERSION ($TAG)"
echo "----"; echo "$NOTES"; echo "----"
if [[ -n "${DRY_RUN:-}" ]]; then echo "DRY_RUN: checks passed, nothing published."; exit 0; fi

Scripts/release.sh
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

git tag -a "$TAG" -m "Leftover $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" "$DMG" -R "$REPO" --verify-tag --title "Leftover $VERSION" --notes "$NOTES"

# What users download must be what was notarized here.
REMOTE_SHA=$(curl -sfL "https://github.com/$REPO/releases/download/$TAG/Leftover-$VERSION.dmg" | shasum -a 256 | cut -d' ' -f1)
[[ "$REMOTE_SHA" == "$SHA" ]] || fail "downloaded DMG does not match ($REMOTE_SHA != $SHA); cask not updated"

TAPDIR=$(mktemp -d)
trap 'rm -rf "$TAPDIR"' EXIT
gh repo clone "$TAP" "$TAPDIR" -- -q
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAPDIR/Casks/leftover.rb"
git -C "$TAPDIR" add Casks/leftover.rb
git -C "$TAPDIR" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
  commit -q -m "leftover $VERSION"
git -C "$TAPDIR" push -q origin HEAD

echo "Published Leftover $VERSION"
echo "  https://github.com/$REPO/releases/tag/$TAG"
echo "  brew upgrade --cask leftover"
