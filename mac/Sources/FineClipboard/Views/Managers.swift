import SwiftUI

struct SnippetsView: View {
    let store: Store
    @State private var items: [Snippet] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(items) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name).fontWeight(.medium)
                            Text(s.content).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("编辑") { edit(s) }
                        Button("删除") { store.deleteSnippet(s.id); reload() }
                    }
                }
            }
            Divider()
            HStack { Button("新建片段…") { add() }; Spacer() }.padding(8)
        }
        .frame(minWidth: 400, minHeight: 320)
        .onAppear(perform: reload)
    }

    private func reload() { items = store.snippets() }
    private func add() {
        guard let name = Prompt.text("新建片段", "名称"), !name.isEmpty else { return }
        guard let content = Prompt.text("片段内容", "", value: "", multiline: true) else { return }
        store.addSnippet(name: name, content: content); reload()
    }
    private func edit(_ s: Snippet) {
        guard let name = Prompt.text("编辑片段", "名称", value: s.name), !name.isEmpty else { return }
        guard let content = Prompt.text("片段内容", "", value: s.content, multiline: true) else { return }
        store.updateSnippet(s.id, name: name, content: content); reload()
    }
}

struct ListsView: View {
    let store: Store
    @State private var items: [ClipList] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(items) { l in
                    HStack {
                        Text(l.name)
                        Spacer()
                        Button("重命名") { rename(l) }
                        Button("删除") {
                            if Prompt.confirm("删除列表「\(l.name)」?", "列表里的条目会移出列表,但不会被删除。") {
                                store.deleteList(l.id); reload()
                            }
                        }
                    }
                }
            }
            Divider()
            HStack { Button("新建列表…") { add() }; Spacer() }.padding(8)
        }
        .frame(minWidth: 360, minHeight: 300)
        .onAppear(perform: reload)
    }

    private func reload() { items = store.lists() }
    private func add() {
        guard let name = Prompt.text("新建列表", "列表名称"), !name.isEmpty else { return }
        store.addList(name: name); reload()
    }
    private func rename(_ l: ClipList) {
        guard let name = Prompt.text("重命名列表", "列表名称", value: l.name), !name.isEmpty else { return }
        store.renameList(l.id, name: name); reload()
    }
}

struct PasswordsView: View {
    let vault: Vault
    @State private var items: [PasswordEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(items) { p in
                    HStack {
                        Image(systemName: "key.fill").foregroundColor(.secondary)
                        Text(p.name)
                        Spacer()
                        Button("显示") {
                            Prompt.info(p.name, vault.reveal(p.id) ?? "(无法解密)")
                        }
                        Button("编辑") { edit(p) }
                        Button("删除") {
                            if Prompt.confirm("删除密码「\(p.name)」?") { vault.deleteEntry(p.id); reload() }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("新建密码…") { add() }
                Spacer()
                Text("密码以 AES-256-GCM 加密保存").font(.caption).foregroundColor(.secondary)
            }.padding(8)
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear(perform: reload)
    }

    private func reload() { items = vault.entries() }
    private func add() {
        guard let (name, secret) = Prompt.nameAndSecret("新建密码"), !name.isEmpty, !secret.isEmpty else { return }
        vault.addEntry(name: name, secret: secret); reload()
    }
    private func edit(_ p: PasswordEntry) {
        let current = vault.reveal(p.id) ?? ""
        guard let (name, secret) = Prompt.nameAndSecret("编辑密码", name: p.name, secret: current),
              !name.isEmpty, !secret.isEmpty else { return }
        vault.updateEntry(p.id, name: name, secret: secret); reload()
    }
}
