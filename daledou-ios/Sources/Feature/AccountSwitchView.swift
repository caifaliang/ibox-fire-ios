import SwiftUI

/// M8：账号切换 — 对齐 Android AccountSwitchScreen（本机令牌）
struct AccountSwitchView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AccountStore.shared

    @State private var remark = ""
    @State private var paste = ""
    @State private var banner = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("令牌只保存在本机，请勿发给他人。建议先一键/扫码登录成功再保存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("保存当前") {
                    TextField("备注名（可选）", text: $remark)
                    Button("保存当前账号") {
                        saveCurrent()
                    }
                    .fontWeight(.semibold)
                }

                Section("已保存 \(store.accounts.count) 个") {
                    if store.accounts.isEmpty {
                        Text("暂无保存账号")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.accounts) { acc in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(acc.name)
                                    .font(.body.weight(.medium))
                                Text("QQ=\(acc.qq ?? "?") · cookie=\(acc.cookie.prefix(28))…")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("切换") { switchTo(acc) }
                                        .buttonStyle(.borderedProminent)
                                    Button("删除", role: .destructive) {
                                        store.delete(id: acc.id)
                                        banner = "已删除 \(acc.name)"
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("粘贴 Cookie 令牌登录") {
                    TextField("粘贴含会话的 Cookie", text: $paste, axis: .vertical)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(4...8)
                    Button("用令牌登录并保存") {
                        loginWithPaste()
                    }
                }

                if !banner.isEmpty {
                    Section {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("账号切换")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { store.refresh() }
        }
    }

    private func saveCurrent() {
        guard let saved = store.saveCurrent(
            cookie: vm.session.cookieHeader,
            qq: vm.session.qq,
            name: remark
        ) else {
            banner = "当前没有可保存的登录会话，请先一键/扫码/Cookie 登录"
            return
        }
        remark = ""
        banner = "已保存 \(saved.name)"
    }

    private func switchTo(_ acc: SavedAccount) {
        guard LoginURLs.hasGameSession(acc.cookie) else {
            banner = "该账号 Cookie 无效，请删除后重新保存"
            return
        }
        vm.applySavedAccount(acc)
        banner = "已切换到 \(acc.name)"
        dismiss()
    }

    private func loginWithPaste() {
        let header = AppViewModel.normalizeCookieHeader(paste)
        guard LoginURLs.hasGameSession(header) else {
            banner = "令牌无效：需要 skey 或 openId+accessToken 会话"
            return
        }
        let qq = LoginURLs.extractQq(header)
        _ = store.saveCurrent(cookie: header, qq: qq, name: remark)
        remark = ""
        paste = ""
        vm.applyCookieHeader(header, status: "令牌已登录，进入游戏…")
        dismiss()
    }
}
