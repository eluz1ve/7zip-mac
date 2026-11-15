import Foundation

/// Поиск бинарника 7zz и запуск его с разбором прогресса.
enum SevenZip {
    static let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/7-Zip")

    /// 7zz, который лежит внутри приложения (есть в готовых релизах).
    static var bundledURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "7zz")
            .flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    private static let lock = NSLock()
    private static var cachedBinary: URL??

    /// Какой 7zz запускать. Установленный отдельно (install.sh, «Установить новую версию…»)
    /// и встроенный в релиз сравниваются по версии — берётся более новый,
    /// при равных версиях — установленный отдельно.
    static var binaryURL: URL? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cachedBinary { return cached }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let installed = [
            supportDirectory.appendingPathComponent("bin/7zz").path,
            home + "/.local/bin/7zz",
            "/opt/homebrew/bin/7zz",
            "/usr/local/bin/7zz",
        ].first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))

        var chosen = installed ?? bundledURL
        if let installed = installed, let bundled = bundledURL,
           let a = versionNumber(of: installed), let b = versionNumber(of: bundled), b > a {
            chosen = bundled
        }
        cachedBinary = .some(chosen)
        return chosen
    }

    /// Забыть выбранный 7zz (после установки новой версии).
    static func resetBinary() {
        lock.lock(); cachedBinary = nil; lock.unlock()
    }

    /// Версия как число для сравнения: 26.06 → 2606.
    private static func versionNumber(of binary: URL) -> Int? {
        guard let text = versionString(of: binary) else { return nil }
        let number = text.split(separator: " ").first.map(String.init) ?? text
        let parts = number.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 100 + parts[1]
    }

    /// Например «26.06 (arm64)».
    static func versionString() -> String? {
        guard let binary = binaryURL else { return nil }
        return versionString(of: binary)
    }

    private static func versionString(of binary: URL) -> String? {
        let process = Process()
        process.executableURL = binary
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.contains("7-Zip") }) else { return nil }
        // "7-Zip (z) 26.06 (arm64) : Copyright ..."
        let head = line.split(separator: ":").first.map(String.init) ?? String(line)
        return head.replacingOccurrences(of: "7-Zip", with: "")
            .replacingOccurrences(of: "(z)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Быстрая проверка: зашифрован ли архив (заголовки или файлы).
    static func isEncrypted(_ archive: URL) -> Bool {
        guard let binary = binaryURL else { return false }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["l", "-slt", archive.path]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return false }
        var found = false
        var tail = Data()
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            if found { continue }
            let window = tail + chunk
            let text = String(decoding: window, as: UTF8.self)
            if text.contains("Encrypted = +") || text.contains("Enter password") {
                found = true
                process.terminate()
            }
            tail = window.suffix(32)
        }
        process.waitUntilExit()
        return found
    }
}

/// Одна операция 7zz (или конвейер из двух процессов для .tar.gz и т.п.).
struct SZCommand {
    /// Заголовок в окне прогресса, например «Сжатие — Photos.7z».
    var title: String
    var args: [String]
    /// Если задано — второй 7zz, читающий stdin от первого.
    var pipeArgs: [String]? = nil
    /// Распаковка/тест: можно спросить пароль и повторить.
    var mayNeedPassword = false
    /// Архив, который стоит проверить на шифрование до запуска.
    var archiveToProbe: URL? = nil
    /// Показать итог даже при успехе (для «Тестировать»).
    var showsSummary = false
    /// Временные файлы, которые надо удалить после выполнения.
    var temporaryFiles: [URL] = []
}

