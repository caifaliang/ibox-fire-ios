import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        Group {
            if !vm.siteLoggedIn { SiteLoginScreen() }
            else { MainShell() }
        }
    }
}

struct SiteLoginScreen: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        VStack(spacing: 16) {
            Text("iBox Fire").font(.largeTitle.bold())
            Text("网站会员登录").foregroundStyle(.secondary)
            TextField("用户名", text: $vm.siteUserName)
                .textInputAutocapitalization(.never)
                .fieldStyle()
            SecureField("密码", text: $vm.sitePassword).fieldStyle()
            if !vm.siteError.isEmpty { Text(vm.siteError).foregroundStyle(.red).font(.caption) }
            Button(vm.loginLoading ? "登录中…" : "登录") { Task { await vm.siteLogin() } }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .disabled(vm.loginLoading)
        }
        .padding(24)
        .dismissKeyboardOnTap()
    }
}

struct MainShell: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                platformBtn(.ibox, "iBox")
                platformBtn(.newbee, "NewBee")
                Spacer()
                Button { vm.techMode = .profile } label: {
                    Image(systemName: "person.circle").font(.title2)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)

            if vm.vipPreviewBanner {
                Text("非VIP预览模式：可浏览，开火需开通会员")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity).padding(6)
                    .background(Color.orange.opacity(0.12))
            }

            if !runner.runningKinds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(runner.runningKinds.sorted(), id: \.self) { k in
                            HStack(spacing: 4) {
                                Text(k).font(.caption2.bold())
                                Button("停") {
                                    if let kind = TaskKind(rawValue: k) { runner.stop(kind) }
                                }.font(.caption2).foregroundStyle(.red)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.15)).clipShape(Capsule())
                        }
                        Button("全部停止") { runner.stopAll() }
                            .font(.caption2.bold()).foregroundStyle(.red)
                    }.padding(.horizontal)
                }.padding(.vertical, 4)
            }

            if !vm.busyMsg.isEmpty {
                Text(vm.busyMsg)
                    .font(.caption.bold()).foregroundStyle(.blue)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Color.blue.opacity(0.08))
            }

            if vm.techMode != .profile {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.appPlatform == .ibox ? vm.iboxTabs : vm.nbTabs) { t in
                            Button(t.label) {
                                vm.techMode = t
                                vm.onTechModeChanged(t)
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(vm.techMode == t ? Color.primary : Color(.systemGray5))
                            .foregroundStyle(vm.techMode == t ? Color(.systemBackground) : .primary)
                            .clipShape(Capsule())
                        }
                    }.padding(.horizontal)
                }.padding(.bottom, 6)
            }

            Divider()

            Group {
                if vm.techMode == .profile { ProfileScreen() }
                else if vm.appPlatform == .newbee && !vm.nbLoggedIn { NbLoginScreen() }
                else { ModePane() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func platformBtn(_ p: AppPlatform, _ title: String) -> some View {
        Button(title) {
            vm.appPlatform = p
            vm.techMode = p == .ibox ? .announce : .nb_presale
        }
        .font(.headline)
        .foregroundStyle(vm.appPlatform == p ? .primary : .secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(vm.appPlatform == p ? Color.primary : .clear, lineWidth: 2))
    }
}

// MARK: - Shared chrome

private extension View {
    func fieldStyle() -> some View {
        self.padding(10).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

struct QuotaBanner: View {
    let q: QuotaInfo
    let label: String
    var body: some View {
        HStack {
            Text(label).font(.caption.bold())
            Spacer()
            Text(q.unlimited ? "不限次" : "剩 \(q.remaining)/\(q.limit)")
                .font(.caption)
                .foregroundStyle(q.unlimited || q.remaining > 0 ? .green : .red)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TimeFields: View {
    @Binding var h: Int
    @Binding var m: Int
    @Binding var s: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("开火时间（北京）").font(.caption.bold())
            HStack(spacing: 8) {
                stepper("时", $h, 0...23)
                stepper("分", $m, 0...59)
                stepper("秒", $s, 0...59)
            }
        }
    }
    private func stepper(_ title: String, _ v: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button("−") { v.wrappedValue = max(range.lowerBound, v.wrappedValue - 1) }
                Text(String(format: "%02d", v.wrappedValue)).font(.body.monospacedDigit()).frame(width: 28)
                Button("+") { v.wrappedValue = min(range.upperBound, v.wrappedValue + 1) }
            }
            .padding(6).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }
}

struct WorkerPicker: View {
    @Binding var workers: Int
    let onPick: (Int) -> Void
    var body: some View {
        Menu {
            ForEach(AppViewModel.workerOptions, id: \.self) { n in
                Button("\(n) 线程") { workers = n; onPick(n) }
            }
        } label: {
            HStack {
                Text("并发 \(workers) 线程").font(.subheadline)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .fieldStyle()
        }
    }
}

struct ModeChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption.bold())
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(selected ? Color.primary : Color(.systemGray5))
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct PickedBar: View {
    let title: String
    let subtitle: String
    let onClear: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("重选", action: onClear).font(.caption)
        }
        .padding(10).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StopStartButton: View {
    let running: Bool
    let startTitle: String
    let stopTitle: String
    let enabled: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    var body: some View {
        if running {
            Button(stopTitle, action: onStop)
                .buttonStyle(.borderedProminent).tint(.red).frame(maxWidth: .infinity)
        } else {
            Button(startTitle, action: onStart)
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                .disabled(!enabled)
        }
    }
}

struct CollSearchBox: View {
    @Binding var query: String
    let hits: [CollHit]
    let label: String
    let onPick: (CollHit) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(label, text: $query).fieldStyle()
            if hits.isEmpty {
                Text(query.count >= 2 ? "无匹配 · 换个关键词" : "输入藏品名称关键词")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(hits.prefix(12)) { h in
                    Button {
                        onPick(h)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name).font(.subheadline).foregroundStyle(.primary)
                            Text("GID \(h.id)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                    Divider()
                }
            }
        }
    }
}

struct ModeLogPanel: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { vm.logExpanded.toggle() }
            } label: {
                HStack {
                    Text("日志").font(.caption.bold())
                    Text("\(vm.currentLogs.count)").font(.caption2).foregroundStyle(.secondary)
                    if !runner.runningKinds.isEmpty {
                        Text("LIVE").font(.caption2.bold()).foregroundStyle(.red)
                    }
                    Spacer()
                    if vm.logExpanded {
                        Button("复制") {
                            UIPasteboard.general.string = vm.logsText()
                        }.font(.caption2)
                        Button("清空") { vm.clearLogs() }.font(.caption2).foregroundStyle(.red)
                    }
                    Image(systemName: vm.logExpanded ? "chevron.down" : "chevron.up").font(.caption)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if vm.logExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(vm.currentLogs) { l in
                            HStack(alignment: .top, spacing: 6) {
                                Text(l.time).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Text(l.msg).font(.caption)
                                    .foregroundStyle(l.type == "error" ? .red : (l.type == "buy" ? .green : .primary))
                            }
                        }
                    }.padding(.horizontal).padding(.bottom, 8)
                }
                .frame(maxHeight: 160)
            } else if let latest = vm.currentLogs.first {
                Text(latest.msg).font(.caption).lineLimit(1)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.bottom, 8)
                    .onTapGesture { withAnimation { vm.logExpanded = true } }
            } else {
                Text("暂无日志 · 点此展开").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.bottom, 8)
                    .onTapGesture { withAnimation { vm.logExpanded = true } }
            }
        }
        .background(Color(.systemGray6))
    }
}

