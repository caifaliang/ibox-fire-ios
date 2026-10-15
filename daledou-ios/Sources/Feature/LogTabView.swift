import SwiftUI

/// 对齐 APK `HuoYueDaiWanScreen`（底栏「日志」）：运行状态 + 搜索 + 日志列表。
struct LogTabView: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var log = TaskLogStore.shared
    @ObservedObject private var runner = HuoYueRunner.shared
    @ObservedObject private var lingJiang = LingJiangRunner.shared
    @State private var query = ""

    private var shown: [TaskLogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return log.entries }
        return log.entries.filter {
            $0.tag.localizedCaseInsensitiveContains(q)
                || $0.message.localizedCaseInsensitiveContains(q)
                || $0.timeLabel.contains(q)
        }
    }

    private var hero: String {
        if let n = log.activeName, !n.isEmpty { return "正在跑 \(n)" }
        if log.running { return "正在跑 后台任务" }
        return "目前没有任务在跑"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("日志")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DlColors.ink)
                .padding(.top, 16)
            Text(hero)
                .font(.system(size: 13))
                .foregroundStyle(
                    (log.running || !(log.activeName ?? "").isEmpty)
                        ? DlColors.accentBlue : DlColors.inkMuted
                )
                .padding(.top, 4)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button {
                    if runner.running {
                        runner.stop()
                    } else {
                        runner.start(cookie: SessionStore.shared.cookieHeader)
                    }
                } label: {
                    Text(runner.running ? "停止活跃" : "一键活跃")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(runner.running ? Color.orange : DlColors.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    if lingJiang.running {
                        lingJiang.stop()
                    } else {
                        lingJiang.start(cookie: SessionStore.shared.cookieHeader)
                    }
                } label: {
                    Text(lingJiang.running ? "停止领奖" : "一键领奖")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(lingJiang.running ? Color.orange : DlColors.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    vm.showHuoYue = true
                } label: {
                    Text("活跃设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DlColors.accentBlue)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DlColors.accentBlue.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    vm.showLingJiang = true
                } label: {
                    Text("领奖设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DlColors.accentBlue)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DlColors.accentBlue.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                TextField("搜索记录…", text: $query)
                    .font(.system(size: 14))
                    .foregroundStyle(DlColors.ink)
                Button("清空") { log.clear() }
                    .font(.system(size: 13))
                    .foregroundStyle(DlColors.inkSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(DlColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DlColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if shown.isEmpty {
                        Text(log.entries.isEmpty ? "跑任务时日志会显示在这里" : "没有匹配的记录")
                            .font(.system(size: 13))
                            .foregroundStyle(DlColors.inkMuted)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(shown) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(e.tag)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DlColors.accentBlue)
                                    Spacer()
                                    Text(e.timeLabel)
                                        .font(.system(size: 11))
                                        .foregroundStyle(DlColors.inkMuted)
                                }
                                Text(e.message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(DlColors.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DlColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DlColors.border.opacity(0.8), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DlColors.canvas)
    }
}