final class SZRunner {
    private var processes: [Process] = []
    private let lock = NSLock()
    private var cancelRequested = false
    private var suspended = false

    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelRequested }

    /// progress(процент или nil, текущий файл или nil), completion(код возврата, журнал) — на главном потоке.
    func run(_ command: SZCommand, password: String?,
             progress: @escaping (Double?, String?) -> Void,
             completion: @escaping (Int32, String) -> Void) {
        guard let binary = SevenZip.binaryURL else {
            completion(-1, L("7zz was not found. Reinstall 7-Zip or use “Install new version…” in the main window.",
                             "Не найден 7zz. Переустановите 7-Zip или нажмите «Установить новую версию…» в главном окне."))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let log = LogBuffer()
            let group = DispatchGroup()

            let first = Process()
            first.executableURL = binary
            var args = command.args
            if let password = password, !password.isEmpty { args.insert("-p" + password, at: 1) }
            first.arguments = args
            first.standardInput = FileHandle.nullDevice
            let firstError = Pipe()
            first.standardError = firstError

            var second: Process?
            var link: Pipe?
            if let pipeArgs = command.pipeArgs {
                let connection = Pipe()
                link = connection
                first.standardOutput = connection
                let process = Process()
                process.executableURL = binary
                process.arguments = pipeArgs
                process.standardInput = connection
                let output = Pipe()
                process.standardOutput = output
                process.standardError = output
                Self.drain(output, group: group) { log.append($0) }
                second = process
            } else {
                let output = Pipe()
                first.standardOutput = output
                Self.drain(output, group: group) { log.append($0) }
            }

            let parser = ProgressParser()
            Self.drain(firstError, group: group) { data in
                for token in parser.feed(data) {
                    switch token {
                    case .progress(let percent, let file):
                        DispatchQueue.main.async { progress(percent, file) }
                    case .scanning:
                        DispatchQueue.main.async { progress(nil, nil) }
                    case .text(let line):
                        log.append(Data((line + "\n").utf8))
                    }
                }
            }

            do {
                try first.run()
                try second?.run()
            } catch {
                if first.isRunning { first.terminate() }
                DispatchQueue.main.async { completion(-1, error.localizedDescription) }
                return
            }
            // Родителю концы соединительной трубы не нужны — иначе второй процесс не увидит конец данных.
            try? link?.fileHandleForWriting.close()
            try? link?.fileHandleForReading.close()

            self.lock.lock()
            self.processes = [first] + (second.map { [$0] } ?? [])
            let alreadyCancelled = self.cancelRequested
            self.lock.unlock()
            if alreadyCancelled { first.interrupt(); second?.interrupt() }

            first.waitUntilExit()
            second?.waitUntilExit()
            group.wait()

            self.lock.lock()
            self.processes = []
            self.lock.unlock()

            for file in command.temporaryFiles { try? FileManager.default.removeItem(at: file) }

            let status = max(first.terminationStatus, second?.terminationStatus ?? 0)
            let reason: Int32 = (first.terminationReason == .uncaughtSignal
                                 || second?.terminationReason == .uncaughtSignal) ? 255 : status
            let text = log.text
            DispatchQueue.main.async { completion(reason, text) }
        }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let running = processes
        let wasSuspended = suspended
        suspended = false
        lock.unlock()
        for process in running where process.isRunning {
            if wasSuspended { process.resume() }
            process.interrupt()   // SIGINT: 7zz сам удалит недописанный архив
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            for process in running where process.isRunning { process.terminate() }
        }
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        let running = processes
        suspended = paused
        lock.unlock()
        for process in running where process.isRunning {
            if paused { _ = process.suspend() } else { _ = process.resume() }
        }
    }

    private static func drain(_ pipe: Pipe, group: DispatchGroup, handler: @escaping (Data) -> Void) {
        group.enter()
        let handle = pipe.fileHandleForReading
        Thread.detachNewThread {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                handler(chunk)
            }
            group.leave()
        }
    }
}

/// Потокобезопасный журнал вывода с ограничением размера.
private final class LogBuffer {
    private var data = Data()
    private let lock = NSLock()
    private let limit = 256 * 1024

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        if data.count > limit { data = data.suffix(limit / 2) }
        lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Разбирает поток прогресса 7zz (-bsp2): куски, разделённые backspace / CR / LF.
final class ProgressParser {
    enum Token {
        case progress(Double, String?)
        case scanning
        case text(String)
    }

    private var buffer = Data()
    private static let percentPattern = try! NSRegularExpression(
        pattern: #"^(\d{1,3})%(?:\s+\d+)?(?:\s+[-+=.A-Z])?(?:\s+(.*))?$"#)
    private static let scanPattern = try! NSRegularExpression(pattern: #"^\d+\s*[KMG]?\s+Scan\b"#)

    func feed(_ data: Data) -> [Token] {
        buffer.append(data)
        guard let lastSeparator = buffer.lastIndex(where: { $0 == 8 || $0 == 10 || $0 == 13 }) else { return [] }
        let complete = buffer.prefix(through: lastSeparator)
        buffer = Data(buffer.suffix(from: buffer.index(after: lastSeparator)))

        var tokens: [Token] = []
        for piece in complete.split(whereSeparator: { $0 == 8 || $0 == 10 || $0 == 13 }) {
            let text = String(decoding: piece, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = Self.percentPattern.firstMatch(in: text, range: range),
               let percentRange = Range(match.range(at: 1), in: text),
               let percent = Double(text[percentRange]) {
                var file: String?
                if let fileRange = Range(match.range(at: 2), in: text) {
                    let name = String(text[fileRange])
                    if !name.isEmpty { file = name }
                }
                tokens.append(.progress(min(percent, 100), file))
            } else if Self.scanPattern.firstMatch(in: text, range: range) != nil {
                tokens.append(.scanning)
            } else {
                tokens.append(.text(text))
            }
        }
        return tokens
    }
}