// MARK: - Login / Profile

struct IboxLoginCard: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showToken = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("登录 iBox（开火账号）").font(.headline)
            TextField("手机号", text: $vm.iboxPhone).keyboardType(.phonePad).fieldStyle()
            TextField("验证码", text: $vm.iboxCode).keyboardType(.numberPad).fieldStyle()
            Button(vm.smsLoading ? "发送中…" : "获取验证码") { vm.sendSms() }
                .buttonStyle(.bordered).disabled(vm.smsLoading)
            if vm.smsSent { Text("验证码已发送").font(.caption).foregroundStyle(.green) }
            if !vm.iboxLoginError.isEmpty { Text(vm.iboxLoginError).font(.caption).foregroundStyle(.red) }
            Button(vm.loginLoading ? "登录中…" : "登录 iBox") { vm.loginSms() }
                .buttonStyle(.borderedProminent).disabled(vm.loginLoading)
            Button(showToken ? "收起 Token" : "Token 登录") { showToken.toggle() }.font(.caption)
            if showToken {
                TextEditor(text: $vm.iboxTokenInput).frame(minHeight: 80)
                    .padding(6).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button("验证 Token") { vm.loginToken() }.buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
    }
}

struct NbLoginScreen: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("NewBee 登录").font(.title2.bold())
                TextField("手机号", text: $vm.nbMobile).keyboardType(.phonePad).fieldStyle()
                SecureField("密码", text: $vm.nbPassword).fieldStyle()
                Button("OCR 登录") { Task { await vm.nbOcrLogin() } }.buttonStyle(.borderedProminent)
                Text("或粘贴 Token").font(.caption)
                TextEditor(text: $vm.nbTokenInput).frame(minHeight: 80)
                    .padding(8).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button("保存 Token") { vm.saveNbToken() }
                if !vm.nbError.isEmpty { Text(vm.nbError).foregroundStyle(.red).font(.caption) }
            }.padding()
        }
        .dismissKeyboardOnTap()
    }
}

