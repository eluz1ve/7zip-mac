import Cocoa
import Darwin
import FinderSync

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [NSObject] = []
    private let mainWindow = MainWindowController()
    private var handledRequest = false

    // MARK: Жизненный цикл

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        buildMenu()

        mainWindow.model.onAdd = { [weak self] in self?.chooseFilesToAdd() }
        mainWindow.model.onExtract = { [weak self] in self?.chooseArchiveToExtract() }
        mainWindow.model.onDrop = { [weak self] urls in self?.open(files: urls) }
        mainWindow.model.onUpdate = { [weak self] in self?.mainWindow.runUpdater() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerFinderExtensionIfNeeded()
        // Если приложение запущено ссылкой или файлом, запрос придёт сразу; иначе покажем главное окно.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if !self.handledRequest { self.mainWindow.show() }
        }
    }

    /// Готовый релиз ставят простым перетаскиванием в «Программы» — install.sh при этом
    /// не запускается. Поэтому регистрируем и включаем расширение Finder сами:
    /// один раз для каждой версии и только когда приложение уже лежит в «Программах»
    /// (а не запущено прямо из образа диска).
    private func registerFinderExtensionIfNeeded() {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/"),
              let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("7-Zip Finder.appex"),
              let extensionID = Bundle(url: appex)?.bundleIdentifier else { return }
        let key = "finderExtensionRegistered"
        let stamp = path + " " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
        guard UserDefaults.standard.string(forKey: key) != stamp else { return }

        DispatchQueue.global(qos: .utility).async {
            for arguments in [["-a", appex.path], ["-e", "use", "-i", extensionID]] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
            DispatchQueue.main.async {
                UserDefaults.standard.set(stamp, forKey: key)
                self.mainWindow.model.extensionEnabled = FIFinderSyncController.isExtensionEnabled
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow.show() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Входящие запросы

    /// Файлы, открытые через «Открыть в программе» или брошенные на значок в Dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        handledRequest = true
        open(files: files)
    }

    /// Ссылка sevenzip://действие?f=путь&f=путь — так расширение Finder передаёт выбранные файлы.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text),
              let request = SZShared.parse(url) else { return }
        handledRequest = true
        let trusted = Self.isFromOwnBundle(event)
        perform(request.action, files: request.files, trusted: trusted)
    }

    /// Ссылку может открыть кто угодно (сайт, другая программа). Без окна подтверждения
    /// выполняем только то, что пришло от нашего собственного расширения Finder.
    private static func isFromOwnBundle(_ event: NSAppleEventDescriptor) -> Bool {
        guard let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0 else {
            return false
        }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(cString: buffer)
        let own = Bundle.main.bundlePath + "/Contents/"
        NSLog("7-Zip: request from pid %d (%@)", pid, path)
        return path.hasPrefix(own)
    }

    private func open(files: [URL]) {
        if files.allSatisfy(SZShared.isArchive) {
            perform(.extract, files: files, trusted: true)
        } else {
            perform(.add, files: files, trusted: true)
        }
    }

    private func perform(_ action: SZAction, files: [URL], trusted: Bool) {
        let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { url -> URL in
                // Нужен корректный признак папки, чтобы правильно выбрать имя архива.
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return URL(fileURLWithPath: url.path, isDirectory: isDirectory.boolValue)
            }
        guard !existing.isEmpty else {
            alert(L("Files not found.", "Файлы не найдены."))
            maybeShowMainWindow()
            return
        }

        switch action {
        case .add:
            showAddDialog(existing)
        case .add7z, .addZip:
            guard trusted else { showAddDialog(existing); return }
            let format: ArchiveFormat = action == .add7z ? .sevenZ : .zip
            let directory = existing[0].deletingLastPathComponent()
            let archive = directory.appendingPathComponent(
                SZShared.archiveBaseName(for: existing) + "." + format.fileExtension)
            var options = AddOptions(archivePath: archive.path)
            options.format = format
            run([SZCommands.add(files: existing, options: options)])
        case .extract:
            showExtractDialog(existing.filter { !$0.hasDirectoryPath })
        case .extractHere, .extractTo:
            let archives = existing.filter { !$0.hasDirectoryPath }
            guard trusted else { showExtractDialog(archives); return }
            run(archives.map { archive in
                var destination = archive.deletingLastPathComponent()
                if action == .extractTo {
                    destination.appendPathComponent(SZShared.extractFolderName(for: archive), isDirectory: true)
                }
                return SZCommands.extract(archive: archive, destination: destination, overwrite: .rename)
            })
        case .test:
            run(existing.filter { !$0.hasDirectoryPath }.map(SZCommands.test))
        }
    }

    // MARK: Окна

    private func showAddDialog(_ files: [URL]) {
        let controller = AddDialogController(files: files) { [weak self] controller, command in
            guard let self = self else { return }
            if let command = command { self.run([command]) }
            self.release(controller)
        }
        controllers.append(controller)
        controller.show()
    }

    private func showExtractDialog(_ archives: [URL]) {
        guard !archives.isEmpty else { maybeShowMainWindow(); return }
        let controller = ExtractDialogController(archives: archives) { [weak self] controller, commands in
            guard let self = self else { return }
            if let commands = commands { self.run(commands) }
            self.release(controller)
        }
        controllers.append(controller)
        controller.show()
    }

    private func run(_ commands: [SZCommand]) {
        guard !commands.isEmpty else { maybeShowMainWindow(); return }
        let controller = JobController(commands: commands) { [weak self] controller in
            self?.release(controller)
        }
        controllers.append(controller)
        controller.start()
    }

    private func release(_ controller: NSObject) {
        // Отложенно: контроллер ещё выполняет свой метод.
        DispatchQueue.main.async {
            self.controllers.removeAll { $0 === controller }
            self.maybeQuit()
        }
    }

    /// Если запрос ничего не показал и окон нет — не висеть в Dock без дела.
    private func maybeQuit() {
        if controllers.isEmpty, !NSApp.windows.contains(where: { $0.isVisible }) {
            NSApp.terminate(nil)
        }
    }

    private func maybeShowMainWindow() {
        if controllers.isEmpty, !NSApp.windows.contains(where: { $0.isVisible }) { mainWindow.show() }
    }

    private func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func chooseFilesToAdd() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("Add", "Добавить")
        if panel.runModal() == .OK, !panel.urls.isEmpty { perform(.add, files: panel.urls, trusted: true) }
    }

    private func chooseArchiveToExtract() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Extract", "Распаковать")
        if panel.runModal() == .OK, !panel.urls.isEmpty { perform(.extract, files: panel.urls, trusted: true) }
    }

    // MARK: Меню

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("About 7-Zip", "О программе 7-Zip"),
                        action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide 7-Zip", "Скрыть 7-Zip"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quit 7-Zip", "Завершить 7-Zip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("File", "Файл"))
        fileMenu.addItem(withTitle: L("Add to archive…", "Добавить к архиву…"),
                         action: #selector(menuAdd), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: L("Extract archive…", "Распаковать архив…"),
                         action: #selector(menuExtract), keyEquivalent: "o").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L("Close Window", "Закрыть окно"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Edit", "Правка"))
        editMenu.addItem(withTitle: L("Undo", "Отменить"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut", "Вырезать"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy", "Скопировать"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste", "Вставить"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All", "Выбрать все"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func menuAdd() { chooseFilesToAdd() }
    @objc private func menuExtract() { chooseArchiveToExtract() }

    @objc private func showAbout() {
        let version = SevenZip.versionString() ?? "—"
        let credits = NSAttributedString(
            string: L("Front end for the 7-Zip console program (7zz) \(version).\n7-Zip Copyright © Igor Pavlov, www.7-zip.org",
                      "Оболочка для консольного 7-Zip (7zz) \(version).\n7-Zip Copyright © Igor Pavlov, www.7-zip.org"),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}
