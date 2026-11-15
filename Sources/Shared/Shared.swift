import Foundation

/// Код, общий для приложения и расширения Finder.

let szIsRussian: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")

/// Строка интерфейса: русская, если система на русском, иначе английская.
func L(_ en: String, _ ru: String) -> String { szIsRussian ? ru : en }

enum SZAction: String {
    case add            // окно «Добавить к архиву»
    case add7z          // сразу в name.7z
    case addZip = "addzip"
    case extract        // окно «Распаковать»
    case extractHere = "extracthere"
    case extractTo = "extractto"   // в папку name/
    case test
}

enum SZShared {
    static let urlScheme = "sevenzip"
    static let appBundleID = "local.sevenzip.SevenZip"

    static let archiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "tbz", "xz", "txz",
        "zst", "tzst", "lzma", "z", "taz", "wim", "esd", "iso", "cab", "arj", "lzh", "lha",
        "cpio", "rpm", "deb", "dmg", "jar", "xar", "pkg", "apk", "vhd", "vhdx",
        "squashfs", "001",
    ]

    /// Расширения «сжатого tar»: распаковываются в один приём (как tar -xf).
    static let singleStreamExtensions: Set<String> = ["gz", "bz2", "xz", "zst", "lzma", "z"]
    static let tarShortExtensions: Set<String> = ["tgz", "tbz2", "tbz", "txz", "tzst", "taz"]

    static func isArchive(_ url: URL) -> Bool {
        !url.hasDirectoryPath && archiveExtensions.contains(url.pathExtension.lowercased())
    }

    /// file.tar.gz, file.tgz и т.п.
    static func isCompressedTar(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if tarShortExtensions.contains(ext) { return true }
        if singleStreamExtensions.contains(ext) {
            return url.deletingPathExtension().pathExtension.lowercased() == "tar"
        }
        return false
    }

    /// Имя архива по умолчанию (без расширения) — как в 7-Zip для Windows.
    static func archiveBaseName(for items: [URL]) -> String {
        guard let first = items.first else { return "Archive" }
        if items.count == 1 {
            let name = first.hasDirectoryPath ? first.lastPathComponent
                                              : first.deletingPathExtension().lastPathComponent
            return name.isEmpty ? "Archive" : name
        }
        let parent = first.deletingLastPathComponent().lastPathComponent
        return (parent.isEmpty || parent == "/") ? "Archive" : parent
    }

    /// Имя папки для «Распаковать в name/».
    static func extractFolderName(for archive: URL) -> String {
        var url = archive.deletingPathExtension()
        let ext = archive.pathExtension.lowercased()
        let inner = url.pathExtension.lowercased()
        if (singleStreamExtensions.contains(ext) && inner == "tar") || (ext == "001" && !inner.isEmpty) {
            url = url.deletingPathExtension()
        }
        let name = url.lastPathComponent
        return name.isEmpty ? "Extracted" : name
    }

    static func makeURL(action: SZAction, files: [URL]) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = action.rawValue
        components.queryItems = files.map { URLQueryItem(name: "f", value: $0.path) }
        return components.url
    }

    static func parse(_ url: URL) -> (action: SZAction, files: [URL])? {
        guard url.scheme?.lowercased() == urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let action = SZAction(rawValue: (components.host ?? "").lowercased()) else { return nil }
        let files = (components.queryItems ?? [])
            .filter { $0.name == "f" }
            .compactMap { $0.value }
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0) }
        return files.isEmpty ? nil : (action, files)
    }
}
