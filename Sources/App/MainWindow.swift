import Cocoa
import SwiftUI
import FinderSync
import UniformTypeIdentifiers

/// Главное окно: показывается, когда 7-Zip.app запущен просто так, без файлов.

final class MainModel: ObservableObject {
    @Published var version = "…"
    @Published var extensionEnabled = false
    @Published var updating = false

    var onAdd: () -> Void = {}
    var onExtract: () -> Void = {}
    var onDrop: ([URL]) -> Void = { _ in }
    var onUpdate: () -> Void = {}

    func refresh() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
        DispatchQueue.global(qos: .userInitiated).async {
            let version = SevenZip.versionString()
            DispatchQueue.main.async {
                self.version = version ?? L("7zz is not installed", "7zz не установлен")
            }
        }
    }
}

struct MainView: View {
    @ObservedObject var model: MainModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("7-Zip").font(.title).bold()
                    Text(model.version).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
            }

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc").font(.system(size: 26)).foregroundStyle(.secondary)
                Text(L("Drop files here to compress,\nor archives to extract",
                       "Перетащите сюда файлы, чтобы сжать,\nили архивы, чтобы распаковать"))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("Add to archive…", "Добавить к архиву…")) { model.onAdd() }
                    Button(L("Extract archive…", "Распаковать архив…")) { model.onExtract() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6, 4]))
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                collect(providers)
                return true
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: model.extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.extensionEnabled ? Color.green : Color.orange)
                    Text(model.extensionEnabled
                         ? L("Finder context menu is enabled", "Меню 7-Zip в Finder включено")
                         : L("Finder context menu is disabled", "Меню 7-Zip в Finder выключено"))
                    Spacer()
                    Button(L("Extension settings…", "Настройки расширений…")) {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }
                }
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                    Text(L("New 7-Zip release?", "Вышла новая версия 7-Zip?"))
                        .lineLimit(1)
                    Spacer()
                    if model.updating { ProgressView().controlSize(.small) }
                    Button(L("Install new version…", "Установить новую версию…")) { model.onUpdate() }
                        .disabled(model.updating)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func collect(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { model.onDrop(urls.sorted { $0.path < $1.path }) }
        }
    }
}

final class MainWindowController: NSObject, NSWindowDelegate {
    let model = MainModel()
    private(set) var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(model: model)))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "7-Zip"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.extensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    /// Запускает встроенный скрипт обновления для выбранного архива/папки с новой версией.
    func runUpdater() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = L("Choose the downloaded 7z…-mac.tar.xz file or the unpacked folder",
                          "Выберите скачанный файл 7z…-mac.tar.xz или распакованную папку")
        panel.prompt = L("Install", "Установить")
        guard panel.runModal() == .OK, let source = panel.url,
              let script = Bundle.main.url(forResource: "update-7zz", withExtension: "sh") else { return }

        model.updating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, source.path]
            var environment = ProcessInfo.processInfo.environment
            environment["SEVENZIP_FROM_APP"] = "1"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var output = ""
            var status: Int32 = -1
            do {
                try process.run()
                output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                status = process.terminationStatus
            } catch {
                output = error.localizedDescription
            }
            SevenZip.resetBinary()
            DispatchQueue.main.async {
                self.model.updating = false
                self.model.refresh()
                let alert = NSAlert()
                alert.alertStyle = status == 0 ? .informational : .warning
                alert.messageText = status == 0 ? L("Done", "Готово") : L("Update failed", "Не удалось обновить")
                alert.informativeText = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if let window = self.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
    }
}
