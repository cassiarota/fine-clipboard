import AppKit

enum SelfTest {
    static func run() -> Int32 {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FineClipboard-selftest-\(UUID().uuidString)")
        setenv("FINECLIPBOARD_DATA_DIR", dir.path, 1)
        var failures = 0
        var lines: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            let passed = condition(); lines.append("\(passed ? "PASS" : "FAIL") \(name)"); if !passed { failures += 1 }
        }

        autoreleasepool {
            let store = Store()
            store.setSetting(Store.themeKey, "dark")
            check("settings round-trip", store.setting(Store.themeKey) == "dark")
            let textId = store.add(kind: .text, text: "self-test searchable text", data: nil, preview: "text", source: "SelfTest", html: "<b>rich</b>", rtf: "{\\rtf1 rich}")
            let fileId = store.add(kind: .files, text: "/tmp/one\n/tmp/two", data: nil, preview: "files", source: "SelfTest")
            let image = NSImage(size: NSSize(width: 80, height: 50)); image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 80, height: 50).fill(); image.unlockFocus()
            let png = image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()
            let imageId = store.add(kind: .image, text: nil, data: png, preview: "image", source: "SelfTest")
            check("text/image/file history", store.count() == 3 && Set(store.allItems().map(\.kind.rawValue)).count == 3)
            check("search and rich text", store.searchItems("searchable").contains { $0.id == textId && $0.hasRichText })
            check("kind filters", store.itemsByKind(.image).first?.id == imageId && store.itemsByKind(.files).first?.id == fileId)
            store.setPinned(textId, true); check("favorite", store.pinnedItems().first?.id == textId)
            let listId = store.addList(name: "Release test"); store.assignToList(fileId, listId: listId)
            check("custom list", store.itemsByList(listId).first?.id == fileId)
            store.renameList(listId, name: "Renamed test"); check("rename list", store.lists().contains { $0.id == listId && $0.name == "Renamed test" })
            store.addSnippet(name: "Greeting", content: "hello"); let snippet = store.snippets().first!
            store.updateSnippet(snippet.id, name: "Greeting 2", content: "hello again")
            check("snippet CRUD", store.snippets().first?.content == "hello again"); store.deleteSnippet(snippet.id); check("snippet delete", store.snippets().isEmpty)

            let vault = Vault(store); vault.setMasterPassword("self-test-master-one"); vault.addEntry(name: "API", secret: "secret-value")
            let password = vault.entries().first!; check("password encrypt/decrypt", vault.reveal(password.id) == "secret-value")
            vault.lock(); check("password lock/wrong", vault.reveal(password.id) == nil && !vault.unlock("wrong"))
            check("password unlock", vault.unlock("self-test-master-one") && vault.reveal(password.id) == "secret-value")
            check("password change", vault.changeMasterPassword(old: "self-test-master-one", new: "self-test-master-two"))

            let monitor = ClipboardMonitor(); var capture: Capture?; monitor.onCapture = { capture = $0 }; monitor.start()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("monitor self-test", forType: .string)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8)); check("clipboard text monitor", capture?.text == "monitor self-test")
            capture = nil; monitor.paused = true; NSPasteboard.general.clearContents(); NSPasteboard.general.setString("paused", forType: .string)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8)); check("pause recording", capture == nil); monitor.stop()

            let rich = store.allItems().first { $0.id == textId }!; Paste.writeItem(rich)
            check("rich/plain pasteboard write", NSPasteboard.general.string(forType: .string) == rich.text && NSPasteboard.general.string(forType: .html) != nil)
            Paste.writeItem(store.allItems().first { $0.id == imageId }!); check("image pasteboard write", ClipboardMonitor.readImagePNG(NSPasteboard.general) != nil)

            let preview = ScreenshotPreviewView(data: png); _ = preview.body
            check("screenshot editor construction", !png.isEmpty)
            store.clear(keepPinned: true); check("clear keeps favorites", store.count() == 1 && store.allItems().first?.id == textId)
            store.clear(keepPinned: false); check("clear all", store.count() == 0)
        }
        unsetenv("FINECLIPBOARD_DATA_DIR")
        try? FileManager.default.removeItem(at: dir)
        lines.append("SUMMARY failures=\(failures)")
        print(lines.joined(separator: "\n"))
        return failures == 0 ? 0 : 1
    }
}
