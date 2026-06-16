import Cocoa
import ServiceManagement

enum AppInfo {
    static let name = "FineClipboard"
    /// Read from the bundle's Info.plist when packaged; falls back when run as a bare binary.
    static let version: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.10.0"
}

/// Launch-at-login via the modern Service Management API (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("FineClipboard login item error: \(error.localizedDescription)")
        }
    }
}

/// Light / dark / follow-system appearance for the whole app.
enum Appearance {
    static func apply(_ mode: String?) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil // follow system
        }
    }
}

enum PopupSize {
    static func dimensions(_ tag: String?) -> (width: CGFloat, height: CGFloat) {
        switch tag {
        case "small": return (340, 420)
        case "large": return (560, 680)
        default: return (440, 540) // medium
        }
    }
}