struct ProfileScreen: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        List {
            Section("网站会员") {
                Text(vm.siteUser?.username ?? "-")
                Text(vipLabel)
                if let e = vm.siteUser?.vipExpiresAt, !e.isEmpty { Text("到期 \(e)").font(.caption) }
                Button("刷新额度") { Task { await vm.refreshAllQuotas(force: true) } }
                Button("退出网站", role: .destructive) { vm.siteLogout() }
            }
            Section("额度") {
                Text("抢合 \(vm.synthQuota.unlimited ? "不限" : "\(vm.synthQuota.remaining)/\(vm.synthQuota.limit)")")
                Text("抢购 \(vm.presaleQuota.unlimited ? "不限" : "\(vm.presaleQuota.remaining)/\(vm.presaleQuota.limit)")")
                Text("公告 \(vm.announceQuota.unlimited ? "不限" : "\(vm.announceQuota.remaining)/\(vm.announceQuota.limit)")")
            }
            Section("iBox") {
                Text(vm.iboxLoggedIn ? "已登录 uid=\(JwtUtil.uid(vm.iboxToken) ?? 0)" : "未登录")
                if vm.iboxLoggedIn {
                    Button("复制 Token") { UIPasteboard.general.string = vm.iboxToken }
                    Button("清除 iBox", role: .destructive) { vm.clearIbox() }
                }
            }
            Section("NewBee") {
                Text(vm.nbLoggedIn ? (vm.nbMobile.isEmpty ? "已登录" : vm.nbMobile) : "未登录")
                if vm.nbLoggedIn {
                    Button("复制 Token") { UIPasteboard.general.string = vm.nbToken }
                    Button("退出 NewBee", role: .destructive) { vm.clearNb() }
                }
            }
            Section("易代理 API") {
                Text("已内置默认提取链接；登录会员后会同步网页保存的链接")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("提取链接", text: $vm.proxyExtractUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)
                Button("保存代理链接") { vm.saveProxyExtractUrl() }
            }
            Section("说明") {
                Text("iOS 无前台服务：长任务请保持 App 在前台。杀后台即停。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var vipLabel: String {
        if vm.siteUser?.isAdmin == true { return "管理员" }
        if vm.isYearVip { return "年卡 VIP" }
        if vm.isMonthVip { return "月卡 VIP" }
        if vm.isVip { return "VIP" }
        return "免费用户"
    }
}

// MARK: - Mode panes

struct ModePane: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch vm.techMode {
                    case .announce: AnnouncePane()
                    case .synth: SynthPane()
                    case .presale: PresalePane()
                    case .buy: BuyPane()
                    case .sell: SellPane()
                    case .precision: PrecisionPane()
                    case .batch: BatchPane()
                    case .sweep: SweepPane()
                    case .query: QueryPane()
                    case .nb_presale: NbPresalePane()
                    case .nb_snipe: NbSnipePane()
                    default: EmptyView()
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            ModeLogPanel()
        }
        .dismissKeyboardOnTap()
    }
}

struct AnnouncePane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.isYearVip ? "年卡 · 公告锁不限次 · 本机直连" : (vm.isMonthVip ? "月卡 · 公告锁每日限次 · 本机直连" : "月卡/年卡可用 · 本机直连"))
                .font(.caption)
            Text("开放：北京时间 09:00–23:59").font(.caption2).foregroundStyle(.secondary)
            QuotaBanner(q: vm.announceQuota, label: "公告锁定")
            if !vm.announceQuota.openNow {
                Text("当前时段已关闭（\(vm.announceQuota.openHours)）").font(.caption).foregroundStyle(.orange)
            }
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else {
            HStack(spacing: 8) {
                ModeChip(title: "普通下单", selected: vm.announceOrderMode == "single") { vm.announceOrderMode = "single" }
                ModeChip(title: "批量下单", selected: vm.announceOrderMode == "batch") { vm.announceOrderMode = "batch" }
            }
            if vm.announceOrderMode == "batch" {
                HStack(spacing: 8) {
                    TextField("钱包余额 ¥", text: $vm.announceMaxPrice).keyboardType(.decimalPad).fieldStyle()
                    TextField("数量", text: $vm.announceMaxCount).keyboardType(.numberPad).fieldStyle()
                }
            }
            StopStartButton(
                running: runner.isRunning(.announce),
                startTitle: "开始公告锁定（本地）",
                stopTitle: "停止公告锁定",
                enabled: vm.canAnnounce && (vm.announceQuota.unlimited || vm.announceQuota.remaining > 0) && vm.announceQuota.openNow,
                onStart: { vm.startAnnounce() },
                onStop: { runner.stop(.announce) }
            )
            }
        }
    }
}

