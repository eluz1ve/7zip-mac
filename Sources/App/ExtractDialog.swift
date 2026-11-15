import Cocoa
import SwiftUI

/// Окно «Распаковать».

final class ExtractModel: ObservableObject {
    let archives: [URL]
    @Published var destination: String
    @Published var useSubfolder: Bool
    @Published var subfolder: String
    @Published var withPaths = true
    @Published var overwrite: OverwriteMode
    @Published var password = ""
    @Published var showPassword = false

    init(archives: [URL]) {
        self.archives = archives
        let first = archives[0]
        destination = first.deletingLastPathComponent().path
        useSubfolder = true
        subfolder = archives.count == 1 ? SZShared.extractFolderName(for: first) : "*"
        overwrite = OverwriteMode(rawValue: UserDefaults.standard.string(forKey: "extract.overwrite") ?? "") ?? .rename
    }

    func commands() -> [SZCommand] {
        UserDefaults.standard.set(overwrite.rawValue, forKey: "extract.overwrite")
        let base = URL(fileURLWithPath: destination, isDirectory: true)
        return archives.map { archive in
            var target = base
            if useSubfolder {
                let name = (archives.count > 1 || subfolder == "*" || subfolder.isEmpty)
                    ? SZShared.extractFolderName(for: archive) : subfolder
                target = base.appendingPathComponent(name, isDirectory: true)
            }
            return SZCommands.extract(archive: archive, destination: target, overwrite: overwrite,
                                      withPaths: withPaths, password: password)
        }
    }
}

struct ExtractView: View {
    @ObservedObject var model: ExtractModel
    let onOK: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Extract to:", "Распаковать в:"))
            HStack {
                TextField("", text: $model.destination)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .help(model.destination)
                Button("…") { browse() }
            }
            HStack {
                Toggle(model.archives.count > 1
                       ? L("Separate folder for each archive", "Отдельная папка для каждого архива")
                       : L("Into subfolder:", "В подпапку:"),
                       isOn: $model.useSubfolder)
                if model.archives.count == 1 {
                    TextField("", text: $model.subfolder)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .disabled(!model.useSubfolder)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Path mode:", "Режим путей:"))
                    Picker("", selection: $model.withPaths) {
                        Text(L("Full pathnames", "Полные пути")).tag(true)
                        Text(L("No pathnames", "Без путей")).tag(false)
                    }
                    .labelsHidden()
                    Text(L("Overwrite mode:", "Перезапись:"))
                    Picker("", selection: $model.overwrite) {
                        ForEach(OverwriteMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                .frame(width: 300, alignment: .leading)

                GroupBox(L("Password", "Пароль")) {
                    VStack(alignment: .leading, spacing: 7) {
                        if model.showPassword {
                            TextField("", text: $model.password).textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("", text: $model.password).textFieldStyle(.roundedBorder)
                        }
                        Toggle(L("Show password", "Показать пароль"), isOn: $model.showPassword)
                    }
                    .padding(4)
                }
                .frame(width: 240)
            }

            HStack {
                Text(model.archives.count == 1 ? model.archives[0].lastPathComponent
                     : L("\(model.archives.count) archives", "Архивов: \(model.archives.count)"))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L("Cancel", "Отмена"), action: onCancel).keyboardShortcut(.cancelAction)
                Button("OK", action: onOK).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 564)
        .padding(18)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: model.destination, isDirectory: true)
        panel.prompt = L("Choose", "Выбрать")
        if panel.runModal() == .OK, let url = panel.url {
            model.destination = url.path
        }
    }
}

final class ExtractDialogController: NSObject, NSWindowDelegate {
    private let model: ExtractModel
    private var window: NSWindow?
    private let onFinish: (ExtractDialogController, [SZCommand]?) -> Void

    init(archives: [URL], onFinish: @escaping (ExtractDialogController, [SZCommand]?) -> Void) {
        self.model = ExtractModel(archives: archives)
        self.onFinish = onFinish
        super.init()
    }

    func show() {
        let view = ExtractView(model: model,
                               onOK: { [weak self] in self?.confirm() },
                               onCancel: { [weak self] in self?.finish(nil) })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = L("Extract", "Распаковать")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirm() {
        guard model.destination.hasPrefix("/") else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Specify the full path to the destination folder.",
                                  "Укажите полный путь к папке назначения.")
            if let window = window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        finish(model.commands())
    }

    private func finish(_ commands: [SZCommand]?) {
        onFinish(self, commands)
        window?.delegate = nil
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(nil)
        return false
    }
}
