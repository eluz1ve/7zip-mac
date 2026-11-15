#!/bin/bash
# Удаляет всё, что поставил install.sh: приложение, расширение Finder, 7zz и команды в терминале.
set -uo pipefail

APP_ID="local.sevenzip.SevenZip"
LINK_DIR="$HOME/.local/bin"
SUPPORT="$HOME/Library/Application Support/7-Zip"

osascript -e "tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 || true

for app in "/Applications/7-Zip.app" "$HOME/Applications/7-Zip.app"; do
    if [ -d "$app" ]; then
        pluginkit -r "$app/Contents/PlugIns/7-Zip Finder.appex" >/dev/null 2>&1 || true
        rm -rf "$app"
        echo "Удалено: $app"
    fi
done

for name in 7zz 7z 7zip-update; do
    link="$LINK_DIR/$name"
    # Удаляем только свои символические ссылки.
    if [ -L "$link" ]; then
        case "$(readlink "$link")" in
            "$SUPPORT"/*|*/update-7zz.sh) rm -f "$link"; echo "Удалено: $link" ;;
        esac
    fi
done

if [ -d "$SUPPORT" ]; then
    rm -rf "$SUPPORT"
    echo "Удалено: $SUPPORT"
fi
defaults delete "$APP_ID" >/dev/null 2>&1 || true
echo "7-Zip удалён. Папку с исходниками ($(cd "$(dirname "$0")" && pwd)) можно удалить вручную."
