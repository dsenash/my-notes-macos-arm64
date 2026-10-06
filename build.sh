#!/bin/bash
# Сборка MyNotes.app для macOS.
# По умолчанию собирается universal-бинарник (Apple Silicon arm64 + Intel x86_64).
#   ./build.sh                 — universal (arm64 + x86_64)
#   ARCHS=arm64 ./build.sh     — только Apple Silicon
#   ARCHS=x86_64 ./build.sh    — только Intel
# Требуется: macOS 14+, Xcode или Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MyNotes.app"
ARCHS="${ARCHS:-universal}"

case "$ARCHS" in
    universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    arm64|x86_64) ARCH_FLAGS=(--arch "$ARCHS") ;;
    *)
        echo "Неизвестное значение ARCHS=$ARCHS (допустимо: universal, arm64, x86_64)" >&2
        exit 1
        ;;
esac

echo "→ Компиляция (release, $ARCHS)…"
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/MyNotes"

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
echo "Архитектуры: $(lipo -archs "$APP/Contents/MacOS/MyNotes")"
echo "Готово: $APP"
echo "Запуск:        open \"$APP\""
echo "Установка:     cp -R \"$APP\" /Applications/"