struct SynthPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    @State private var listExpanded = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuotaBanner(q: vm.synthQuota, label: "抢合")
            Text("本地开火 · 抢合/抢购已内置易代理").font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else {

            if let sel = vm.selectedActivity, !listExpanded {
                PickedBar(title: sel.name, subtitle: "#\(sel.id) · \(sel.startTime)", onClear: {
                    vm.clearSynthSelection(); listExpanded = true
                })
            } else {
                HStack {
                    TextField("搜索活动", text: $vm.activitySearch).fieldStyle()
                    Button { Task { await vm.refreshActivities(vm.activitySearch) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                Text("\(vm.activities.count) 条活动 · 选择后列表收起").font(.caption2).foregroundStyle(.secondary)
                ForEach(vm.activities) { a in
                    Button {
                        vm.selectActivity(a); listExpanded = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(a.name).font(.subheadline)
                            Text("#\(a.id) · \(a.startTime)").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                }
            }

            if vm.selectedActivity != nil {
                if !vm.busyMsg.isEmpty { Text(vm.busyMsg).font(.caption).foregroundStyle(.blue) }
                if !vm.channels.isEmpty {
                    Text("通道").font(.caption.bold())
                    ForEach(vm.channels) { ch in
                        Button {
                            vm.selectChannel(ch.id)
                        } label: {
                            HStack {
                                Text(ch.name.isEmpty ? "通道 \(ch.id)" : ch.name).font(.caption)
                                Spacer()
                                if vm.channelId == ch.id { Image(systemName: "checkmark.circle.fill") }
                            }
                            .padding(8)
                            .background(vm.channelId == ch.id ? Color.primary.opacity(0.12) : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !vm.materials.isEmpty {
                    Text("材料").font(.caption.bold())
                    ForEach(vm.materials, id: \.albumId) { m in
                        Toggle("\(m.name) (\(m.albumId))", isOn: Binding(
                            get: { vm.checkedAlbums.contains(m.albumId) },
                            set: { on in
                                if on { vm.checkedAlbums.insert(m.albumId) } else { vm.checkedAlbums.remove(m.albumId) }
                            }
                        )).font(.caption)
                    }
                }
                TimeFields(h: $vm.fireH, m: $vm.fireM, s: $vm.fireS)
                HStack {
                    TextField("数量", text: $vm.synthQty).keyboardType(.numberPad).fieldStyle()
                    WorkerPicker(workers: $vm.workers) { vm.setWorkers($0) }
                }
                StopStartButton(
                    running: runner.isRunning(.synth),
                    startTitle: "开始抢合（本地 · \(vm.synthQty)×\(vm.workers)线程）",
                    stopTitle: "停止抢合",
                    enabled: vm.synthQuota.unlimited || vm.synthQuota.remaining > 0,
                    onStart: { vm.startSynth() },
                    onStop: { runner.stop(.synth) }
                )
            }
            }
        }
        .onAppear { if vm.activities.isEmpty { Task { await vm.refreshActivities("") } } }
    }
}

struct PresalePane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuotaBanner(q: vm.presaleQuota, label: "抢购")
            Text("本地开火 · T-160预存极验 · sales下单\(vm.presaleAutoPay ? " · 自动支付" : "")").font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if let item = vm.presaleSelected {
                PickedBar(title: item.name, subtitle: "¥\(item.price) · #\(item.saleId)", onClear: { vm.clearPresaleSelection() })
                TimeFields(h: $vm.fireH, m: $vm.fireM, s: $vm.fireS)
                TextField("数量", text: $vm.presaleQty).keyboardType(.numberPad).fieldStyle()
                Toggle("自动支付（汇付钱包）", isOn: $vm.presaleAutoPay)
                if vm.presaleAutoPay { SecureField("支付密码", text: $vm.consignPwd).fieldStyle() }
                StopStartButton(
                    running: runner.isRunning(.presale),
                    startTitle: "开始抢购（本地）",
                    stopTitle: "停止抢购",
                    enabled: vm.presaleQuota.unlimited || vm.presaleQuota.remaining > 0,
                    onStart: { vm.startPresale() },
                    onStop: { runner.stop(.presale) }
                )
            } else {
                HStack {
                    Text("\(vm.presaleItems.count) 条发售").font(.caption)
                    Spacer()
                    Button { Task { await vm.refreshPresaleList() } } label: { Image(systemName: "arrow.clockwise") }
                }
                ForEach(vm.presaleItems) { p in
                    Button { vm.selectPresale(p) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).font(.subheadline)
                                Text("#\(p.saleId) · \(p.startTime)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "¥%.0f", p.price)).font(.caption.bold())
                        }
                    }
                    Divider()
                }
            }
        }
        .onAppear { if vm.presaleItems.isEmpty { Task { await vm.refreshPresaleList(silent: true) } } }
    }
}

struct BuyPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ModeChip(title: "云端", selected: vm.buyCloudMode) { vm.buyCloudMode = true }
                ModeChip(title: "本地", selected: !vm.buyCloudMode) { vm.buyCloudMode = false }
            }
            Text(vm.buyCloudMode
                 ? "☁️ 云端捡漏（服务器跑，可切后台/锁屏）"
                 : (vm.buyAutoPay ? "⚡ 本地开火 · 自动支付 · 需保持前台" : "⚡ 本地开火 · 需保持前台"))
                .font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if vm.buyGid <= 0 {
                CollSearchBox(query: Binding(get: { vm.collSearch }, set: { vm.searchColl($0) }), hits: vm.collHits, label: "搜索藏品", onPick: { vm.pickColl($0, target: "buy") })
            } else {
                PickedBar(title: vm.buyCname, subtitle: "GID \(vm.buyGid)", onClear: { vm.buyGid = 0; vm.buyCname = "" })
                TextField("目标价 ≤¥", text: $vm.buyPrice).keyboardType(.decimalPad).fieldStyle()
                TextField("数量", text: $vm.buyQty).keyboardType(.numberPad).fieldStyle()
                HStack {
                    ModeChip(title: "批量+普通", selected: vm.buyMode == "cross") { vm.buyMode = "cross" }
                    ModeChip(title: "普通", selected: vm.buyMode == "normal") { vm.buyMode = "normal" }
                    ModeChip(title: "纯批量", selected: vm.buyMode == "batch") { vm.buyMode = "batch" }
                }
                if vm.buyMode == "batch" {
                    HStack {
                        TextField("批购间隔", text: $vm.buyBatchInterval).keyboardType(.decimalPad).fieldStyle()
                        Text("秒（默认6）").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("自动支付（汇付钱包）", isOn: $vm.buyAutoPay)
                if vm.buyAutoPay { SecureField("支付密码", text: $vm.buyPayPwd).fieldStyle() }
                StopStartButton(
                    running: runner.isRunning(.buy),
                    startTitle: vm.buyCloudMode ? "开始捡漏（云端）" : "开始捡漏（本地）",
                    stopTitle: "停止捡漏",
                    enabled: vm.isVip,
                    onStart: { vm.startBuy() },
                    onStop: { runner.stop(.buy) }
                )
            }
        }
    }
}

