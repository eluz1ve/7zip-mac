import Cocoa
import SwiftUI

/// Окно «Добавить к архиву» — по образцу 7-Zip для Windows.

struct Choice: Identifiable, Hashable {
    let value: String   // "" = автоматически
    let label: String
    var id: String { value }
}

final class AddModel: ObservableObject {
    let files: [URL]

    @Published var archivePath: String
    @Published var format: ArchiveFormat { didSet { formatChanged(from: oldValue) } }
    @Published var level: Int { didSet { normalize() } }
    @Published var method: String { didSet { if method != oldValue { dictionary = ""; word = "" } } }
    @Published var dictionary = ""
    @Published var word = ""
    @Published var solid = ""
    @Published var threads = ""
    @Published var volumeSize = ""
    @Published var parameters = ""
    @Published var updateMode: UpdateMode
    @Published var pathMode: PathMode
    @Published var deleteAfter = false
    @Published var password = ""
    @Published var passwordRepeat = ""
    @Published var showPassword = false
    @Published var encryptionMethod = ""
    @Published var encryptNames = false

    init(files: [URL]) {
        self.files = files
        let defaults = UserDefaults.standard
        let format = ArchiveFormat(rawValue: defaults.string(forKey: "add.format") ?? "") ?? .sevenZ
        self.format = format
        let savedLevel = defaults.object(forKey: "add.level") as? Int ?? 5
        self.level = format.levels.contains(savedLevel) ? savedLevel : (format.levels.contains(5) ? 5 : format.levels[0])
        self.method = format.methods.first ?? ""
        self.updateMode = UpdateMode(rawValue: defaults.string(forKey: "add.updateMode") ?? "") ?? .add
        self.pathMode = PathMode(rawValue: defaults.string(forKey: "add.pathMode") ?? "") ?? .relative
        self.encryptionMethod = format.encryptionMethods.last ?? ""

        let directory = files.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        self.archivePath = directory
            .appendingPathComponent(SZShared.archiveBaseName(for: files) + "." + format.fileExtension).path
    }

    func rememberSettings() {
        let defaults = UserDefaults.standard
        defaults.set(format.rawValue, forKey: "add.format")
        defaults.set(level, forKey: "add.level")
        defaults.set(updateMode.rawValue, forKey: "add.updateMode")
        defaults.set(pathMode.rawValue, forKey: "add.pathMode")
    }

    // MARK: Зависимости между полями

    private func formatChanged(from old: ArchiveFormat) {
        guard old != format else { return }
        let oldSuffix = "." + old.fileExtension
        if archivePath.lowercased().hasSuffix(oldSuffix) {
            archivePath = String(archivePath.dropLast(oldSuffix.count)) + "." + format.fileExtension
        }
        if !format.levels.contains(level) {
            level = format.levels.contains(5) ? 5 : format.levels[0]
        }
        method = format.methods.first ?? ""
        dictionary = ""
        word = ""
        if !format.supportsSolid { solid = "" }
        if !format.supportsEncryptNames { encryptNames = false }
        encryptionMethod = format.encryptionMethods.last ?? ""
    }

    private func normalize() {
        if level == 0 { dictionary = ""; word = "" }
    }

    var compresses: Bool { format.levels.count > 1 && level > 0 }
    var canEncrypt: Bool { !format.encryptionMethods.isEmpty }
    var effectiveMethod: String { method.isEmpty ? (format.methods.first ?? "") : method }

    // MARK: Списки значений

    static func levelTitle(_ level: Int) -> String {
        switch level {
        case 0: return L("Store", "Без сжатия")
        case 1: return L("Fastest", "Скоростной")
        case 3: return L("Fast", "Быстрый")
        case 5: return L("Normal", "Нормальный")
        case 7: return L("Maximum", "Максимальный")
        default: return L("Ultra", "Ультра")
        }
    }

    private static func sizeLabel(_ value: String) -> String {
        let number = value.dropLast()
        switch value.last {
        case "k": return "\(number) " + L("KB", "КБ")
        case "m": return "\(number) " + L("MB", "МБ")
        case "g": return "\(number) " + L("GB", "ГБ")
        default: return value
        }
    }

    private func auto(_ detail: String?) -> Choice {
        Choice(value: "", label: "* " + (detail ?? L("auto", "авто")))
    }

    var dictionaryChoices: [Choice] {
        guard compresses else { return [] }
        let values: [String]
        var autoDetail: String?
        switch effectiveMethod {
        case "LZMA", "LZMA2":
            values = ["64k", "256k", "1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m", "512m", "1024m"]
            if format == .sevenZ || format == .xz {
                autoDetail = [1: "256k", 3: "4m", 5: "32m", 7: "128m", 9: "256m"][level].map(Self.sizeLabel)
            }
        case "PPMd":
            let all = ["1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m", "512m", "1024m"]
            values = format == .zip ? Array(all.prefix(9)) : all
        case "BZip2":
            values = (1...9).map { "\($0)00k" }
            autoDetail = [1: "100k", 3: "500k", 5: "900k", 7: "900k", 9: "900k"][level].map(Self.sizeLabel)
        case "Deflate":
            return [Choice(value: "", label: Self.sizeLabel("32k"))]
        case "Deflate64":
            return [Choice(value: "", label: Self.sizeLabel("64k"))]
        default:
            return []
        }
        return [auto(autoDetail)] + values.map { Choice(value: $0, label: Self.sizeLabel($0)) }
    }

