import SwiftUI

/// 真源：`DaiWanRecordScreen` — 悬浮钮打开的「代玩-记录」片单。
struct DaiWanRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var named = DaiWanNamedRunner.shared
    @ObservedObject private var log = TaskLogStore.shared
    @ObservedObject private var huoyue = HuoYueRunner.shared
    @ObservedObject private var lingjiang = LingJiangRunner.shared

    @State private var openGroups: Set<String> = ["一键", "代玩", "任务", "报名"]
    @State private var showLog = false
    @State private var query = ""
    @State private var filterBusy = true
    @State private var toast = ""

    private var heroBusy: Bool {
        named.running || huoyue.running || lingjiang.running || log.running
    }

    private var heroTitle: String {
        if let n = named.activeName, !n.isEmpty { return "正在跑 \(n)" }
        if let n = log.activeName, !n.isEmpty { return "正在跑 \(n)" }
        if heroBusy { return "正在跑 后台任务" }
        return "目前没有任务在跑"
    }

    private var filteredLog: [TaskLogEntry] {
        log.entries.filter { e in
            let hitQ = query.isEmpty
                || e.raw.localizedCaseInsensitiveContains(query)
            let hitBusy = !filterBusy || (!e.message.contains("繁忙") && !e.message.contains("请稍后再试"))
            return hitQ && hitBusy
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                heroBar
                if showLog {
                    logPane
                } else {
                    railPane
                }
            }
            .background(DlColors.canvas)
            .navigationTitle(showLog ? "运行日志" : "代玩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if showLog { showLog = false } else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !showLog {
                        Button("全部设置") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                vm.openFeature(id: "more_settings")
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(DlColors.inkSecondary)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !toast.isEmpty {
                    Text(toast)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
    }

    private var heroBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(heroTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(heroBusy ? DlColors.accentBlue : DlColors.ink)
                Text("点下方磁贴立即跑；角标进设置")
                    .font(.system(size: 11))
                    .foregroundStyle(DlColors.inkMuted)
            }
            Spacer()
            Button(showLog ? "片单" : "日志") {
                showLog.toggle()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DlColors.accentBlue)
            if heroBusy {
                Button("停止") {
                    named.stop()
                    huoyue.stop()
                    lingjiang.stop()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DlColors.surface)
    }

    private var railPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(DaiWanRecordRails.groups) { group in
                    groupBlock(group)
                }
            }
            .padding(12)
            .padding(.bottom, 24)
        }
    }

    private func groupBlock(_ group: DaiWanRecordRails.Group) -> some View {
        let open = openGroups.contains(group.title)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if open { openGroups.remove(group.title) } else { openGroups.insert(group.title) }
            } label: {
                HStack {
                    Text(group.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DlColors.ink)
                    Spacer()
                    if let sid = group.settingId {
                        Text("设置")
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.accentBlue)
                            .onTapGesture { openSettings(sid) }
                    }
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(DlColors.inkMuted)
                }
            }
            .buttonStyle(.plain)

            if open {
                let wides = group.tiles.filter(\.wide)
                let normals = group.tiles.filter { !$0.wide }
                ForEach(wides) { tile in
                    wideTile(tile)
                }
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    ForEach(normals) { tile in
                        normalTile(tile)
                    }
                }
            }
        }
        .padding(10)
        .background(DlColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DlColors.border.opacity(0.8), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func wideTile(_ tile: DaiWanRecordRails.Tile) -> some View {
        Button { fire(tile) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DlColors.ink)
                    if let h = tile.hint {
                        Text(h)
                            .font(.system(size: 11))
                            .foregroundStyle(DlColors.inkMuted)
                    }
                }
                Spacer()
                if let corner = tile.cornerAction {
                    Text("设置")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DlColors.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DlColors.accentBlueSoft)
                        .clipShape(Capsule())
                        .onTapGesture { onWorkbench(corner) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DlColors.accentBlueSoft.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func normalTile(_ tile: DaiWanRecordRails.Tile) -> some View {
        Button { fire(tile) } label: {
            Text(tile.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DlColors.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 4)
                .background(DlColors.canvas)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var logPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索日志…", text: $query)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(DlColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                Toggle(isOn: $filterBusy) {
                    Text("滤繁忙").font(.system(size: 11))
                }
                .toggleStyle(.button)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if filteredLog.isEmpty {
                Text("跑任务时日志会显示在这里")
                    .font(.system(size: 13))
                    .foregroundStyle(DlColors.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLog) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(e.timeLabel)] [\(e.tag)]")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DlColors.accentBlue)
                        Text(e.message)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.ink)
                    }
                    .listRowBackground(DlColors.surface)
                }
                .listStyle(.plain)
            }
        }
    }

    private func fire(_ tile: DaiWanRecordRails.Tile) {
        if let fid = DaiWanRecordRails.openFeatureId(for: tile.action) {
            flash("打开：\(tile.title)")
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                vm.openFeature(id: fid)
            }
            return
        }
        named.run(tile.action)
        flash("已开始：\(tile.title)")
    }

    private func onWorkbench(_ action: String) {
        if let sid = DaiWanRecordRails.settingsFeatureId(for: action) {
            openSettings(sid)
            return
        }
        named.run(action)
        flash("已开始：\(action)")
    }

    private func openSettings(_ id: String) {
        flash("打开设置")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            vm.openFeature(id: id)
        }
    }

    private func flash(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if toast == s { toast = "" }
        }
    }
}