struct SellPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本地开火 · 需寄售密码").font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if vm.sellGid <= 0 {
                CollSearchBox(query: Binding(get: { vm.collSearch }, set: { vm.searchColl($0) }), hits: vm.collHits, label: "搜索藏品", onPick: { vm.pickColl($0, target: "sell") })
            } else {
                PickedBar(title: vm.sellCname, subtitle: "GID \(vm.sellGid)", onClear: { vm.sellGid = 0; vm.sellCname = "" })
                TextField("最低接受价 ≥¥", text: $vm.sellPrice).keyboardType(.decimalPad).fieldStyle()
                TextField("数量", text: $vm.sellQty).keyboardType(.numberPad).fieldStyle()
                SecureField("寄售密码", text: $vm.consignPwd).fieldStyle()
                StopStartButton(running: runner.isRunning(.sell), startTitle: "开始卖求购（本地）", stopTitle: "停止卖求购", enabled: vm.isVip, onStart: { vm.startSell() }, onStop: { runner.stop(.sell) })
            }
        }
    }
}

struct PrecisionPane: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本地直连 · 搜藏品 → UUID/翻页选求购单 → 选持仓 → 精准卖出")
                .font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if vm.precisionGid <= 0 {
                CollSearchBox(
                    query: Binding(get: { vm.collSearch }, set: { vm.searchColl($0) }),
                    hits: vm.collHits,
                    label: "搜索藏品",
                    onPick: { vm.pickColl($0, target: "precision") }
                )
            } else {
                PickedBar(title: vm.precisionCname, subtitle: "GID \(vm.precisionGid)", onClear: { vm.clearPrecision() })
                HStack(spacing: 8) {
                    TextField("求购订单号 orderUuid", text: $vm.precisionUuid).fieldStyle()
                    Button(vm.precisionUuidLoading ? "…" : "匹配") {
                        vm.searchPrecisionUuid()
                    }
                    .disabled(vm.precisionUuidLoading || vm.precisionUuid.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let o = vm.precisionSelectedOrder {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("已匹配").font(.caption2).foregroundStyle(.green)
                            Text("¥\(o.price)").font(.headline)
                        }
                        Text(o.orderUuid.isEmpty ? "-" : o.orderUuid).font(.caption2).lineLimit(1)
                        Text("\(o.createdAt) · \(o.id)/\(o.orderRelationId)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Text("求购列表 第\(vm.precisionOrdersPage)页 · 共\(vm.precisionOrdersTotal)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("上一页") { vm.loadPrecisionOrders(page: vm.precisionOrdersPage - 1) }
                        .disabled(vm.precisionOrdersPage <= 1 || vm.precisionOrdersLoading)
                        .font(.caption)
                    Button("下一页") { vm.loadPrecisionOrders(page: vm.precisionOrdersPage + 1) }
                        .disabled(vm.precisionOrdersPage * 20 >= vm.precisionOrdersTotal || vm.precisionOrdersLoading)
                        .font(.caption)
                    Button(vm.precisionOrdersLoading ? "…" : "刷新") { vm.loadPrecisionOrders(page: vm.precisionOrdersPage) }
                        .disabled(vm.precisionOrdersLoading)
                        .font(.caption)
                }
                if vm.precisionOrders.isEmpty && !vm.precisionOrdersLoading {
                    Text("暂无求购单").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(vm.precisionOrders) { o in
                        let sel = vm.precisionSelectedOrder?.id == o.id
                        Button { vm.selectPrecisionOrder(o) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("¥\(o.price)").font(.subheadline.weight(.medium))
                                    Text(o.orderUuid.isEmpty ? "id=\(o.id)" : o.orderUuid)
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    Text(o.createdAt).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sel ? "已选" : "选择").font(.caption).foregroundStyle(.blue)
                            }
                        }
                        Divider()
                    }
                }
                if vm.precisionSelectedOrder != nil {
                    HStack {
                        Text("持仓").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(
                            vm.precisionHoldingsLoading ? "加载中…" :
                                (vm.precisionHoldings.isEmpty ? "加载持仓" : "\(vm.precisionHoldings.count)件")
                        ) { vm.loadPrecisionHoldings() }
                        .disabled(vm.precisionHoldingsLoading)
                        .font(.caption)
                    }
                    ForEach(vm.precisionHoldings) { h in
                        let sel = h.id == vm.precisionSelectedHoldingId
                        Button { vm.precisionSelectedHoldingId = h.id } label: {
                            Text("\(h.name.isEmpty ? "#\(h.tokenId)" : h.name) (#\(h.id))")
                                .font(.subheadline.weight(sel ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                    }
                    SecureField("寄售密码", text: $vm.consignPwd).fieldStyle()
                    if !vm.precisionResult.isEmpty {
                        let ok = vm.precisionResult.contains("成功") || vm.precisionResult.contains("已匹配")
                        let bad = vm.precisionResult.contains("失败") || vm.precisionResult.contains("错误") || vm.precisionResult.contains("未找到")
                        Text(vm.precisionResult)
                            .font(.caption)
                            .foregroundStyle(ok ? Color.green : (bad ? Color.red : Color.secondary))
                    }
                    Button {
                        vm.doPrecisionSell()
                    } label: {
                        Text(vm.precisionRunning ? "执行中…" : "精准卖出（本地）")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.precisionRunning || !vm.isVip || vm.precisionSelectedHoldingId <= 0)
                }
            }
        }
    }
}

struct BatchPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上架固定3.5s · 编号顺序").font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if vm.batchGid <= 0 {
                CollSearchBox(query: Binding(get: { vm.collSearch }, set: { vm.searchColl($0) }), hits: vm.collHits, label: "搜索藏品", onPick: { vm.pickColl($0, target: "batch") })
            } else {
                PickedBar(title: vm.batchCname, subtitle: "GID \(vm.batchGid)", onClear: { vm.batchGid = 0; vm.batchCname = "" })
                HStack {
                    ModeChip(title: "上架", selected: vm.batchAction == "list") { vm.batchAction = "list" }
                    ModeChip(title: "下架", selected: vm.batchAction == "unlist") { vm.batchAction = "unlist" }
                }
                if vm.batchAction == "list" {
                    TextField("上架价 ¥", text: $vm.batchPrice).keyboardType(.decimalPad).fieldStyle()
                    SecureField("寄售密码", text: $vm.consignPwd).fieldStyle()
                }
                TextField("数量(0=尽量全)", text: $vm.batchQty).keyboardType(.numberPad).fieldStyle()
                Toggle("安全模式 固定3.5s(编号顺序)", isOn: $vm.batchSafe)
                StopStartButton(
                    running: runner.isRunning(.batch),
                    startTitle: vm.batchAction == "unlist" ? "开始下架（本地）" : "开始上架（本地）",
                    stopTitle: "停止",
                    enabled: vm.isVip,
                    onStart: { vm.startBatch() },
                    onStop: { runner.stop(.batch) }
                )
            }
        }
    }
}

