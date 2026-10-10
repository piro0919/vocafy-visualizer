#!/bin/bash
# Packs dist/VocafyVisualizer.app into dist/VocafyVisualizer-<version>.dmg.
# hdiutil only, no AppleScript: driving Finder hangs outside an interactive session.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/VocafyVisualizer.app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
staging="$root/dist/dmg"
dmg="$root/dist/VocafyVisualizer-$version.dmg"

rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

hdiutil create -volname "Vocafy Visualizer" -srcfolder "$staging" -ov -format UDZO -quiet "$dmg"
rm -rf "$staging"

echo "built $dmg ($(du -h "$dmg" | cut -f1))"
shasum -a 256 "$dmg"
