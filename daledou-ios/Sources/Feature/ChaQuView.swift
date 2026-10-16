import SwiftUI

/// 真源：`ChaQuScreen` — 武林查区设置 + 按等级扫名册。
struct ChaQuView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var roster = ChaQuStore.shared
    @State private var tip = ""
    @State private var busy = false
    @State private var tick = 0

    private let t = FeatureToggleStore.shared
    private let fid = "chaqu"

    private let wlbmOptions: [(String, String)] = [
        ("1", "50下"), ("2", "60下"), ("3", "70下"), ("4", "80下"),
        ("5", "90下"), ("6", "100下"), ("7", "110下"), ("8", "120下"),
        ("9", "六周年下"), ("10", "130下"), ("11", "140下"), ("12", "150下"),
        ("13", "160下"), ("14", "170下"), ("15", "180下"), ("16", "无限制下"),
    ]

    var body: some View {
        let _ = roster.revision
        let _ = tick
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("查区设置（建议定期点「按等级查区」更新名册）")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DlColors.ink)

                    toggleRow("（每日凌晨1点-5点）自动更新报名数据", key: "cb_start")

                    textField("最低等级", key: "min_dj")
                    textField("最高等级", key: "max_dj")
                    textField("输入战力(默认5000)", key: "zhanli")

                    Text("武林报名档位（手机/电脑武林读取）")
                        .font(.system(size: 13, weight: .semibold))
                    Text("当前：\(wlbmLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkSecondary)
                    textField("档位 type(1-16)", key: "wlbm_type")

                    HStack(spacing: 8) {
                        quickType("120下", "8")
                        quickType("无限制", "16")
                        quickType("六周年", "9")
                        quickType("180下", "15")
                    }

                    textField("电脑赛区码01-05", key: "wlbm_saiqu_pc")
                    textField("手机赛区码", key: "wlbm_saiqu_phone")

                    VStack(spacing: 8) {
                        actionButton("获取最新报名数据", busy: busy) {
                            await fetchSignup()
                        }
                        actionButton("按等级查区", busy: busy) {
                            await runChaQu()
                        }
                        actionButton("清空名册", busy: false, danger: true) {
                            roster.clear()
                            tip = "名册已清空"
                        }
                    }

                    Text("本地名册 \(roster.size()) 人")
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.accentBlue)

                    if !tip.isEmpty {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.inkMuted)
                    }

                    let sample = roster.sample(12)
                    if !sample.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("名册预览")
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(sample, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DlColors.inkSecondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DlColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(14)
            }
            .background(DlColors.canvas)
            .navigationTitle("查区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                if t.getString(fid, "zhanli").isEmpty {
                    t.setString(fid, "zhanli", "5000")
                }
                if t.getString(fid, "wlbm_type").isEmpty {
                    t.setString(fid, "wlbm_type", "16")
                }
            }
        }
    }

    private var wlbmLabel: String {
        let v = t.getString(fid, "wlbm_type", default: "16")
        return wlbmOptions.first(where: { $0.0 == v })?.1 ?? "自定义 type=\(v)"
    }

    private func toggleRow(_ label: String, key: String) -> some View {
        Button {
            t.setBool(fid, key, !t.getBool(fid, key))
            tick &+= 1
        } label: {
            HStack {
                Image(systemName: t.getBool(fid, key) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(t.getBool(fid, key) ? DlColors.accentBlue : DlColors.inkMuted)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(DlColors.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func textField(_ label: String, key: String) -> some View {
        TextField(label, text: Binding(
            get: { t.getString(fid, key) },
            set: {
                t.setString(fid, key, $0)
                tick &+= 1
            }
        ))
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(DlColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func quickType(_ label: String, _ value: String) -> some View {
        Button(label) {
            t.setString(fid, "wlbm_type", value)
            tick &+= 1
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(DlColors.accentBlue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DlColors.surface)
        .clipShape(Capsule())
    }

    private func actionButton(
        _ title: String, busy: Bool, danger: Bool = false, action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(danger ? Color.red.opacity(0.85) : (busy ? DlColors.inkMuted : DlColors.accentBlue))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(busy)
        .buttonStyle(.plain)
    }

    private func fetchSignup() async {
        busy = true
        defer { busy = false }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        let (_, body) = await LedouCGI.getPetPk(cmd: "signup", cookie: cookie)
        let msg = CombatLog.fromBody(body)
        tip = msg.isEmpty ? String(body.prefix(200)) : msg
        TaskLogStore.shared.append("查区", tip)
    }

    private func runChaQu() async {
        busy = true
        defer { busy = false }
        t.setBool(fid, "force_resume", false)
        tip = await ChaQuActions.farm(force: true) { line in
            Task { @MainActor in
                TaskLogStore.shared.append("查区", line)
            }
        }
    }
}
