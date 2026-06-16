import Cocoa
import SwiftUI

/// Borderless panel that can still become key (so the search field accepts typing).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts the popup in a floating panel near the cursor and handles keyboard navigation.
final class PopupController: NSObject, NSWindowDelegate {
    let model: PopupModel
    private var panel: KeyablePanel?
    private var keyMonitor: Any?
    var sizeTag: () -> String? = { "medium" }

    private static let digitForKeyCode: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    init(model: PopupModel) { self.model = model }

    func show() {
        model.reload()
        let (w, h) = PopupSize.dimensions(sizeTag())
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionAtCursor(panel, w: w, h: h)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func reloadIfVisible() { if isVisible { model.reload() } }

    private func makePanel() -> KeyablePanel {
        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = true
        p.delegate = self

        let host = NSHostingView(rootView: PopupView(model: model))
        host.wantsLayer = true
        host.layer?.cornerRadius = 10
        host.layer?.masksToBounds = true
        p.contentView = host
        return p
    }

    private func positionAtCursor(_ panel: NSPanel, w: CGFloat, h: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: w, height: h)
        var x = mouse.x
        var y = mouse.y - h
        if x + w > vf.maxX { x = vf.maxX - w }
        if x < vf.minX { x = vf.minX }
        if y < vf.minY { y = vf.minY }
        if y + h > vf.maxY { y = vf.maxY - h }
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    // MARK: - keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Esc
            hide(); return true
        case 125: // Down
            model.move(1); return true
        case 126: // Up
            model.move(-1); return true
        case 36, 76: // Return / keypad Enter
            let plain = mods.contains(.command) || mods.contains(.shift)
            hide()
            model.activateSelected(plain: plain)
            return true
        default:
            // Number quick-paste only when not searching and with no modifiers.
            if model.search.isEmpty, mods.isEmpty, let n = PopupController.digitForKeyCode[event.keyCode] {
                if model.rows.contains(where: { $0.badge == n }) {
                    hide()
                    model.activateBadge(n)
                    return true
                }
            }
            return false
        }
    }

    // Clicking another app / losing key → close.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
