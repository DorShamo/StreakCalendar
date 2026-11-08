#!/bin/bash
# Builds Streak Calendar.app and puts it in your Applications folder.
set -e
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo ""
  echo "First, your Mac needs Apple's free developer tools."
  echo "A window will pop up — click Install, wait for it to finish,"
  echo "then run this same command again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

APP="Streak Calendar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building Streak Calendar…"
xcrun swiftc -parse-as-library -O \
  -target "$(uname -m)-apple-macos12.0" \
  StreakCalendar.swift \
  -o "$APP/Contents/MacOS/StreakCalendar"

cp Info.plist "$APP/Contents/Info.plist"

if [ -f icon.png ]; then
  mkdir -p icon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out "icon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf icon.iconset
fi

if rm -rf "/Applications/$APP" 2>/dev/null && cp -R "$APP" /Applications/ 2>/dev/null; then
  echo "Done! Streak Calendar is in your Applications folder."
  open "/Applications/$APP"
else
  echo "Done! The app is in this folder — drag it into Applications."
  open "$APP"
fi
