#!/bin/bash
# Сборка MyNotes.app для macOS на Apple Silicon (arm64).
# Требуется: macOS 14+, Xcode или Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MyNotes.app"

echo "→ Компиляция (release, arm64)…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MyNotes"

echo "→ Сборка пакета приложения…"
rm -rf "$APP" build/icon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ru.lproj" "$APP/Contents/Resources/en.lproj"
cp "$BIN" "$APP/Contents/MacOS/MyNotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Рисую иконку…"
"$BIN" --render-icons build/icon.iconset
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Подпись (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo
echo "Готово: $APP"
echo "Запуск:        open \"$APP\""
echo "Установка:     cp -R \"$APP\" /Applications/"
