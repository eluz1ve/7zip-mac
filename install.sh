#!/bin/bash
# Полная установка 7-Zip для macOS:
#   1. ставит консольный 7zz (через update-7zz.sh);
#   2. собирает приложение 7-Zip.app с окном «Добавить к архиву»;
#   3. кладёт его в /Applications и включает подменю «7-Zip» в контекстном меню Finder.
#
#   ./install.sh                     — 7zz берётся из ~/Downloads (или уже установленный)
#   ./install.sh <путь к 7z…-mac.tar.xz или папке>
#
# Для обновления только самого 7-Zip до новой версии достаточно: 7zip-update [путь]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/7-Zip.app"
APP_ID="local.sevenzip.SevenZip"
EXT_ID="local.sevenzip.SevenZip.FinderMenu"
SUPPORT_BIN="$HOME/Library/Application Support/7-Zip/bin/7zz"
LINK_DIR="$HOME/.local/bin"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

step() { printf '\n== %s\n' "$*"; }

# ---------- 1. 7zz ----------
step "Консольный 7zz"
if [ $# -ge 1 ]; then
    "$ROOT/update-7zz.sh" "$1"
elif [ -x "$SUPPORT_BIN" ]; then
    echo "Уже установлен: $("$SUPPORT_BIN" </dev/null | awk 'NF { print; exit }')"
else
    "$ROOT/update-7zz.sh"
fi

# ---------- 2. Сборка ----------
step "Сборка 7-Zip.app"
"$ROOT/build.sh"

# ---------- 3. Установка ----------
step "Установка"
if [ -w /Applications ]; then DEST_DIR="/Applications"; else DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; fi
DEST="$DEST_DIR/7-Zip.app"

osascript -e "tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 || true
pluginkit -r "$DEST/Contents/PlugIns/7-Zip Finder.appex" >/dev/null 2>&1 || true
rm -rf "$DEST"
ditto "$APP" "$DEST"

"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
pluginkit -a "$DEST/Contents/PlugIns/7-Zip Finder.appex" || true
pluginkit -e use -i "$EXT_ID" || true

mkdir -p "$LINK_DIR"
ln -sf "$ROOT/update-7zz.sh" "$LINK_DIR/7zip-update"

echo "Приложение: $DEST"
echo "Расширение Finder: $(pluginkit -m -i "$EXT_ID" 2>/dev/null | head -1 || true)"
echo
echo "Готово. Правый клик по файлу в Finder → 7-Zip."
echo "Если подменю не появилось: Системные настройки → Основные → Объекты входа и расширения →"
echo "Расширения Finder (или «Расширения файлового провайдера») → включите 7-Zip."
