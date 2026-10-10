#!/bin/bash
# Puts out one version of the macOS app: builds, checks, packs and pushes it to GitHub.
#
#   ./macos/scripts/release.sh 0.1.0
#
# Tags are `v<version>` for the macOS app. A Windows release will need its own prefix.
set -euo pipefail

macos="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$macos/.." && pwd)"
cd "$root"

version="${1:-}"
if [ -z "$version" ]; then
  echo "usage: ./macos/scripts/release.sh <version>   e.g. ./macos/scripts/release.sh 0.1.0" >&2
  exit 1
fi

repo="piro0919/vocafy-visualizer"
plist="macos/Resources/Info.plist"
app="macos/dist/VocafyVisualizer.app"
dmg="VocafyVisualizer-${version}.dmg"

fail() {
  echo "error: $*" >&2
  exit 1
}

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "the version must look like 1.2.3 (got: ${version})"
fi

# The release commit below takes only the version file. Anything else lying around would either
# be left out of the tagged commit or be swept into it, so a dirty tree stops here.
if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  fail "the working tree has uncommitted changes; commit or stash them first"
fi
if [ "$(git branch --show-current)" != "main" ]; then
  fail "releases are cut from main"
fi
git fetch -q origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
  fail "HEAD is not on origin/main yet; push first"
fi
if git rev-parse -q --verify "refs/tags/v${version}" >/dev/null ||
  git ls-remote --exit-code --tags origin "refs/tags/v${version}" >/dev/null; then
  fail "tag v${version} already exists"
fi

# The release notes are this version's section of CHANGELOG.md.
notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
awk -v head="## [${version}]" '
  /^## / { if (found) exit; if (index($0, head) == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md >"$notes"
if ! grep -q '[^[:space:]]' "$notes"; then
  fail "CHANGELOG.md has no \"## [${version}]\" section, or it is empty"
fi

build_number=$(($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist") + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "$plist"
./macos/scripts/build.sh

built="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
[ "$built" = "$version" ] || fail "the built app says ${built}, expected ${version}"
codesign --verify --deep --strict "$app" || fail "the built app's signature does not verify"

# Whatever is about to be handed out is checked first.
"$app/Contents/MacOS/VocafyVisualizer" --selftest

./macos/scripts/dmg.sh >/dev/null

git add "$plist"
git commit -q -m "chore(release): ${version}"
git tag "v${version}"
git push -q origin main
git push -q origin "v${version}"

gh release create "v${version}" \
  --repo "$repo" \
  --title "Vocafy Visualizer ${version}" \
  --notes-file "$notes" \
  "macos/dist/${dmg}"

echo "released: https://github.com/${repo}/releases/tag/v${version}"
shasum -a 256 "macos/dist/${dmg}"
