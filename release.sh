#!/bin/bash
# Собирает готовый релиз: скачивает консольный 7-Zip для macOS, собирает 7-Zip.app
# с ним внутри и упаковывает в образ диска (.dmg), который остаётся только перетащить
# в «Программы».
#
#   ./release.sh <ссылка на 7zXXXX-mac.tar.xz или путь к нему> [папка для результата]
#
# С версии 26.06 7-Zip выпускает две сборки: 7zXXXX-mac.tar.xz (Apple Silicon)
# и 7zXXXX-mac-x64.tar.xz (Intel). Достаточно дать любую из них — вторая берётся
# из того же места, и из двух 7zz склеивается один универсальный. Если второй
# нет, релиз собирается под те процессоры, что есть.
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

# ---------- 1. Архивы 7-Zip ----------
clean="${SOURCE%%[?#]*}"
name="$(basename "$clean")"
[[ "$name" =~ ^7z([0-9]{2})([0-9]{2})-mac(-x64)?\.tar\.xz$ ]] \
    || fail "Нужна ссылка на консольную версию для macOS вида 7z2606-mac.tar.xz, а не «$name»."
CODE="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
VERSION="$((10#${BASH_REMATCH[1]})).${BASH_REMATCH[2]}"
LOCATION="$(dirname "$clean")"

case "$SOURCE" in
    https://www.7-zip.org/*|https://7-zip.org/*|https://github.com/ip7z/7zip/releases/download/*) REMOTE=1 ;;
    http://*|https://*) fail "Ссылка должна вести на 7-zip.org или github.com/ip7z/7zip/releases." ;;
    *) REMOTE=0 ;;
esac

# Достаёт архив: обязательный (тот, что дали) или парный (может не существовать).
fetch() { # <имя файла> <обязательный: 1|0>
    local file="$1" required="$2"
    if [ "$REMOTE" = 1 ]; then
        if curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$WORK/$file" "$LOCATION/$file"; then
            echo "Скачан $LOCATION/$file"; return 0
        fi
    elif [ -f "$LOCATION/$file" ]; then
        cp "$LOCATION/$file" "$WORK/$file"; echo "Взят $LOCATION/$file"; return 0
    fi
    rm -f "$WORK/$file"
    [ "$required" = 1 ] && fail "Не удалось получить $LOCATION/$file"
    echo "Нет парной сборки $file — пропускаю."
    return 1
}

ARCHIVES=("$name")
fetch "$name" 1
if [ "$name" = "7z$CODE-mac.tar.xz" ]; then pair="7z$CODE-mac-x64.tar.xz"; else pair="7z$CODE-mac.tar.xz"; fi
fetch "$pair" 0 && ARCHIVES+=("$pair")

# Распаковываем и собираем по одному 7zz на каждую архитектуру.
mkdir -p "$WORK/thin"
DOCS=""
for archive in "${ARCHIVES[@]}"; do
    dir="$WORK/x/${archive%.tar.xz}"
    mkdir -p "$dir"
    tar -xJf "$WORK/$archive" -C "$dir" || fail "Не удалось распаковать $archive"
    [ -f "$dir/7zz" ] || fail "В $archive нет файла 7zz."
    file -b "$dir/7zz" | grep -q "Mach-O" || fail "7zz в $archive — не программа для macOS."
    # Лицензию и описание берём из архива для Apple Silicon (он первый, если дали его).
    [ -n "$DOCS" ] || DOCS="$dir"
    for arch in $(lipo -archs "$dir/7zz"); do
        case "$arch" in arm64|x86_64) ;; *) continue ;; esac
        [ -f "$WORK/thin/$arch" ] && continue
        if [ "$(lipo -archs "$dir/7zz")" = "$arch" ]; then
            cp "$dir/7zz" "$WORK/thin/$arch"
        else
            lipo "$dir/7zz" -thin "$arch" -output "$WORK/thin/$arch"
        fi
        echo "7zz для $arch — из $archive"
    done
done

BIN="$DOCS/7zz.release"
thin=("$WORK"/thin/*)
[ -e "${thin[0]}" ] || fail "Нет 7zz ни для arm64, ни для x86_64."
lipo -create "${thin[@]}" -output "$BIN"
chmod 755 "$BIN"
# build.sh ищет лицензию рядом с 7zz — кладём склеенный файл туда же, где она лежит.
mv "$BIN" "$DOCS/7zz"
BIN="$DOCS/7zz"

has_arm=0; has_intel=0
for arch in $(lipo -archs "$BIN"); do
    case "$arch" in arm64) has_arm=1 ;; x86_64) has_intel=1 ;; esac
done
if [ $has_arm = 1 ] && [ $has_intel = 1 ]; then ARCH="universal"; LABEL="universal"; ARCH_TEXT="Apple Silicon + Intel"
elif [ $has_arm = 1 ]; then ARCH="arm64"; LABEL="apple-silicon"; ARCH_TEXT="Apple Silicon"
else ARCH="x86_64"; LABEL="intel"; ARCH_TEXT="Intel"; fi

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
SUMS=""
for archive in "${ARCHIVES[@]}"; do
    sha="$(shasum -a 256 "$WORK/$archive" | awk '{ print $1 }')"
    if [ "$REMOTE" = 1 ]; then label="7-Zip: [$archive]($LOCATION/$archive)"; else label="7-Zip: $archive"; fi
    SUMS+="| $label | \`$sha\` |"$'\n'
done

NOTES="$ROOT/build/release-notes.md"
cat > "$NOTES" <<EOF
Ready-to-use **7-Zip.app** with the official **7-Zip $VERSION** console engine inside · $ARCH_TEXT · macOS 13+
Готовое приложение **7-Zip.app** с официальным консольным **7-Zip $VERSION** внутри · $ARCH_TEXT · macOS 13+

### Install
1. Download **$DMG_NAME**, open it and drag **7-Zip** to **Applications**.
2. Launch 7-Zip once. The app isn't signed with an Apple developer certificate, so the first launch is blocked:
   open **System Settings → Privacy & Security** and press **Open Anyway**.
   Or in Terminal: \`xattr -dr com.apple.quarantine /Applications/7-Zip.app\`
3. Right-click any file in Finder → **7-Zip**. If the submenu is missing, press **Extension settings…** in the 7-Zip window.

### Установка
1. Скачайте **$DMG_NAME**, откройте и перетащите **7-Zip** в **Программы**.
2. Запустите 7-Zip один раз. Приложение не подписано сертификатом разработчика Apple, поэтому первый запуск будет заблокирован:
   откройте **Системные настройки → Конфиденциальность и безопасность** и нажмите **Всё равно открыть**.
   Или в Терминале: \`xattr -dr com.apple.quarantine /Applications/7-Zip.app\`
3. Правый клик по файлу в Finder → **7-Zip**. Если подменю нет — нажмите **Настройки расширений…** в окне 7-Zip.

### Checksums · Контрольные суммы
| File | SHA-256 |
|---|---|
| \`$DMG_NAME\` | \`$DMG_SHA\` |
$SUMS
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
