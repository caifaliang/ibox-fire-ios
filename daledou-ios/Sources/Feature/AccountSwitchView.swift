import SwiftUI

/// 真源：`AccountSwitchScreen` — 本机令牌保存 / 切换 / 粘贴登录。
struct AccountSwitchView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AccountStore.shared
    @ObservedObject private var session = SessionStore.shared

    @State private var name = ""
    @State private var paste = ""
    @State private var qqInput = ""
    @State private var tip = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("令牌只保存在本机。请勿发给他人。保存前请先一键/扫码登录成功。")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)

                    TextField("备注名（可选）", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        if let saved = store.saveCurrent(name: name) {
                            tip = "已保存 \(saved.name)"
                            name = ""
                        } else {
                            tip = "当前没有可保存的登录 Cookie"
                        }
                    } label: {
                        Text("保存当前账号")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DlColors.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Text("已保存 \(store.accounts.count) 个")
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkSecondary)

                    ForEach(store.accounts) { acc in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(acc.name)
                                .font(.system(size: 14, weight: .medium))
                            Text("QQ=\(acc.qq ?? "?")  cookie=\(String(acc.cookie.prefix(24)))…")
                                .font(.system(size: 11))
                                .foregroundStyle(DlColors.inkMuted)
                            HStack(spacing: 10) {
                                Button("切换") {
                                    tip = vm.switchToSavedAccount(acc)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("删除", role: .destructive) {
                                    store.delete(id: acc.id)
                                    tip = "已删除"
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Divider().padding(.vertical, 4)

                    Text("粘贴 Cookie 令牌登录")
                        .font(.system(size: 13, weight: .medium))
                    TextEditor(text: $paste)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        tip = vm.loginWithPastedToken(paste, name: name)
                        if tip.contains("已登录") {
                            paste = ""
                            name = ""
                        }
                    } label: {
                        Text("用令牌登录")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DlColors.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.vertical, 4)

                    Text("手动填写大乐斗 QQ（道聚城兑换用）")
                        .font(.system(size: 13, weight: .medium))
                    TextField("QQ 号码", text: $qqInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .onChange(of: qqInput) { v in
                            qqInput = v.filter(\.isNumber)
                        }

                    Button {
                        let q = qqInput.trimmingCharacters(in: .whitespaces)
                        guard q.count >= 5 else {
                            tip = "QQ 号码不合法"
                            return
                        }
                        session.setQq(q)
                        tip = "已记录 QQ=\(q)"
                    } label: {
                        Text("保存 QQ 号")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DlColors.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if !tip.isEmpty {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.inkSecondary)
                    }
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("账号切换 / 令牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                qqInput = session.qq
            }
        }
    }
}