struct SweepPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    private var maxP: Double { Double(vm.sweepMaxPrice) ?? 0 }
    private var qtyN: Int { Int(vm.sweepQty) ?? 1 }
    private var canStart: Bool {
        vm.sweepSeller != nil && !vm.sweepSelected.isEmpty && maxP > 0 && qtyN >= 1
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本地开火 · 点选暗号挂单定位卖家").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(vm.sweepHelp ? "收起 ▲" : "怎么用？") { vm.sweepHelp.toggle() }.font(.caption)
            }
            if vm.sweepHelp {
                Text("1. 卖家在市场挂一个暗号藏品（可高价），并开放个人持仓\n2. 买家搜索暗号藏品 → 点选挂单 → 确认卖家昵称锁定\n3. 进入卖家仓库选分组；填最高接受价与数量后会自动勾选「有标价且≤最高价」的件\n4. 确认勾选后点「开始点对点」；只买已勾选件数")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if vm.sweepSeller == nil {
                if vm.sweepMarkerGid <= 0 {
                    CollSearchBox(
                        query: Binding(get: { vm.sweepMarkerSearch }, set: { vm.searchMarkerColl($0) }),
                        hits: vm.sweepMarkerHits,
                        label: "搜索暗号藏品",
                        onPick: { vm.pickColl($0, target: "sweepMarker") }
                    )
                } else {
                    PickedBar(title: vm.sweepMarkerCname, subtitle: "GID \(vm.sweepMarkerGid)") {
                        vm.clearSweepSeller()
                        vm.sweepMarkerGid = 0
                        vm.sweepMarkerCname = ""
                        vm.sweepMarkerOrders = []
                        vm.sweepMarkerSearch = ""
                    }
                    Text("市场挂单（价格降序，点选定位）").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(vm.sweepMarkerOrders.enumerated()), id: \.element.id) { idx, o in
                        Button { vm.pickMarkerOrder(o) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("¥\(fmtPrice(o.price))  #\(o.tokenId.isEmpty ? "-" : o.tokenId)").font(.subheadline)
                                    Text(o.sellerName.isEmpty ? "卖家待解析" : o.sellerName).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("选择").font(.caption).foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                        if idx == vm.sweepMarkerOrders.count - 1 {
                            Color.clear.frame(height: 1).onAppear { vm.loadMarkerOrders(reset: false) }
                        }
                    }
                    if vm.sweepMarkerLoading {
                        Text("加载中…").font(.caption).foregroundStyle(.secondary)
                    } else if vm.sweepMarkerOrders.isEmpty {
                        Text("暂无挂单").font(.caption).foregroundStyle(.secondary)
                    } else if !vm.sweepMarkerHasMore {
                        Text("没有更多").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Text("已锁定卖家：\(vm.sweepSeller?.name ?? "未知")").font(.subheadline.bold()).foregroundStyle(.green)
                    Spacer()
                    Button("重选卖家") { vm.reselectSweepSeller() }.font(.caption)
                }
                HStack {
                    TextField("最高接受价 ¥", text: Binding(get: { vm.sweepMaxPrice }, set: { vm.setSweepPriceQty(maxPrice: $0) }))
                        .keyboardType(.decimalPad).fieldStyle()
                    TextField("数量 N", text: Binding(get: { vm.sweepQty }, set: { vm.setSweepPriceQty(qty: $0) }))
                        .keyboardType(.numberPad).fieldStyle().frame(width: 88)
                }
                Text("已选 \(vm.sweepSelected.count) / \(qtyN)" + (vm.sweepAutoSelectMsg.isEmpty ? "" : "  \(vm.sweepAutoSelectMsg)"))
                    .font(.caption).foregroundStyle(.secondary)
                if !vm.sweepWhGroups.isEmpty {
                    ForEach(vm.sweepWhGroups) { g in
                        Button { vm.selectWhGroup(g) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name.isEmpty ? "GID \(g.groupId)" : g.name).font(.subheadline)
                                Text("GID \(g.groupId) · \(g.count) 件").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(vm.sweepGid == g.groupId ? Color.primary.opacity(0.12) : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                } else if vm.sweepWhLoading && vm.sweepGid <= 0 {
                    Text("加载仓库分组…").font(.caption).foregroundStyle(.secondary)
                }
                if !vm.sweepCname.isEmpty {
                    Text("\(vm.sweepCname)  GID \(vm.sweepGid)").font(.subheadline.bold())
                }
                if vm.sweepGid > 0 {
                    ForEach(Array(vm.sweepWhItems.enumerated()), id: \.element.id) { idx, it in
                        SweepWhRow(
                            item: it,
                            selected: vm.sweepSelected.contains { $0.digitalCollectionId == it.digitalCollectionId },
                            maxP: maxP,
                            canToggle: {
                                let selected = vm.sweepSelected.contains { $0.digitalCollectionId == it.digitalCollectionId }
                                let over = it.hasPrice && maxP > 0 && it.price > maxP
                                return selected || (!over && vm.sweepSelected.count < qtyN)
                            }(),
                            autoSelecting: vm.sweepAutoSelecting,
                            onToggle: { vm.toggleWhItem(it) }
                        )
                        if idx == vm.sweepWhItems.count - 1 {
                            Color.clear.frame(height: 1).onAppear { vm.loadWarehouseItems(reset: false) }
                        }
                    }
                    if vm.sweepWhLoading {
                        Text("加载中…").font(.caption).foregroundStyle(.secondary)
                    } else if vm.sweepWhItems.isEmpty {
                        Text("该分组暂无持仓").font(.caption).foregroundStyle(.secondary)
                    } else if !vm.sweepWhHasMore {
                        Text("没有更多").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("自动支付（汇付钱包）", isOn: $vm.sweepAutoPay)
                if vm.sweepAutoPay { SecureField("支付密码", text: $vm.sweepPayPwd).fieldStyle() }
                StopStartButton(
                    running: runner.isRunning(.sweep),
                    startTitle: "开始点对点（本地 · \(vm.sweepSelected.count)件）",
                    stopTitle: "停止",
                    enabled: vm.isVip && canStart,
                    onStart: { vm.startSweep() },
                    onStop: { runner.stop(.sweep) }
                )
            }
            if !vm.sweepHint.isEmpty {
                Text(vm.sweepHint).font(.caption).foregroundStyle(.red)
            }
        }
        .alert("确认卖家", isPresented: Binding(
            get: { vm.sweepSellerConfirm != nil },
            set: { if !$0 { vm.cancelSweepSellerConfirm() } }
        )) {
            Button("取消", role: .cancel) { vm.cancelSweepSellerConfirm() }
            Button("确认") { vm.confirmSweepSeller() }
        } message: {
            Text("定位到卖家：\(vm.sweepSellerConfirm?.name ?? "未知")，确认是 TA？")
        }
    }
    private func fmtPrice(_ p: Double) -> String {
        p.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", p) : String(format: "%.2f", p)
    }
}

private struct SweepWhRow: View {
    let item: SweepWhItem
    let selected: Bool
    let maxP: Double
    let canToggle: Bool
    let autoSelecting: Bool
    let onToggle: () -> Void
    private var over: Bool { item.hasPrice && maxP > 0 && item.price > maxP }
    var body: some View {
        Button {
            if canToggle && !autoSelecting { onToggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.primary : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(item.tokenId.isEmpty ? "-" : item.tokenId)" + (item.hasPrice ? "  ¥\(fmtPrice(item.price))" : ""))
                        .font(.subheadline)
                        .opacity(over && !selected ? 0.4 : 1)
                    if !item.hasPrice {
                        Text("无标价，按上限约束").font(.caption2).foregroundStyle(.orange)
                    } else if over {
                        Text("高于最高接受价").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(!canToggle || autoSelecting)
        Divider()
    }
    private func fmtPrice(_ p: Double) -> String {
        p.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", p) : String(format: "%.2f", p)
    }
}

struct QueryPane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("查求购数 / 挂单数 · 深度翻页 + 价格分布").font(.caption).foregroundStyle(.secondary)
            if !vm.iboxLoggedIn {
                IboxLoginCard()
            } else if vm.queryGid <= 0 {
                CollSearchBox(query: Binding(get: { vm.collSearch }, set: { vm.searchColl($0) }), hits: vm.collHits, label: "搜索藏品", onPick: { vm.pickColl($0, target: "query") })
            } else {
                PickedBar(title: vm.queryCname, subtitle: "GID \(vm.queryGid)", onClear: {
                    vm.queryGid = 0; vm.queryCname = ""
                    vm.queryTiers = []; vm.queryScanned = 0; vm.queryApiTotal = 0
                })
                HStack {
                    ModeChip(title: "查求购数", selected: vm.queryKind == "purchase") { vm.queryKind = "purchase" }
                    ModeChip(title: "查挂单数", selected: vm.queryKind == "consignment") { vm.queryKind = "consignment" }
                }
                Text("查询深度").font(.caption)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                    ForEach(AppViewModel.queryDepths, id: \.self) { d in
                        ModeChip(title: "\(d)", selected: vm.queryDepth == d) { vm.queryDepth = d }
                    }
                }
                if !vm.queryProgressMsg.isEmpty {
                    Text(vm.queryProgressMsg).font(.caption).foregroundStyle(.blue)
                }
                if vm.queryScanned > 0 || !vm.queryTiers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(vm.queryKind == "purchase" ? "求购" : "挂单") \(vm.queryScanned) 单" +
                             (vm.queryApiTotal > 0 ? " · 接口 total \(vm.queryApiTotal)" : "") +
                             " · \(vm.queryTiers.count) 价位")
                            .font(.subheadline.bold())
                        ForEach(vm.queryTiers.prefix(30)) { t in
                            Text(String(format: "¥%.2f × %d", t.price, t.count)).font(.caption.monospaced())
                        }
                    }
                    .padding(10).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                StopStartButton(running: runner.isRunning(.query), startTitle: "开始查询（本地）", stopTitle: "停止查询", enabled: vm.isVip, onStart: { vm.startQuery() }, onStop: { runner.stop(.query) })
            }
        }
    }
}

