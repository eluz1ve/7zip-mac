#!/bin/bash
# Устанавливает или обновляет консольный 7-Zip (7zz) из скачанного с 7-zip.org архива.
#
#   7zip-update                         — сам найдёт самый свежий 7z*-mac в ~/Downloads
#   7zip-update ~/Downloads/7z2700-mac.tar.xz
#   7zip-update ~/Downloads/7z2700-mac  (распакованная папка)
#   7zip-update /path/to/7zz            (сам бинарник)
#
# Приложение 7-Zip.app и меню Finder пересобирать не нужно: они используют
# тот 7zz, который лежит в ~/Library/Application Support/7-Zip/bin.

set -euo pipefail

SUPPORT="$HOME/Library/Application Support/7-Zip"
BIN_DIR="$SUPPORT/bin"
LINK_DIR="$HOME/.local/bin"

say()  { printf '%s\n' "$*"; }
fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }

version_of() {
    # Вторая строка вывода: "7-Zip (z) 26.06 (arm64) : Copyright ..."
    "$1" 2>/dev/null </dev/null \
        | awk 'NF { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+$/) { print $i; exit } exit }'
}

find_latest_download() {
    local newest="" candidate
    for candidate in "$HOME"/Downloads/7z*-mac.tar.xz "$HOME"/Downloads/7z*-mac; do
        [ -e "$candidate" ] || continue
        if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
            newest="$candidate"
        fi
    done
    printf '%s' "$newest"
}

src="${1:-}"
if [ -z "$src" ]; then
    src="$(find_latest_download)"
    [ -n "$src" ] || fail "не нашёл 7z*-mac.tar.xz или папку 7z*-mac в ~/Downloads. Укажите путь: 7zip-update <путь>"
    say "Источник: $src"
fi
[ -e "$src" ] || fail "нет такого файла или папки: $src"

tmp=""
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; return 0; }
trap cleanup EXIT

src_dir=""
if [ -d "$src" ]; then
    src_dir="$src"
    bin="$src/7zz"
elif [[ "$src" == *.tar.xz || "$src" == *.tar || "$src" == *.txz ]]; then
    tmp="$(mktemp -d)"
    tar -xf "$src" -C "$tmp"
    src_dir="$tmp"
    bin="$tmp/7zz"
else
    bin="$src"
fi

[ -f "$bin" ] && [ ! -L "$bin" ] || fail "не найден файл 7zz в: $src"
file -b "$bin" | grep -q "Mach-O" || fail "$bin — не исполняемый файл macOS"
arch="$(uname -m)"
lipo -archs "$bin" 2>/dev/null | tr ' ' '\n' | grep -qx "$arch" \
    || fail "этот 7zz собран не для вашего процессора ($arch): $(lipo -archs "$bin" 2>/dev/null)"

mkdir -p "$BIN_DIR"
new="$BIN_DIR/7zz.new"
cp -f "$bin" "$new"
chmod 755 "$new"
# Снимаем метку карантина браузера, иначе Gatekeeper не даст запустить файл.
xattr -c "$new" 2>/dev/null || true
# На Apple Silicon файл обязан иметь хотя бы локальную подпись.
codesign -v "$new" 2>/dev/null || codesign -f -s - "$new"

new_version="$(version_of "$new")"
[ -n "$new_version" ] || { rm -f "$new"; fail "новый 7zz не запускается"; }

old_version=""
[ -x "$BIN_DIR/7zz" ] && old_version="$(version_of "$BIN_DIR/7zz" || true)"

mv -f "$new" "$BIN_DIR/7zz"

# Лицензия и справка — рядом, чтобы были под рукой.
if [ -n "$src_dir" ]; then
    for doc in License.txt History.txt readme.txt; do
        [ -f "$src_dir/$doc" ] && cp -f "$src_dir/$doc" "$SUPPORT/$doc"
    done
    if [ -d "$src_dir/MANUAL" ]; then
        rm -rf "$SUPPORT/MANUAL"
        cp -R "$src_dir/MANUAL" "$SUPPORT/MANUAL"
        xattr -cr "$SUPPORT/MANUAL" 2>/dev/null || true
    fi
fi

# Команды 7zz и 7z в терминале.
mkdir -p "$LINK_DIR"
ln -sf "$BIN_DIR/7zz" "$LINK_DIR/7zz"
ln -sf "$BIN_DIR/7zz" "$LINK_DIR/7z"

if [ -z "$old_version" ]; then
    say "Установлен 7-Zip $new_version"
elif [ "$old_version" = "$new_version" ]; then
    say "7-Zip $new_version переустановлен (версия та же)"
else
    say "7-Zip обновлён: $old_version → $new_version"
fi
say "Бинарник: $BIN_DIR/7zz"
# Проверяем PATH только при запуске из терминала: приложения, открытые из Finder/Dock,
# получают урезанный системный PATH без настроек из ~/.zshrc, и проверка там врёт.
if [ -z "${SEVENZIP_FROM_APP:-}" ]; then
    case ":$PATH:" in
        *":$LINK_DIR:"*) ;;
        *) say "Внимание: $LINK_DIR нет в PATH — команды 7zz/7z в терминале не будут видны." ;;
    esac
fi
