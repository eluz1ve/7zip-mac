import Cocoa
import FinderSync

/// Расширение Finder: добавляет подменю «7-Zip» в контекстное меню файлов и папок.
/// Само ничего не сжимает (оно в песочнице) — только передаёт выбранные файлы
/// приложению 7-Zip.app через ссылку sevenzip://.
@objc(SZFinderSync)
final class SZFinderSync: FIFinderSync {

    override init() {
        super.init()
        // Меню нужно везде, включая внешние диски.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let items = FIFinderSyncController.default().selectedItemURLs(),
              !items.isEmpty else { return nil }

        let submenu = NSMenu(title: "7-Zip")

        if items.allSatisfy(SZShared.isArchive) {
            submenu.addItem(item(L("Extract files…", "Распаковать…"), #selector(extractDialog(_:))))
            submenu.addItem(item(L("Extract Here", "Распаковать здесь"), #selector(extractHere(_:))))
            let folder = items.count == 1 ? SZShared.extractFolderName(for: items[0]) : "*"
            submenu.addItem(item(L("Extract to \"\(folder)/\"", "Распаковать в \"\(folder)/\""),
                                 #selector(extractTo(_:))))
            submenu.addItem(item(L("Test archive", "Тестировать"), #selector(testArchive(_:))))
            submenu.addItem(.separator())
        }

        let base = SZShared.archiveBaseName(for: items)
        submenu.addItem(item(L("Add to archive…", "Добавить к архиву…"), #selector(addDialog(_:))))
        submenu.addItem(item(L("Add to \"\(base).7z\"", "Добавить к \"\(base).7z\""), #selector(add7z(_:))))
        submenu.addItem(item(L("Add to \"\(base).zip\"", "Добавить к \"\(base).zip\""), #selector(addZip(_:))))

        // Клик по самому пункту «7-Zip» (не по подменю) — окно «Добавить к архиву».
        let root = NSMenuItem(title: "7-Zip", action: #selector(addDialog(_:)), keyEquivalent: "")
        root.target = self
        if let icon = Bundle.main.image(forResource: "menu") {
            icon.size = NSSize(width: 16, height: 16)
            root.image = icon
        }
        root.submenu = submenu

        let menu = NSMenu(title: "")
        menu.addItem(root)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc func addDialog(_ sender: AnyObject?) { send(.add) }
    @objc func add7z(_ sender: AnyObject?) { send(.add7z) }
    @objc func addZip(_ sender: AnyObject?) { send(.addZip) }
    @objc func extractDialog(_ sender: AnyObject?) { send(.extract) }
    @objc func extractHere(_ sender: AnyObject?) { send(.extractHere) }
    @objc func extractTo(_ sender: AnyObject?) { send(.extractTo) }
    @objc func testArchive(_ sender: AnyObject?) { send(.test) }

    private func send(_ action: SZAction) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty,
              let url = SZShared.makeURL(action: action, files: items) else { return }

        // …/7-Zip.app/Contents/PlugIns/X.appex → …/7-Zip.app
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error = error {
                NSLog("7-Zip Finder: open failed (%@), falling back to URL handler", error.localizedDescription)
                NSWorkspace.shared.open(url)
            }
        }
    }
}