    var wordChoices: [Choice] {
        guard compresses else { return [] }
        let values: [Int]
        var autoDetail: String?
        switch effectiveMethod {
        case "LZMA", "LZMA2":
            values = [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 273]
            if format == .sevenZ || format == .xz {
                autoDetail = [1: 32, 3: 32, 5: 32, 7: 64, 9: 64][level].map(String.init)
            }
        case "Deflate":
            values = [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 258]
            autoDetail = [1: 32, 3: 32, 5: 32, 7: 64, 9: 128][level].map(String.init)
        case "Deflate64":
            values = [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 257]
            autoDetail = [1: 32, 3: 32, 5: 32, 7: 64, 9: 128][level].map(String.init)
        case "PPMd":
            values = format == .zip ? [2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16]
                                    : [2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32]
        default:
            return []
        }
        return [auto(autoDetail)] + values.map { Choice(value: String($0), label: String($0)) }
    }

    var solidChoices: [Choice] {
        guard format.supportsSolid else { return [] }
        let sizes = ["1m", "16m", "64m", "256m", "1g", "4g", "16g", "64g"]
        return [auto(nil), Choice(value: "off", label: L("Non-solid", "Не непрерывный"))]
            + sizes.map { Choice(value: $0, label: Self.sizeLabel($0)) }
            + [Choice(value: "on", label: L("Solid", "Непрерывный"))]
    }

    var threadChoices: [Choice] {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return [auto("\(cores)")] + (1...max(cores, 1)).map { Choice(value: String($0), label: String($0)) }
    }

    static let volumePresets: [(value: String, label: String)] = [
        ("10M", "10M"), ("100M", "100M"), ("1000M", "1000M"),
        ("650M", "650M — CD"), ("700M", "700M — CD"),
        ("4092M", "4092M — FAT"), ("4480M", "4480M — DVD"),
        ("8128M", "8128M — DVD DL"), ("23040M", "23040M — BD"),
    ]

    // MARK: Результат

    /// Возвращает текст ошибки или nil, если всё в порядке.
    func validate() -> String? {
        if archivePath.trimmingCharacters(in: .whitespaces).isEmpty {
            return L("Specify the archive name.", "Укажите имя архива.")
        }
        if !archivePath.hasPrefix("/") {
            return L("Specify the full path to the archive.", "Укажите полный путь к архиву.")
        }
        if canEncrypt, !showPassword, password != passwordRepeat {
            return L("Passwords do not match.", "Пароли не совпадают.")
        }
        if format.singleFileOnly, files.count != 1 || files[0].hasDirectoryPath {
            return L("The \(format.rawValue) format can compress only a single file. Use tar, 7z or zip for several files or folders.",
                     "Формат \(format.rawValue) сжимает только один файл. Для нескольких файлов или папок выберите tar, 7z или zip.")
        }
        let volume = volumeSize.replacingOccurrences(of: " ", with: "")
        if !volume.isEmpty, volume.range(of: #"^\d+[bkmgBKMG]?$"#, options: .regularExpression) == nil {
            return L("Invalid volume size. Examples: 100M, 4480M, 1G.",
                     "Неверный размер тома. Примеры: 100M, 4480M, 1G.")
        }
        return nil
    }

    var options: AddOptions {
        AddOptions(archivePath: archivePath, format: format, level: level,
                   method: method, dictionary: dictionary, word: word, solid: solid,
                   threads: threads, volumeSize: volumeSize, parameters: parameters,
                   updateMode: updateMode, pathMode: pathMode, deleteAfter: deleteAfter,
                   password: canEncrypt ? password : "", encryptionMethod: encryptionMethod,
                   encryptNames: encryptNames)
    }
}

struct AddView: View {
    @ObservedObject var model: AddModel
    let onOK: () -> Void
    let onCancel: () -> Void