struct NbPresalePane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("高峰1分钟高并发 → 单线程300ms拖尾 → 代理耗尽补抽 → 最长20min\(vm.nbPresaleAutoPay ? " · 自动支付" : "")").font(.caption).foregroundStyle(.secondary)
            if let item = vm.nbPresaleSelected {
                PickedBar(title: item.name, subtitle: "¥\(item.price) · pid \(item.pid)", onClear: { vm.clearNbPresaleSelection() })
                TimeFields(h: $vm.fireH, m: $vm.fireM, s: $vm.fireS)
                HStack {
                    TextField("数量", text: $vm.nbPresaleQty).keyboardType(.numberPad).fieldStyle()
                    WorkerPicker(workers: $vm.workers) { vm.setWorkers($0) }
                }
                if let lim = item.limit, lim > 0 {
                    Text("限购 \(lim) · 高峰\(vm.workers)线程").font(.caption2).foregroundStyle(.secondary)
                }
                Toggle("自动支付（汇付）", isOn: $vm.nbPresaleAutoPay)
                if vm.nbPresaleAutoPay { SecureField("支付密码", text: $vm.nbPresalePayPwd).fieldStyle() }
                StopStartButton(
                    running: runner.isRunning(.nbPresale),
                    startTitle: "开始 NB 抢购（高峰\(vm.workers)线程）",
                    stopTitle: "停止 NB 抢购",
                    enabled: vm.isVip,
                    onStart: { vm.startNbPresale() },
                    onStop: { runner.stop(.nbPresale) }
                )
            } else {
                HStack {
                    Text("\(vm.nbPresaleItems.count) 条首发").font(.caption)
                    Spacer()
                    Button { Task { await vm.refreshNbPresaleList() } } label: { Image(systemName: "arrow.clockwise") }
                }
                ForEach(vm.nbPresaleItems) { p in
                    Button { vm.selectNbPresale(p) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).font(.subheadline)
                                Text("pid \(p.pid) · \(p.startTime)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "¥%.0f", p.price)).font(.caption.bold())
                        }
                    }
                    Divider()
                }
            }
        }
        .onAppear { if vm.nbPresaleItems.isEmpty { Task { await vm.refreshNbPresaleList(silent: true) } } }
    }
}

