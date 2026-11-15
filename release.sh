#!/bin/bash
# Собирает готовый релиз: скачивает консольный 7-Zip для macOS, собирает 7-Zip.app
# с ним внутри и упаковывает в образ диска (.dmg), который остаётся только перетащить
# в «Программы».
#
#   ./release.sh <ссылка на 7zXXXX-mac.tar.xz или путь к нему> [папка для результата]
#
# Ссылки принимаются только с официальных мест: 7-zip.org и github.com/ip7z/7zip.
# Этот скрипт запускает GitHub Action «Release» (.github/workflows/release.yml),
# но его можно запустить и локально — результат появится в dist/.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${1:?Укажите ссылку на 7zXXXX-mac.tar.xz или путь к нему}"
OUT="${2:-$ROOT/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

fail() { echo "::error::$*" >&2; echo "Ошибка: $*" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------- 1. Архив 7-Zip ----------
name="$(basename "${SOURCE%%[?#]*}")"
[[ "$name" =~ ^7z([0-9]{2})([0-9]{2})-mac\.tar\.xz$ ]] \
    || fail "Нужна ссылка на консольную версию для macOS вида 7z2606-mac.tar.xz, а не «$name»."
VERSION="$((10#${BASH_REMATCH[1]})).${BASH_REMATCH[2]}"

case "$SOURCE" in
    https://www.7-zip.org/*|https://7-zip.org/*|https://github.com/ip7z/7zip/releases/download/*)
        echo "Скачиваю $SOURCE"
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$WORK/$name" "$SOURCE" \
            || fail "Не удалось скачать $SOURCE"
        ;;
    http://*|https://*)
        fail "Ссылка должна вести на 7-zip.org или github.com/ip7z/7zip/releases."
        ;;
    *)
        [ -f "$SOURCE" ] || fail "Нет файла $SOURCE"
        cp "$SOURCE" "$WORK/$name"
        ;;
esac
ARCHIVE_SHA="$(shasum -a 256 "$WORK/$name" | awk '{ print $1 }')"

mkdir -p "$WORK/7z"
tar -xJf "$WORK/$name" -C "$WORK/7z" || fail "Не удалось распаковать $name"
BIN="$WORK/7z/7zz"
[ -f "$BIN" ] || fail "В архиве нет файла 7zz."
file -b "$BIN" | grep -q "Mach-O" || fail "7zz в архиве — не программа для macOS."

# Под какие процессоры собран 7zz — под те же собираем и приложение.
archs=" $(lipo -archs "$BIN") "
case "$archs" in
    *" arm64 "*" x86_64 "*|*" x86_64 "*" arm64 "*) ARCH="universal"; LABEL="universal"; ARCH_TEXT="Apple Silicon + Intel" ;;
    *" arm64 "*)  ARCH="arm64";  LABEL="apple-silicon"; ARCH_TEXT="Apple Silicon" ;;
    *" x86_64 "*) ARCH="x86_64"; LABEL="intel";         ARCH_TEXT="Intel" ;;
    *) fail "Неизвестная архитектура 7zz:$archs" ;;
esac

# Если 7zz запускается на этой машине — сверяем версию с именем файла.
reported="$("$BIN" </dev/null 2>/dev/null \
    | awk 'NF { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+$/) { print $i; exit } exit }' || true)"
if [ -n "$reported" ] && [ "$reported" != "$VERSION" ]; then
    echo "::warning::Имя архива говорит $VERSION, а 7zz — $reported. Берём $reported."
    VERSION="$reported"
fi
echo "7-Zip $VERSION, $ARCH_TEXT"

# ---------- 2. Сборка ----------
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(date +%Y%m%d%H%M)}"
"$ROOT/build.sh" --arch "$ARCH" --bundle-7zz "$BIN" --sign "$SIGN_IDENTITY" \
    --version "$VERSION" --build-number "$BUILD_NUMBER"
APP="$ROOT/build/7-Zip.app"
if [ "$ARCH" = "universal" ] || [ "$ARCH" = "$(uname -m)" ]; then
    "$APP/Contents/MacOS/7zz" </dev/null >/dev/null 2>&1 || fail "Встроенный 7zz не запускается."
fi

# ---------- 3. Образ диска ----------
mkdir -p "$OUT"
DMG_NAME="7-Zip-$VERSION-macOS-$LABEL.dmg"
DMG="$OUT/$DMG_NAME"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/7-Zip.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "7-Zip $VERSION" -srcfolder "$STAGE" -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify -quiet "$DMG"
DMG_SHA="$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
echo "$DMG_SHA  $DMG_NAME" > "$DMG.sha256"
echo "Образ: $DMG"

# ---------- 4. Описание релиза ----------
case "$SOURCE" in https://*) SOURCE_TEXT="$SOURCE" ;; *) SOURCE_TEXT="$name" ;; esac
NOTES="$ROOT/build/release-notes.md"
cat > "$NOTES" <<EOF
Ready-to-use **7-Zip.app** with the official **7-Zip $VERSION** console engine inside · $ARCH_TEXT · macOS 13+
Готовое приложение **7-Zip.app** с официальным консольным **7-Zip $VERSION** внутри · $ARCH_TEXT · macOS 13+

### Install
1. Download **$DMG_NAME**, open it and drag **7-Zip** to **Applications**.
2. Launch 7-Zip once. The app is not notarized by Apple, so the first launch is blocked:
   open **System Settings → Privacy & Security** and press **Open Anyway**.
   Or in Terminal: \`xattr -dr com.apple.quarantine /Applications/7-Zip.app\`
3. Right-click any file in Finder → **7-Zip**. If the submenu is missing, press **Extension settings…** in the 7-Zip window.

### Установка
1. Скачайте **$DMG_NAME**, откройте и перетащите **7-Zip** в **Программы**.
2. Запустите 7-Zip один раз. Приложение не нотариально заверено Apple, поэтому первый запуск будет заблокирован:
   откройте **Системные настройки → Конфиденциальность и безопасность** и нажмите **Всё равно открыть**.
   Или в Терминале: \`xattr -dr com.apple.quarantine /Applications/7-Zip.app\`
3. Правый клик по файлу в Finder → **7-Zip**. Если подменю нет — нажмите **Настройки расширений…** в окне 7-Zip.

### Checksums · Контрольные суммы
| File | SHA-256 |
|---|---|
| \`$DMG_NAME\` | \`$DMG_SHA\` |
| 7-Zip: $SOURCE_TEXT | \`$ARCHIVE_SHA\` |

<sub>Unofficial front end, not affiliated with Igor Pavlov or the 7-Zip project. Provided "as is", without warranty.
7-Zip is © Igor Pavlov, GNU LGPL with the unRAR restriction; its license is inside the app: \`Contents/Resources/7-Zip/License.txt\`.<br>
Неофициальная оболочка, не связана с Игорем Павловым и проектом 7-Zip. Предоставляется «как есть», без гарантий.</sub>
EOF

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=$VERSION"
        echo "label=$LABEL"
        echo "dmg=$DMG"
        echo "notes=$NOTES"
    } >> "$GITHUB_OUTPUT"
fi