    private let labelWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Archive:", "Архив:"))
                // Ширина поля не зависит от длины пути: длинный путь прокручивается внутри.
                TextField("", text: $model.archivePath)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .help(model.archivePath)
                Button("…") { browse() }
            }

            HStack(alignment: .top, spacing: 20) {
                leftColumn.frame(width: 370)
                rightColumn.frame(width: 320)
            }

            HStack {
                Text(sourceSummary).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L("Cancel", "Отмена"), action: onCancel).keyboardShortcut(.cancelAction)
                Button("OK", action: onOK).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: AddView.contentWidth)
        .padding(18)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Ширина окна фиксирована: колонки 370 + 320 и промежуток 20.
    static let contentWidth: CGFloat = 710

    private var sourceSummary: String {
        if model.files.count == 1 { return model.files[0].lastPathComponent }
        return L("\(model.files.count) items", "Объектов: \(model.files.count)")
    }

    // MARK: Левая колонка

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            row(L("Archive format:", "Формат архива:")) {
                Picker("", selection: $model.format) {
                    ForEach(ArchiveFormat.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            row(L("Compression level:", "Уровень сжатия:")) {
                Picker("", selection: $model.level) {
                    ForEach(model.format.levels, id: \.self) { Text(AddModel.levelTitle($0)).tag($0) }
                }
                .disabled(model.format.levels.count < 2)
            }
            row(L("Compression method:", "Метод сжатия:")) {
                Picker("", selection: $model.method) {
                    if model.format.methods.isEmpty { Text("—").tag("") }
                    ForEach(model.format.methods, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!model.compresses || model.format.methods.count < 2)
            }
            row(L("Dictionary size:", "Размер словаря:")) {
                choicePicker($model.dictionary, model.dictionaryChoices)
            }
            row(L("Word size:", "Размер слова:")) {
                choicePicker($model.word, model.wordChoices)
            }
            row(L("Solid block size:", "Размер блока:")) {
                choicePicker($model.solid, model.solidChoices)
            }
            row(L("Number of CPU threads:", "Число потоков:")) {
                choicePicker($model.threads, model.threadChoices)
            }
            row(L("Split to volumes:", "Разбить на тома:")) {
                HStack(spacing: 4) {
                    TextField(L("size, e.g. 100M", "размер, напр. 100M"), text: $model.volumeSize)
                        .textFieldStyle(.roundedBorder)
                    Menu("") {
                        ForEach(AddModel.volumePresets, id: \.value) { preset in
                            Button(preset.label) { model.volumeSize = preset.value }
                        }
                        Divider()
                        Button(L("Do not split", "Не разбивать")) { model.volumeSize = "" }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)
                }
            }
            row(L("Parameters:", "Параметры:")) {
                TextField("", text: $model.parameters).textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: Правая колонка

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("Update mode:", "Режим изменения:"))
            Picker("", selection: $model.updateMode) {
                ForEach(UpdateMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()

            Text(L("Path mode:", "Режим путей:"))
            Picker("", selection: $model.pathMode) {
                ForEach(PathMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()

            GroupBox(L("Options", "Опции")) {
                Toggle(L("Delete files after compression", "Удалять файлы после сжатия"), isOn: $model.deleteAfter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }

            GroupBox(L("Encryption", "Шифрование")) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("Enter password:", "Введите пароль:"))
                    if model.showPassword {
                        TextField("", text: $model.password).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("", text: $model.password).textFieldStyle(.roundedBorder)
                        Text(L("Reenter password:", "Повторите пароль:"))
                        SecureField("", text: $model.passwordRepeat).textFieldStyle(.roundedBorder)
                    }
                    Toggle(L("Show password", "Показать пароль"), isOn: $model.showPassword)
                    HStack {
                        Text(L("Encryption method:", "Метод шифрования:"))
                        Picker("", selection: $model.encryptionMethod) {
                            if model.format.encryptionMethods.isEmpty { Text("—").tag("") }
                            ForEach(model.format.encryptionMethods, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(model.format.encryptionMethods.count < 2)
                    }
                    Toggle(L("Encrypt file names", "Шифровать имена файлов"), isOn: $model.encryptNames)
                        .disabled(!model.format.supportsEncryptNames)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .disabled(!model.canEncrypt)
        }
    }

    // MARK: Вспомогательное

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).frame(width: labelWidth, alignment: .leading)
            content().labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func choicePicker(_ selection: Binding<String>, _ choices: [Choice]) -> some View {
        Picker("", selection: selection) {
            if choices.isEmpty { Text("—").tag("") }
            ForEach(choices) { Text($0.label).tag($0.value) }
        }
        .disabled(choices.count < 2)
    }

    private func browse() {
        let panel = NSSavePanel()
        let current = URL(fileURLWithPath: model.archivePath)
        panel.directoryURL = current.deletingLastPathComponent()
        panel.nameFieldStringValue = current.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.archivePath = url.path
        }
    }
}

final class AddDialogController: NSObject, NSWindowDelegate {
    private let model: AddModel
    private var window: NSWindow?
    private let onFinish: (AddDialogController, SZCommand?) -> Void

    init(files: [URL], onFinish: @escaping (AddDialogController, SZCommand?) -> Void) {
        self.model = AddModel(files: files)
        self.onFinish = onFinish
        super.init()
    }

    func show() {
        let view = AddView(model: model,
                           onOK: { [weak self] in self?.confirm() },
                           onCancel: { [weak self] in self?.finish(nil) })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = L("Add to Archive", "Добавить к архиву")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirm() {
        if let problem = model.validate() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = problem
            if let window = window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        model.rememberSettings()
        finish(SZCommands.add(files: model.files, options: model.options))
    }

    private func finish(_ command: SZCommand?) {
        // Сначала сообщаем наружу (там откроется окно прогресса), потом закрываем своё окно,
        // чтобы приложение не завершилось между окнами.
        onFinish(self, command)
        window?.delegate = nil
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(nil)
        return false
    }
}
