import Foundation

/// Построение командных строк 7zz из параметров окон.

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZ = "7z", bzip2, gzip, tar, wim, xz, zip

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .sevenZ: return "7z"
        case .bzip2: return "bz2"
        case .gzip: return "gz"
        case .tar: return "tar"
        case .wim: return "wim"
        case .xz: return "xz"
        case .zip: return "zip"
        }
    }

    /// Первый метод — метод по умолчанию.
    var methods: [String] {
        switch self {
        case .sevenZ: return ["LZMA2", "LZMA", "PPMd", "BZip2"]
        case .zip: return ["Deflate", "Deflate64", "BZip2", "LZMA", "PPMd"]
        case .gzip: return ["Deflate"]
        case .bzip2: return ["BZip2"]
        case .xz: return ["LZMA2"]
        case .tar, .wim: return []
        }
    }

    var levels: [Int] {
        switch self {
        case .sevenZ, .zip: return [0, 1, 3, 5, 7, 9]
        case .gzip, .bzip2, .xz: return [1, 3, 5, 7, 9]
        case .tar, .wim: return [0]
        }
    }

    var supportsSolid: Bool { self == .sevenZ }
    var supportsEncryptNames: Bool { self == .sevenZ }
    /// Формат сжимает только один файл (не папку и не несколько файлов).
    var singleFileOnly: Bool { self == .bzip2 || self == .gzip || self == .xz }

    var encryptionMethods: [String] {
        switch self {
        case .sevenZ: return ["AES-256"]
        case .zip: return ["ZipCrypto", "AES-256"]
        default: return []
        }
    }
}

enum UpdateMode: String, CaseIterable, Identifiable {
    case add, update, freshen, sync
    var id: String { rawValue }
    var title: String {
        switch self {
        case .add: return L("Add and replace files", "Добавить и заменить")
        case .update: return L("Update and add files", "Обновить и добавить")
        case .freshen: return L("Freshen existing files", "Освежить")
        case .sync: return L("Synchronize files", "Синхронизировать")
        }
    }
}

enum PathMode: String, CaseIterable, Identifiable {
    case relative, full, absolute
    var id: String { rawValue }
    var title: String {
        switch self {
        case .relative: return L("Relative pathnames", "Относительные пути")
        case .full: return L("Full pathnames", "Полные пути")
        case .absolute: return L("Absolute pathnames", "Абсолютные пути")
        }
    }
}

enum OverwriteMode: String, CaseIterable, Identifiable {
    case rename, overwrite, skip, renameExisting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rename: return L("Auto rename", "Переименовывать автоматически")
        case .overwrite: return L("Overwrite without prompt", "Перезаписывать без подтверждения")
        case .skip: return L("Skip existing files", "Пропускать существующие")
        case .renameExisting: return L("Auto rename existing files", "Переименовывать существующие")
        }
    }
    var flag: String {
        switch self {
        case .rename: return "-aou"
        case .overwrite: return "-aoa"
        case .skip: return "-aos"
        case .renameExisting: return "-aot"
        }
    }
}

struct AddOptions {
    var archivePath: String
    var format: ArchiveFormat = .sevenZ
    var level: Int = 5
    /// Пустая строка = значение по умолчанию.
    var method = ""
    var dictionary = ""
    var word = ""
    var solid = ""
    var threads = ""
    var volumeSize = ""
    var parameters = ""
    var updateMode: UpdateMode = .add
    var pathMode: PathMode = .relative
    var deleteAfter = false
    var password = ""
    var encryptionMethod = ""
    var encryptNames = false
}

enum SZCommands {

