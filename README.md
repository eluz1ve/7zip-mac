<div align="center">

<img src="docs/icon.png" width="128" alt="7-Zip for macOS icon">

# 7-Zip for macOS

**The classic 7-Zip interface from Windows — native on your Mac, right in Finder.**

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?logo=swift&logoColor=white)
![Apple Silicon & Intel](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-3b82f6)
![License: MIT](https://img.shields.io/badge/license-MIT-8b5cf6)

**English** · [Русский](README.ru.md)

</div>

---

https://github.com/user-attachments/assets/b27773a6-cdd7-4705-ba60-b92f35132a91

If you have ever used 7-Zip on Windows, you already know how this works.
This is a native macOS front end for the official 7-Zip console engine that brings back
the dialogs you're used to — same layout, same options, same names — and puts them
where they belong: in the Finder context menu.

## ✨ What's inside

### 🗂 7-Zip submenu in Finder
Right-click any files or folders → **7-Zip**:

| For any selection | For archives |
|---|---|
| **Add to archive…** — opens the full dialog | **Extract files…** — opens the Extract dialog |
| **Add to "name.7z"** — one click, no questions | **Extract Here** |
| **Add to "name.zip"** — one click, no questions | **Extract to "name/"** |
| | **Test archive** |

Clicking the **7-Zip** item itself (not the submenu) opens *Add to archive* straight away.

### 📦 Add to Archive — the dialog you know
Laid out exactly like on Windows, two columns, every parameter in its usual place:

- **Archive format** — 7z, zip, tar, gzip, bzip2, xz, wim
- **Compression level** — Store → Ultra, **method**, **dictionary size**, **word size**, **solid block size**
- **Number of CPU threads**, **split to volumes** (with presets for CD, DVD, FAT, Blu-ray), **parameters**
- **Update mode** — add & replace, update, freshen, synchronize
- **Path mode** — relative, full or absolute pathnames
- **Delete files after compression**
- **Encryption** — password with confirmation, *show password*, AES-256 / ZipCrypto, *encrypt file names*

Format, level, update and path modes are remembered between runs.

### 📂 Extract dialog
Destination folder with a **…** picker, **extract into a subfolder** (or a separate folder per archive),
**path mode** (full / no pathnames), **overwrite mode** (auto rename, overwrite, skip, rename existing) and **password**.

### ⏱ Progress window
Current file, percentage, elapsed time, **Pause / Continue** and **Cancel**.
Encrypted archives ask for the password up front; a wrong password can be re-entered right away.
If something goes wrong, the full log is one click away.

### 🪟 Main window
Launch the app on its own and you get a compact window with a **drag & drop zone**
(drop files to compress, archives to extract), the Finder extension status and an
**Install new version…** button for updating 7-Zip itself.

### 🌍 English and Russian
The interface follows your macOS language. To pick a language just for 7-Zip:
**System Settings → General → Language & Region → Applications → +** → 7-Zip → English / Русский,
then restart 7-Zip. The Finder submenu always follows the system language.

## 🚀 Installation

**Requirements:** macOS 13 Ventura or later.

### Ready-made build (recommended)

1. Download the latest **`7-Zip-….dmg`** from [**Releases**](https://github.com/eluz1ve/7zip-mac/releases/latest).
   The official 7-Zip engine is already inside — nothing else to install.
2. Open the image and drag **7-Zip** to **Applications**.
3. Launch 7-Zip once. The app isn't notarized by Apple, so macOS blocks the first launch:
   open **System Settings → Privacy & Security** and press **Open Anyway**.
4. Right-click any file in Finder → **7-Zip**. The Finder extension is enabled automatically on first launch;
   if the submenu is missing, press **Extension settings…** in the 7-Zip window.

### Build from source

Needs Xcode or the Command Line Tools (`xcode-select --install`).

1. Download the **macOS console version** of 7-Zip (`7z….-mac.tar.xz`, or `-mac-x64` for Intel) from [7-zip.org](https://www.7-zip.org/download.html).
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

### For maintainers: publishing a release

When a new 7-Zip comes out: **Actions → Release → Run workflow**, paste the link to the macOS console archive from the
[7-Zip download page](https://www.7-zip.org/download.html)
(for example `https://github.com/ip7z/7zip/releases/download/26.06/7z2606-mac.tar.xz`) and run.
Either build works — the Apple Silicon (`-mac`) or the Intel (`-mac-x64`) one: the workflow fetches its pair
from the same place (only 7-zip.org or github.com/ip7z/7zip), combines them into a universal engine,
builds 7-Zip.app with it inside, packs a `.dmg` and publishes the release with checksums.
The same build runs locally: `./release.sh <link or path to the archive>` → `dist/`.

---

## ⚖️ License

**MIT** — see [LICENSE](LICENSE).

This is an independent, unofficial project. It is **not affiliated with, endorsed by or sponsored by**
Igor Pavlov, the 7-Zip project or Apple. The code and builds are provided **"as is"**, without warranty of any kind.
The source code doesn't include 7-Zip; ready-made releases contain the unmodified official `7zz`
from [7-zip.org](https://www.7-zip.org/) together with its license (`Contents/Resources/7-Zip/License.txt`).
7-Zip is © Igor Pavlov, licensed under the GNU LGPL (with the unRAR restriction).
