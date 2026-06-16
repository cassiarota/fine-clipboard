import SwiftUI
import AppKit

final class SettingsModel: ObservableObject {
    let host: AppControl
    @Published var popupLabel = ""
    @Published var plainLabel = ""
    @Published var recording: String?   // "popup" / "plain" while capturing
    private var monitor: Any?

    init(host: AppControl) { self.host = host; loadLabels() }

    func loadLabels() {
        popupLabel = HotkeyCombo.parse(host.store.setting(Store.hotkeyPopupKey), default: .defaultPopup).display()
        plainLabel = HotkeyCombo.parse(host.store.setting(Store.hotkeyPlainKey), default: .defaultPlain).display()
    }

    func startRecording(_ target: String) {
        stopMonitor()
        recording = target
        host.suspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captured(event); return nil
        }
    }

    private func captured(_ event: NSEvent) {
        if event.keyCode == 53 { cancel(); return }                  // Esc
        guard let combo = HotkeyCombo.from(event: event) else { return } // need a modifier; keep waiting
        let isPopup = recording == "popup"
        let ok = host.trySetHotkey(popup: isPopup, combo: combo)
        stopMonitor()
        recording = nil
        loadLabels()
        if !ok { Prompt.info("无法注册该快捷键", "可能已被其它程序占用,或与另一个快捷键冲突,请换一个。") }
    }

    func cancel() {
        stopMonitor()
        recording = nil
        host.resumeHotkeys()
        loadLabels()
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func label(for target: String) -> String {
        if recording == target { return "按下快捷键…" }
        return target == "popup" ? popupLabel : plainLabel
    }
}

struct SettingsView: View {
    let host: AppControl
    let onManageSnippets: () -> Void
    let onManageLists: () -> Void
    let onManagePasswords: () -> Void
    let onMasterPassword: () -> Void
    let masterTitle: () -> String
    @StateObject var model: SettingsModel

    @State private var startup = false
    @State private var sound = false
    @State private var maxItems = "1000"
    @State private var expiry = "0"
    @State private var theme = "system"
    @State private var popupSize = "medium"
    @State private var exclusions = ""
    @State private var count = 0

    private var store: Store { host.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("FineClipboard").font(.title2).bold()
                Text("版本 \(AppInfo.version)").font(.caption).foregroundColor(.secondary)

                Toggle("开机自启动", isOn: $startup)
                    .onChange(of: startup) { LoginItem.setEnabled($0) }
                Toggle("复制时播放提示音", isOn: $sound)
                    .onChange(of: sound) { store.setSetting(Store.soundEnabledKey, $0 ? "1" : "0") }

                Text("已保存 \(count) 条历史记录").font(.callout).foregroundColor(.secondary)
                HStack {
                    Button("清空历史(保留置顶)") {
                        if Prompt.confirm("确定清空历史吗?", "置顶项会保留。") { store.clear(keepPinned: true); count = store.count() }
                    }
                    Button("全部清空") {
                        if Prompt.confirm("确定清空全部历史吗?", "包括置顶项,不可恢复。") { store.clear(keepPinned: false); count = store.count() }
                    }
                }

                labeled("最多保留(非置顶记录)") {
                    Picker("", selection: $maxItems) {
                        Text("200 条").tag("200"); Text("500 条").tag("500")
                        Text("1000 条").tag("1000"); Text("5000 条").tag("5000")
                    }.labelsHidden().frame(width: 140)
                    .onChange(of: maxItems) { store.setSetting(Store.maxItemsKey, $0) }
                }

                HStack {
                    Button("管理常用片段…", action: onManageSnippets)
                    Button("管理列表…", action: onManageLists)
                }

                Divider()
                labeled("历史过期时间") {
                    Picker("", selection: $expiry) {
                        Text("永不过期").tag("0"); Text("1 天").tag("1"); Text("7 天").tag("7")
                        Text("30 天").tag("30"); Text("90 天").tag("90")
                    }.labelsHidden().frame(width: 140)
                    .onChange(of: expiry) {
                        store.setSetting(Store.expiryDaysKey, $0)
                        store.purgeExpired(days: Int($0) ?? 0); count = store.count()
                    }
                }

                Text("排除规则").font(.headline)
                Text("每行一个应用名(如 1Password、KeePassXC),来自这些程序的复制不会被记录。")
                    .font(.caption).foregroundColor(.secondary)
                TextEditor(text: $exclusions)
                    .font(.system(size: 12)).frame(height: 64)
                    .border(Color.secondary.opacity(0.3))
                    .onChange(of: exclusions) { store.setSetting(Store.exclusionsKey, $0) }

                Text("外观").font(.headline)
                HStack(spacing: 18) {
                    labeled("主题") {
                        Picker("", selection: $theme) {
                            Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                        }.labelsHidden().frame(width: 110)
                        .onChange(of: theme) { store.setSetting(Store.themeKey, $0); host.applyAppearance($0) }
                    }
                    labeled("弹窗大小") {
                        Picker("", selection: $popupSize) {
                            Text("小").tag("small"); Text("中").tag("medium"); Text("大").tag("large")
                        }.labelsHidden().frame(width: 90)
                        .onChange(of: popupSize) { store.setSetting(Store.popupSizeKey, $0) }
                    }
                }

                Divider()
                Text("密码保护").font(.headline)
                Text("设置主密码后,可在弹窗「密码」标签里加密保存密码;查看 / 粘贴需输入主密码。")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Button(masterTitle(), action: onMasterPassword)
                    Button("管理密码…", action: onManagePasswords)
                }

                Divider()
                Text("快捷键").font(.headline)
                Text("点击按钮后按下新的组合键(需含修饰键),Esc 取消。").font(.caption).foregroundColor(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("打开剪贴板历史")
                        Button(model.label(for: "popup")) { model.startRecording("popup") }.frame(width: 160)
                    }
                    GridRow {
                        Text("纯文本粘贴最近一条")
                        Button(model.label(for: "plain")) { model.startRecording("plain") }.frame(width: 160)
                    }
                }

                Text("提示:首次使用需在「系统设置 → 隐私与安全性 → 辅助功能」中允许 FineClipboard,才能自动粘贴。")
                    .font(.caption).foregroundColor(.secondary).padding(.top, 4)
            }
            .padding(20)
        }
        .frame(width: 440)
        .onAppear(perform: load)
    }

    private func load() {
        startup = LoginItem.isEnabled
        sound = store.setting(Store.soundEnabledKey) == "1"
        maxItems = store.setting(Store.maxItemsKey) ?? "1000"
        expiry = store.setting(Store.expiryDaysKey) ?? "0"
        theme = store.setting(Store.themeKey) ?? "system"
        popupSize = store.setting(Store.popupSizeKey) ?? "medium"
        exclusions = store.setting(Store.exclusionsKey) ?? ""
        count = store.count()
        model.loadLabels()
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout)
            content()
        }
    }
}