    static func add(files: [URL], options: AddOptions) -> SZCommand {
        let format = options.format
        var args: [String] = [options.updateMode == .add ? "a" : "u"]
        args.append("-t" + format.rawValue)

        let compresses = format.levels.count > 1 && options.level > 0
        if format.levels.count > 1 { args.append("-mx=\(options.level)") }

        if compresses {
            let defaultMethod = format.methods.first ?? ""
            let method = options.method.isEmpty ? defaultMethod : options.method
            if method != defaultMethod {
                args.append((format == .zip ? "-mm=" : "-m0=") + method)
            }
            if !options.dictionary.isEmpty {
                args.append((method == "PPMd" ? "-mmem=" : "-md=") + options.dictionary)
            }
            if !options.word.isEmpty {
                args.append((method == "PPMd" ? "-mo=" : "-mfb=") + options.word)
            }
        }
        if format.supportsSolid, !options.solid.isEmpty { args.append("-ms=" + options.solid) }
        if !options.threads.isEmpty { args.append("-mmt=" + options.threads) }

        switch options.updateMode {
        case .add, .update: break
        case .freshen: args.append("-ur0")
        case .sync: args.append("-uq0")
        }
        switch options.pathMode {
        case .relative: break
        case .full: args.append("-spf2")
        case .absolute: args.append("-spf")
        }
        if options.deleteAfter { args.append("-sdel") }

        let volume = options.volumeSize.replacingOccurrences(of: " ", with: "").lowercased()
        if !volume.isEmpty { args.append("-v" + volume) }

        if !options.password.isEmpty, !format.encryptionMethods.isEmpty {
            args.append("-p" + options.password)
            if format == .zip {
                let method = options.encryptionMethod.isEmpty ? "ZipCrypto" : options.encryptionMethod
                args.append("-mem=" + (method == "AES-256" ? "AES256" : "ZipCrypto"))
            }
            if format.supportsEncryptNames, options.encryptNames { args.append("-mhe=on") }
        }

        args.append(contentsOf: splitParameters(options.parameters))
        args.append(contentsOf: ["-bsp2", "-bso1", "-bse2"])
        args.append(options.archivePath)

        // Очень длинные списки файлов передаём через файл-список.
        var temporaryFiles: [URL] = []
        let paths = files.map(\.path)
        let canUseListFile = !paths.contains(where: { $0.contains("\n") })
        if canUseListFile, paths.reduce(0, { $0 + $1.utf8.count + 1 }) > 100_000 {
            let listFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("7zip-list-\(UUID().uuidString).txt")
            if (try? paths.joined(separator: "\n").write(to: listFile, atomically: true, encoding: .utf8)) != nil {
                args.append("@" + listFile.path)
                temporaryFiles.append(listFile)
            } else {
                args.append(contentsOf: paths)
            }
        } else {
            args.append(contentsOf: paths)
        }

        let name = URL(fileURLWithPath: options.archivePath).lastPathComponent
        return SZCommand(title: L("Compressing — \(name)", "Сжатие — \(name)"),
                         args: args, temporaryFiles: temporaryFiles)
    }

    static func extract(archive: URL, destination: URL, overwrite: OverwriteMode,
                        withPaths: Bool = true, password: String = "") -> SZCommand {
        let title = L("Extracting — \(archive.lastPathComponent)", "Распаковка — \(archive.lastPathComponent)")
        let verb = withPaths ? "x" : "e"

        if SZShared.isCompressedTar(archive) {
            // file.tar.gz → распаковываем сжатие и tar одним конвейером.
            return SZCommand(
                title: title,
                args: ["x", "-so", "-bsp2", "-bso0", "-bse2", archive.path],
                pipeArgs: [verb, "-si", "-ttar", "-o" + destination.path, overwrite.flag, "-bsp0", "-bso0"])
        }
        var args = [verb]
        if !password.isEmpty { args.append("-p" + password) }
        args.append(contentsOf: ["-o" + destination.path, overwrite.flag, "-bsp2", "-bso1", "-bse2", archive.path])
        return SZCommand(title: title, args: args, mayNeedPassword: true,
                         archiveToProbe: password.isEmpty ? archive : nil)
    }

    static func test(archive: URL) -> SZCommand {
        SZCommand(title: L("Testing — \(archive.lastPathComponent)", "Тестирование — \(archive.lastPathComponent)"),
                  args: ["t", "-bsp2", "-bso1", "-bse2", archive.path],
                  mayNeedPassword: true, archiveToProbe: archive, showsSummary: true)
    }

    /// Разбивает строку дополнительных параметров по пробелам с учётом кавычек.
    static func splitParameters(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