struct NbSnipePane: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本地开火 · 盯盘地板 → fast/batch/cross").font(.caption).foregroundStyle(.secondary)
            if vm.nbSnipePid <= 0 {
                TextField("搜索商品", text: Binding(get: { vm.nbSnipeSearch }, set: { vm.searchNbSnipe($0) })).fieldStyle()
                if vm.nbSnipeHits.isEmpty {
                    Text(vm.nbSnipeSearch.isEmpty ? "输入关键词搜索" : "无匹配").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(vm.nbSnipeHits) { h in
                        Button { vm.pickNbSnipe(h) } label: {
                            VStack(alignment: .leading) {
                                Text(h.name).font(.subheadline)
                                Text("PID \(h.id)" + (h.floor.isEmpty ? "" : " · 地板 \(h.floor)")).font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                    }
                }
            } else {
                PickedBar(title: vm.nbSnipeName, subtitle: "PID \(vm.nbSnipePid)", onClear: { vm.clearNbSnipeSelection() })
                HStack {
                    ModeChip(title: "快捷", selected: vm.nbSnipeMode == "fast") { vm.nbSnipeMode = "fast" }
                    ModeChip(title: "批量", selected: vm.nbSnipeMode == "batch") { vm.nbSnipeMode = "batch" }
                    ModeChip(title: "交叉", selected: vm.nbSnipeMode == "cross") { vm.nbSnipeMode = "cross" }
                }
                Text(nbModeTip).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    TextField("目标价 ≤¥", text: $vm.nbSnipePrice).keyboardType(.decimalPad).fieldStyle()
                    TextField("数量", text: $vm.nbSnipeQty).keyboardType(.numberPad).frame(width: 88).fieldStyle()
                }
                Toggle("自动支付（汇付）", isOn: $vm.nbSnipeAutoPay)
                if vm.nbSnipeAutoPay { SecureField("支付密码", text: $vm.nbSnipePayPwd).fieldStyle() }
                StopStartButton(running: runner.isRunning(.nbSnipe), startTitle: "开始捡漏（本地）", stopTitle: "停止 NB 捡漏", enabled: vm.isVip, onStart: { vm.startNbSnipe() }, onStop: { runner.stop(.nbSnipe) })
            }
        }
    }
    private var nbModeTip: String {
        switch vm.nbSnipeMode {
        case "fast": return "快捷：地板达标后 fastBuy，间隔 1s"
        case "batch": return "批量：batchBuy（汇付140），间隔 2s"
        default: return "交叉：批量→快捷→快捷→批量…，间隔 1s"
        }
    }
}
