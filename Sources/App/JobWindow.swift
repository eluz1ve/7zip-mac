import Cocoa
import SwiftUI

/// Окно прогресса: выполняет очередь команд 7zz по одной.

final class JobModel: ObservableObject {
    @Published var title = ""
    @Published var currentFile = ""
    @Published var percent: Double?
    @Published var elapsed: TimeInterval = 0
    @Published var paused = false
    @Published var counter = ""

    var onPauseToggle: () -> Void = {}
    var onCancel: () -> Void = {}
}

struct JobView: View {
    @ObservedObject var model: JobModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.title).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(model.counter).foregroundStyle(.secondary)
            }
            if let percent = model.percent {
                ProgressView(value: percent, total: 100)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text(model.currentFile.isEmpty ? " " : model.currentFile)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(model.percent.map { "\(Int($0))%" } ?? "")
                    .monospacedDigit()
            }
            HStack {
                Text(L("Elapsed time: ", "Прошло: ") + Self.format(model.elapsed))
                    .monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button(model.paused ? L("Continue", "Продолжить") : L("Pause", "Пауза")) { model.onPauseToggle() }
                Button(L("Cancel", "Отмена")) { model.onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 500)
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

final class JobController: NSObject, NSWindowDelegate {
    private let model = JobModel()
    private var queue: [SZCommand]
    private let total: Int
    private var runner: SZRunner?
    private var window: NSWindow?
    private var timer: Timer?
    private var startDate = Date()
    private var pausedAt: Date?
    private var warnings: [String] = []
    private var summaries: [String] = []
    private var rememberedPassword: String?
    private var finished = false
    private let onClose: (JobController) -> Void

    init(commands: [SZCommand], onClose: @escaping (JobController) -> Void) {
        self.queue = commands
        self.total = commands.count
        self.onClose = onClose
        super.init()
    }

    func start() {
        let hosting = NSHostingController(rootView: JobView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "7-Zip"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        model.onCancel = { [weak self] in self?.cancel() }
        model.onPauseToggle = { [weak self] in self?.togglePause() }

        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.pausedAt == nil else { return }
            self.model.elapsed = Date().timeIntervalSince(self.startDate)
        }
        runNext()
    }

    // MARK: Очередь

    private func runNext() {
        guard !queue.isEmpty else { finish(); return }
        let command = queue.removeFirst()
        model.title = command.title
        model.counter = total > 1 ? "\(total - queue.count) / \(total)" : ""
        model.percent = nil
        model.currentFile = ""

        // Если архив зашифрован — спросим пароль заранее, а не после ошибки.
        if let archive = command.archiveToProbe, rememberedPassword == nil {
            DispatchQueue.global(qos: .userInitiated).async {
                let encrypted = SevenZip.isEncrypted(archive)
                DispatchQueue.main.async {
                    if encrypted {
                        guard let password = self.askPassword(for: archive.lastPathComponent, wrong: false) else {
                            self.close(); return
                        }
                        self.rememberedPassword = password
                    }
                    self.execute(command)
                }
            }
        } else {
            execute(command)
        }
    }

    private func execute(_ command: SZCommand) {
        let runner = SZRunner()
        self.runner = runner
        let password = command.mayNeedPassword ? rememberedPassword : nil
        runner.run(command, password: password, progress: { [weak self] percent, file in
            guard let self = self else { return }
            if let percent = percent { self.model.percent = percent }
            if let file = file { self.model.currentFile = file }
        }, completion: { [weak self] status, log in
            self?.completed(command, status: status, log: log, runner: runner)
        })
    }

    private func completed(_ command: SZCommand, status: Int32, log: String, runner: SZRunner) {
        self.runner = nil
        if runner.wasCancelled { close(); return }

        switch status {
        case 0:
            if command.showsSummary { summaries.append(Self.summary(of: log, title: command.title)) }
            runNext()
        case 1:
            warnings.append(command.title + "\n" + Self.tail(of: log))
            runNext()
        default:
            let lowered = log.lowercased()
            let passwordProblem = lowered.contains("wrong password") || lowered.contains("enter password")
            if command.mayNeedPassword, passwordProblem {
                let archiveName = command.args.last.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                if let password = askPassword(for: archiveName, wrong: rememberedPassword != nil) {
                    rememberedPassword = password
                    execute(command)
                } else {
                    close()
                }
                return
            }
            model.percent = 0
            showLog(title: L("7-Zip reported an error", "7-Zip сообщил об ошибке"),
                    text: command.title + "\n\n" + Self.tail(of: log), style: .critical)
            close()
        }
    }

    private func finish() {
        model.percent = 100
        if !warnings.isEmpty {
            showLog(title: L("Completed with warnings", "Завершено с предупреждениями"),
                    text: warnings.joined(separator: "\n\n"), style: .warning)
        } else if !summaries.isEmpty {
            showLog(title: L("There are no errors", "Ошибок не обнаружено"),
                    text: summaries.joined(separator: "\n\n"), style: .informational)
        }
        close()
    }

    // MARK: Управление

    private func cancel() {
        if let runner = runner {
            runner.cancel()   // окно закроется в completed()
        } else {
            close()
        }
    }

    private func togglePause() {
        guard let runner = runner else { return }
        model.paused.toggle()
        runner.setPaused(model.paused)
        if model.paused {
            pausedAt = Date()
        } else if let pausedAt = pausedAt {
            startDate = startDate.addingTimeInterval(Date().timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
    }

    private func close() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        window?.delegate = nil
        window?.close()
        onClose(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

    // MARK: Диалоги

    private func askPassword(for archiveName: String, wrong: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = wrong ? L("Wrong password. Try again:", "Неверный пароль. Попробуйте ещё раз:")
                                  : L("Enter password", "Введите пароль")
        alert.informativeText = archiveName
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L("Cancel", "Отмена"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    private func showLog(title: String, text: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        scroll.borderType = .bezelBorder
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.string = text
            textView.textContainerInset = NSSize(width: 4, height: 4)
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func tail(of log: String, lines count: Int = 60) -> String {
        let lines = log.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(count).joined(separator: "\n")
    }

    /// Короткий итог теста: строки «Everything is Ok», количество файлов, размер.
    private static func summary(of log: String, title: String) -> String {
        let interesting = ["Everything is Ok", "Folders:", "Files:", "Size:", "Compressed:"]
        let lines = log.split(whereSeparator: \.isNewline).map(String.init)
            .filter { line in interesting.contains(where: line.hasPrefix) }
        return ([title] + lines).joined(separator: "\n")
    }
}
