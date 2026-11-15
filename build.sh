#!/bin/bash
# Собирает 7-Zip.app (приложение + расширение Finder) в build/7-Zip.app.
#
#   ./build.sh [--arch native|arm64|x86_64|universal] [--bundle-7zz <путь к 7zz>]
#              [--sign <identity>|-] [--version <версия>] [--build-number <номер>]
#
#   --arch          под какие процессоры собирать (по умолчанию — под этот Mac)
#   --bundle-7zz    положить 7zz внутрь приложения (для готовых релизов)
#   --sign          чем подписать: «-» — локальная подпись; по умолчанию — сертификат
#                   разработчика из связки ключей, если он есть, иначе локальная
#   --version       версия приложения (CFBundleShortVersionString)
#   --build-number  номер сборки (CFBundleVersion)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/7-Zip.app"
APPEX="$APP/Contents/PlugIns/7-Zip Finder.appex"

ARCH="native"
BUNDLE_7ZZ=""
IDENTITY=""
VERSION=""
BUILD_NUMBER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --arch)         ARCH="$2"; shift 2 ;;
        --bundle-7zz)   BUNDLE_7ZZ="$2"; shift 2 ;;
        --sign)         IDENTITY="$2"; shift 2 ;;
        --version)      VERSION="$2"; shift 2 ;;
        --build-number) BUILD_NUMBER="$2"; shift 2 ;;
        *) echo "Неизвестный параметр: $1" >&2; exit 2 ;;
    esac
done

case "$ARCH" in
    native)    ARCHS=("$(uname -m)") ;;
    arm64)     ARCHS=(arm64) ;;
    x86_64)    ARCHS=(x86_64) ;;
    universal) ARCHS=(arm64 x86_64) ;;
    *) echo "Неизвестная архитектура: $ARCH" >&2; exit 2 ;;
esac

command -v swiftc >/dev/null || { echo "Нужен Xcode или Command Line Tools (swiftc не найден)." >&2; exit 1; }

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/ru.lproj" \
         "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources" "$BUILD/obj"

# ---------- код ----------
# Каждую архитектуру собираем отдельно и склеиваем через lipo.
app_parts=(); ext_parts=()
for arch in "${ARCHS[@]}"; do
    target="$arch-apple-macos13.0"
    swiftc -O -swift-version 5 -target "$target" -module-name SevenZip \
        "$ROOT"/Sources/Shared/*.swift "$ROOT"/Sources/App/*.swift \
        -o "$BUILD/obj/7-Zip-$arch"
    swiftc -O -swift-version 5 -target "$target" -module-name SevenZipFinder \
        -parse-as-library -application-extension \
        "$ROOT"/Sources/Shared/*.swift "$ROOT"/Sources/FinderExt/*.swift \
        -Xlinker -e -Xlinker _NSExtensionMain \
        -o "$BUILD/obj/SevenZipFinder-$arch"
    app_parts+=("$BUILD/obj/7-Zip-$arch"); ext_parts+=("$BUILD/obj/SevenZipFinder-$arch")
done
lipo -create "${app_parts[@]}" -output "$APP/Contents/MacOS/7-Zip"
lipo -create "${ext_parts[@]}" -output "$APPEX/Contents/MacOS/SevenZipFinder"
echo "Архитектуры: ${ARCHS[*]}"

cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Ext-Info.plist" "$APPEX/Contents/Info.plist"
cp "$ROOT/update-7zz.sh" "$APP/Contents/Resources/update-7zz.sh"

if [ -n "$VERSION" ]; then
    for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist"
    done
fi
if [ -n "$BUILD_NUMBER" ]; then
    for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"
    done
fi

# ---------- 7zz внутри приложения (для релизов) ----------
if [ -n "$BUNDLE_7ZZ" ]; then
    [ -f "$BUNDLE_7ZZ" ] || { echo "Нет файла: $BUNDLE_7ZZ" >&2; exit 1; }
    cp "$BUNDLE_7ZZ" "$APP/Contents/MacOS/7zz"
    chmod 755 "$APP/Contents/MacOS/7zz"
    xattr -c "$APP/Contents/MacOS/7zz" 2>/dev/null || true
    # Лицензия 7-Zip должна ехать вместе с ним.
    licenses="$APP/Contents/Resources/7-Zip"
    mkdir -p "$licenses"
    for doc in License.txt readme.txt History.txt; do
        [ -f "$(dirname "$BUNDLE_7ZZ")/$doc" ] && cp "$(dirname "$BUNDLE_7ZZ")/$doc" "$licenses/"
    done
    echo "7zz внутри приложения: $("$APP/Contents/MacOS/7zz" </dev/null 2>/dev/null | awk 'NF { print; exit }' || echo 'другая архитектура')"
fi

# ---------- значок ----------
# Основной вариант — значок Icon Composer со своими слоями для светлой и тёмной темы
# (macOS 26+ сама переключает их). Запасной — готовая тёмная плитка, которая
# одинаково читается на любом фоне (старые macOS или нет Xcode).
swiftc -O "$ROOT/tools/make-icon.swift" -o "$BUILD/make-icon"
"$BUILD/make-icon" tile "$BUILD/icon-1024.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BUILD/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$BUILD/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
sips -z 64 64 "$BUILD/icon-1024.png" --out "$APPEX/Contents/Resources/menu.png" >/dev/null

ICON_DOC="$BUILD/AppIcon.icon"
mkdir -p "$ICON_DOC/Assets"
cp "$ROOT/Resources/AppIcon.icon/icon.json" "$ICON_DOC/icon.json"
"$BUILD/make-icon" glyph-light "$ICON_DOC/Assets/glyph-light.png"
"$BUILD/make-icon" glyph-dark "$ICON_DOC/Assets/glyph-dark.png"
ICON_OUT="$BUILD/icon-compiled"
mkdir -p "$ICON_OUT"
if xcrun actool "$ICON_DOC" --compile "$ICON_OUT" --app-icon AppIcon --platform macosx \
        --minimum-deployment-target 13.0 --target-device mac \
        --output-partial-info-plist "$ICON_OUT/partial.plist" >"$BUILD/actool.log" 2>&1 \
   && [ -f "$ICON_OUT/Assets.car" ]; then
    cp "$ICON_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"
    [ -f "$ICON_OUT/AppIcon.icns" ] && cp "$ICON_OUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    echo "Значок: светлый и тёмный варианты"
else
    echo "Значок: actool не собрал значок Icon Composer, используется единый тёмный значок"
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::Значок Icon Composer не собран — в сборке единый тёмный значок."
    sed 's/^/    actool: /' "$BUILD/actool.log" | head -20
    [ "${REQUIRE_ICON_COMPOSER:-0}" = 1 ] && { echo "Нужен значок Icon Composer (REQUIRE_ICON_COMPOSER=1)." >&2; exit 1; }
fi

# ---------- подпись ----------
# Сертификат разработчика, если есть (тогда разрешения macOS не сбрасываются
# при пересборке), иначе локальная подпись.
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID Application/ { print $2; exit }')"
    [ -n "$IDENTITY" ] || IDENTITY="-"
fi
[ -f "$APP/Contents/MacOS/7zz" ] && codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/MacOS/7zz"
codesign --force --sign "$IDENTITY" --timestamp=none \
    --entitlements "$ROOT/Resources/Ext.entitlements" "$APPEX"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Собрано: $APP"
