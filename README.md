<div align="center">

<img src="docs/icon.png" width="128" alt="7-Zip for macOS icon">

# 7-Zip for macOS

**The classic 7-Zip interface from Windows — native on your Mac, right in Finder.**<br>
**Классический интерфейс 7-Zip из Windows — нативно на Mac, прямо в Finder.**

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?logo=swift&logoColor=white)
![Apple Silicon & Intel](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-3b82f6)
![License: MIT](https://img.shields.io/badge/license-MIT-8b5cf6)

[**English**](#english) · [**Русский**](#русский)

</div>

---

<a id="english"></a>

## 🇬🇧 English

<p align="center">
  <a href="docs/demo-en.mp4"><img src="docs/demo-en.gif" width="860" alt="7-Zip for macOS — demo"></a><br>
  <sub>▶ <a href="docs/demo-en.mp4">Watch in full quality (MP4)</a></sub>
</p>

If you have ever used 7-Zip on Windows, you already know how this works.
This is a native macOS front end for the official 7-Zip console engine that brings back
the dialogs you're used to — same layout, same options, same names — and puts them
where they belong: in the Finder context menu.

### ✨ What's inside

#### 🗂 7-Zip submenu in Finder
Right-click any files or folders → **7-Zip**:

| For any selection | For archives |
|---|---|
| **Add to archive…** — opens the full dialog | **Extract files…** — opens the Extract dialog |
| **Add to "name.7z"** — one click, no questions | **Extract Here** |
| **Add to "name.zip"** — one click, no questions | **Extract to "name/"** |
| | **Test archive** |

Clicking the **7-Zip** item itself (not the submenu) opens *Add to archive* straight away.

#### 📦 Add to Archive — the dialog you know
Laid out exactly like on Windows, two columns, every parameter in its usual place:

- **Archive format** — 7z, zip, tar, gzip, bzip2, xz, wim
- **Compression level** — Store → Ultra, **method**, **dictionary size**, **word size**, **solid block size**
- **Number of CPU threads**, **split to volumes** (with presets for CD, DVD, FAT, Blu-ray), **parameters**
- **Update mode** — add & replace, update, freshen, synchronize
- **Path mode** — relative, full or absolute pathnames
- **Delete files after compression**
- **Encryption** — password with confirmation, *show password*, AES-256 / ZipCrypto, *encrypt file names*

Format, level, update and path modes are remembered between runs.

#### 📂 Extract dialog
Destination folder with a **…** picker, **extract into a subfolder** (or a separate folder per archive),
**path mode** (full / no pathnames), **overwrite mode** (auto rename, overwrite, skip, rename existing) and **password**.

#### ⏱ Progress window
Current file, percentage, elapsed time, **Pause / Continue** and **Cancel**.
Encrypted archives ask for the password up front; a wrong password can be re-entered right away.
If something goes wrong, the full log is one click away.

#### 🪟 Main window
Launch the app on its own and you get a compact window with a **drag & drop zone**
(drop files to compress, archives to extract), the Finder extension status and an
**Install new version…** button for updating 7-Zip itself.

#### 🌍 English and Russian
The interface follows your macOS language. To pick a language just for 7-Zip:
**System Settings → General → Language & Region → Applications → +** → 7-Zip → English / Русский,
then restart 7-Zip. The Finder submenu always follows the system language.

### 🚀 Installation

**Requirements:** macOS 13 Ventura or later.

#### Ready-made build (recommended)

1. Download the latest **`7-Zip-….dmg`** from [**Releases**](https://github.com/eluz1ve/7zip-mac/releases/latest).
   The official 7-Zip engine is already inside — nothing else to install.
2. Open the image and drag **7-Zip** to **Applications**.
3. Launch 7-Zip once. The app isn't notarized by Apple, so macOS blocks the first launch:
   open **System Settings → Privacy & Security** and press **Open Anyway**.
4. Right-click any file in Finder → **7-Zip**. The Finder extension is enabled automatically on first launch;
   if the submenu is missing, press **Extension settings…** in the 7-Zip window.

#### Build from source

Needs Xcode or the Command Line Tools (`xcode-select --install`).

1. Download the **macOS console version** of 7-Zip (`7z….-mac.tar.xz`) from [7-zip.org](https://www.7-zip.org/download.html).
2. Clone and install:

   ```bash
   git clone https://github.com/eluz1ve/7zip-mac.git
   cd 7zip-mac
   ./install.sh ~/Downloads/7z2606-mac.tar.xz
   ```

   The script builds the app from source, puts **7-Zip.app** into `/Applications`, installs `7zz`
   and enables the Finder extension. Without an argument it picks the newest `7z*-mac` from `~/Downloads`.
3. If the 7-Zip item doesn't show up in Finder, open 7-Zip and press **Extension settings…**.

**Updating 7-Zip** when a new release comes out — no rebuild needed: in the main window press
**Install new version…** and pick the downloaded file, or run `7zip-update` in Terminal.

**Uninstall:** drag 7-Zip from Applications to the Trash, or run `./uninstall.sh` for a source install.

> The installer and updater print their messages in Russian.

#### For maintainers: publishing a release

When a new 7-Zip comes out: **Actions → Release → Run workflow**, paste the link to the macOS console archive
(for example `https://www.7-zip.org/a/7z2606-mac.tar.xz`) and run. The workflow downloads it (only from
7-zip.org or github.com/ip7z/7zip), builds 7-Zip.app with that engine inside for the same processors
(Apple Silicon, Intel or both), packs a `.dmg` and publishes the release with checksums.
The same build runs locally: `./release.sh <link or path to the archive>` → `dist/`.

---

<a id="русский"></a>

## 🇷🇺 Русский

<p align="center">
  <a href="docs/demo-ru.mp4"><img src="docs/demo-ru.gif" width="860" alt="7-Zip для macOS — демо"></a><br>
  <sub>▶ <a href="docs/demo-ru.mp4">Смотреть в полном качестве (MP4)</a></sub>
</p>

Если вы пользовались 7-Zip в Windows — вы уже умеете пользоваться и этим.
Это нативная оболочка для macOS над официальным консольным 7-Zip: те же привычные окна —
та же компоновка, те же параметры, те же названия — и всё там, где и должно быть:
в контекстном меню Finder.

### ✨ Что внутри

#### 🗂 Подменю 7-Zip в Finder
Правый клик по файлам или папкам → **7-Zip**:

| Для любых файлов | Для архивов |
|---|---|
| **Добавить к архиву…** — полное окно параметров | **Распаковать…** — окно распаковки |
| **Добавить к «имя.7z»** — в один клик, без вопросов | **Распаковать здесь** |
| **Добавить к «имя.zip»** — в один клик, без вопросов | **Распаковать в «имя/»** |
| | **Тестировать архив** |

Клик по самому пункту **7-Zip** (а не по подменю) сразу открывает «Добавить к архиву».

#### 📦 «Добавить к архиву» — то самое окно
Скомпоновано как в Windows: две колонки, каждый параметр на своём месте.

- **Формат архива** — 7z, zip, tar, gzip, bzip2, xz, wim
- **Уровень сжатия** — от «Без сжатия» до «Ультра», **метод**, **размер словаря**, **размер слова**, **размер блока**
- **Число потоков**, **разбить на тома** (готовые размеры для CD, DVD, FAT, Blu-ray), **параметры**
- **Режим изменения** — добавить и заменить, обновить, освежить, синхронизировать
- **Режим путей** — относительные, полные или абсолютные пути
- **Удалять файлы после сжатия**
- **Шифрование** — пароль с повтором, «показать пароль», AES-256 / ZipCrypto, «шифровать имена файлов»

Формат, уровень, режим изменения и режим путей запоминаются.

#### 📂 Окно распаковки
Папка назначения с кнопкой **…**, **распаковка во вложенную папку** (или в отдельную папку для каждого архива),
**режим путей** (полные / без путей), **режим перезаписи** (переименовывать, перезаписывать, пропускать, переименовывать существующие) и **пароль**.

#### ⏱ Окно прогресса
Текущий файл, проценты, прошедшее время, **Пауза / Продолжить** и **Отмена**.
Для зашифрованных архивов пароль спрашивается сразу, а при ошибке его можно ввести повторно.
Если что-то пошло не так — полный лог в один клик.

#### 🪟 Главное окно
Если запустить приложение просто так, откроется компактное окно с **зоной перетаскивания**
(файлы — сжать, архивы — распаковать), статусом расширения Finder и кнопкой
**Установить новую версию…** для обновления самого 7-Zip.

#### 🌍 Русский и английский
Интерфейс следует языку macOS. Чтобы выбрать язык только для 7-Zip:
**Системные настройки → Основные → Язык и регион → Приложения → +** → 7-Zip → Русский / English,
затем перезапустите 7-Zip. Подменю в Finder всегда на языке системы.

### 🚀 Установка

**Нужно:** macOS 13 Ventura или новее.

#### Готовая сборка (рекомендуется)

1. Скачайте последний **`7-Zip-….dmg`** со страницы [**Releases**](https://github.com/eluz1ve/7zip-mac/releases/latest).
   Официальный движок 7-Zip уже внутри — больше ничего ставить не нужно.
2. Откройте образ и перетащите **7-Zip** в **Программы**.
3. Запустите 7-Zip один раз. Приложение не нотариально заверено Apple, поэтому первый запуск macOS заблокирует:
   откройте **Системные настройки → Конфиденциальность и безопасность** и нажмите **Всё равно открыть**.
4. Правый клик по файлу в Finder → **7-Zip**. Расширение Finder включается само при первом запуске;
   если подменю нет — нажмите **Настройки расширений…** в окне 7-Zip.

#### Сборка из исходников

Нужен Xcode или Command Line Tools (`xcode-select --install`).

1. Скачайте **консольную версию 7-Zip для macOS** (`7z….-mac.tar.xz`) с [7-zip.org](https://www.7-zip.org/download.html).
2. Склонируйте и установите:

   ```bash
   git clone https://github.com/eluz1ve/7zip-mac.git
   cd 7zip-mac
   ./install.sh ~/Downloads/7z2606-mac.tar.xz
   ```

   Скрипт соберёт приложение из исходников, положит **7-Zip.app** в `/Applications`, установит `7zz`
   и включит расширение Finder. Без аргумента берётся самый свежий `7z*-mac` из `~/Downloads`.
3. Если пункта 7-Zip в Finder нет — откройте 7-Zip и нажмите **Настройки расширений…**.

**Обновление 7-Zip** при выходе новой версии — без пересборки: в главном окне нажмите
**Установить новую версию…** и выберите скачанный файл, или выполните `7zip-update` в Терминале.

**Удаление:** перетащите 7-Zip из «Программ» в Корзину, а при установке из исходников — `./uninstall.sh`.

#### Для мейнтейнеров: выпуск релиза

Когда выходит новый 7-Zip: **Actions → Release → Run workflow**, вставьте ссылку на консольный архив для macOS
(например, `https://www.7-zip.org/a/7z2606-mac.tar.xz`) и запустите. Workflow скачает его (только с 7-zip.org
или github.com/ip7z/7zip), соберёт 7-Zip.app с этим движком внутри под те же процессоры
(Apple Silicon, Intel или оба), упакует в `.dmg` и опубликует релиз с контрольными суммами.
Та же сборка запускается и локально: `./release.sh <ссылка или путь к архиву>` → `dist/`.

---

## ⚖️ License · Лицензия

**MIT** — see [LICENSE](LICENSE).

This is an independent, unofficial project. It is **not affiliated with, endorsed by or sponsored by**
Igor Pavlov, the 7-Zip project or Apple. The code and builds are provided **"as is"**, without warranty of any kind.
The source code doesn't include 7-Zip; ready-made releases contain the unmodified official `7zz`
from [7-zip.org](https://www.7-zip.org/) together with its license (`Contents/Resources/7-Zip/License.txt`).
7-Zip is © Igor Pavlov, licensed under the GNU LGPL (with the unRAR restriction).

Это независимый неофициальный проект. Он **никак не связан** с Игорем Павловым, проектом 7-Zip или Apple
и не одобрен ими. Код и сборки предоставляются **«как есть»**, без каких-либо гарантий.
В исходном коде 7-Zip нет; готовые релизы содержат неизменённый официальный `7zz`
с [7-zip.org](https://www.7-zip.org/) вместе с его лицензией (`Contents/Resources/7-Zip/License.txt`).
7-Zip © Игорь Павлов, лицензия GNU LGPL (с ограничением unRAR).
