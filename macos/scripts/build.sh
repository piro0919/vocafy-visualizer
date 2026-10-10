#!/bin/bash
# Assembles dist/VocafyVisualizer.app from a release build.
# arm64 only: a universal build needs full Xcode for xcbuild, the Command Line Tools alone cannot.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

app="$root/dist/VocafyVisualizer.app"

swift build -c release --package-path "$root"
binary="$(swift build -c release --package-path "$root" --show-bin-path)/VocafyVisualizer"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/VocafyVisualizer"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
if [ -f "$root/Resources/AppIcon.icns" ]; then
  cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist"
fi

# Ad hoc, like the other apps in the tap. The audio permission is tied to the signature, so
# macOS asks for it again after each update.
codesign --force --sign - "$app"

echo "built $app ($(du -sh "$app" | cut -f1))"
