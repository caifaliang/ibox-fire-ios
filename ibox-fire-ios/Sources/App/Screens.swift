import SwiftUI

struct RootView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        Group {
            if !vm.siteLoggedIn {
                SiteLoginScreen()
            } else {
                MainShell()
            }
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
                .padding().background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 12))
            SecureField("密码", text: $vm.sitePassword)
                .padding().background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 12))
            if !vm.siteError.isEmpty { Text(vm.siteError).foregroundStyle(.red).font(.caption) }
            Button("登录") { Task { await vm.siteLogin() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }
}

@MainActor
struct MainShell: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var runner = TaskRunner.shared

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
            .padding(.horizontal)
            .padding(.vertical, 8)

            if vm.vipPreviewBanner {
                Text("非VIP预览模式：可浏览，开火需开通会员")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity).padding(6).background(Color.orange.opacity(0.12))
            }

            if !runner.runningKinds.isEmpty {
                HStack {
                    Text("运行中: \(runner.runningKinds.sorted().joined(separator: ","))")
                        .font(.caption).foregroundStyle(.green)
                    Spacer()
                    Button("全部停止") { runner.stopAll() }.foregroundStyle(.red).font(.caption.bold())
                }
                .padding(.horizontal).padding(.vertical, 4).background(Color.green.opacity(0.08))
            }

            if vm.techMode != .profile {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let tabs = vm.appPlatform == .ibox ? vm.iboxTabs : vm.nbTabs
                        ForEach(tabs) { t in
                            Button(t.label) { vm.techMode = t }
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(vm.techMode == t ? Color.primary : Color(.systemGray5))
                                .foregroundStyle(vm.techMode == t ? Color(.systemBackground) : .primary)
                                .clipShape(Capsule())
                        }
                    }.padding(.horizontal)
                }
                .padding(.bottom, 6)
            }

            Divider()

            Group {
                if vm.techMode == .profile {
                    ProfileScreen()
                } else if vm.appPlatform == .ibox && !vm.iboxLoggedIn {
                    IboxLoginScreen()
                } else if vm.appPlatform == .newbee && !vm.nbLoggedIn && vm.techMode != .profile {
                    NbLoginScreen()
                } else {
                    ModePane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func platformBtn(_ p: AppPlatform, _ title: String) -> some View {
        Button(title) {
            vm.appPlatform = p
            vm.techMode = p == .ibox ? .buy : .nb_snipe
        }
        .font(.headline)
        .foregroundStyle(vm.appPlatform == p ? .primary : .secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(vm.appPlatform == p ? Color.primary : .clear, lineWidth: 2))
    }
}

struct IboxLoginScreen: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var phone = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("iBox 登录").font(.title2.bold())
                Text("粘贴 JWT（推荐）").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $vm.iboxToken).frame(minHeight: 100)
                    .padding(8).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                if !vm.iboxLoginError.isEmpty { Text(vm.iboxLoginError).foregroundStyle(.red).font(.caption) }
                Button("保存 Token") { vm.saveIboxToken() }.buttonStyle(.borderedProminent)
                Divider()
                Text("短信登录（服务端极验）").font(.caption)
                TextField("手机号", text: $phone).keyboardType(.phonePad)
                    .padding().background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button("发送验证码") { Task { await vm.smsLogin(phone: phone) } }
            }.padding()
        }
    }
}

struct NbLoginScreen: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("NewBee 登录").font(.title2.bold())
                TextField("手机号", text: $vm.nbMobile).keyboardType(.phonePad)
                    .padding().background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                SecureField("密码", text: $vm.nbPassword)
                    .padding().background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button("OCR 登录") { Task { await vm.nbOcrLogin() } }.buttonStyle(.borderedProminent)
                Text("或粘贴 Token").font(.caption)
                TextEditor(text: $vm.nbToken).frame(minHeight: 80)
                    .padding(8).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button("保存 Token") { vm.saveNbToken() }
                if !vm.nbError.isEmpty { Text(vm.nbError).foregroundStyle(.red).font(.caption) }
            }.padding()
        }
    }
}

struct ProfileScreen: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        List {
            Section("网站") {
                Text(vm.siteUser?.username ?? "-")
                Text(vm.isVip ? "VIP" : "免费用户")
                if let e = vm.siteUser?.vipExpiresAt, !e.isEmpty { Text("到期 \(e)").font(.caption) }
                Button("退出网站", role: .destructive) { vm.siteLogout() }
            }
            Section("iBox") {
                Text(vm.iboxLoggedIn ? "已登录 uid=\(JwtUtil.uid(vm.iboxToken) ?? 0)" : "未登录")
                if vm.iboxLoggedIn { Button("清除 iBox", role: .destructive) { vm.clearIbox() } }
            }
            Section("NewBee") {
                Text(vm.nbLoggedIn ? "已登录" : "未登录")
            }
            Section("说明") {
                Text("iOS 无前台服务：长任务请保持 App 在前台。杀后台即停。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("未签名 IPA 由 GitHub Actions 产出，自行自签安装。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct ModePane: View {
    @EnvironmentObject var vm: AppViewModel
    @ObservedObject private var runner = TaskRunner.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    collectionPicker
                    modeFields
                    actionButtons
                }
                .padding()
            }
            LogPanel(logs: vm.logs)
                .frame(height: 220)
        }
    }

    @ViewBuilder private var collectionPicker: some View {
        if vm.appPlatform == .ibox && ![.announce, .presale, .synth].contains(vm.techMode) {
            HStack {
                TextField("搜藏品", text: $vm.searchQ)
                Button("搜") { Task { await vm.search() } }
            }
            if vm.selectedGid > 0 {
                Text("已选 GID \(vm.selectedGid) · \(vm.selectedName)").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(vm.searchHits.prefix(8)) { h in
                Button("\(h.name) (#\(h.id))") { vm.pick(h) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if vm.appPlatform == .newbee {
            TextField("PID / 藏品ID", text: $vm.nbPidText).keyboardType(.numberPad)
                .padding().background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var modeFields: some View {
        switch vm.techMode {
        case .buy, .sell, .nb_snipe:
            TextField("价格", text: $vm.priceText).keyboardType(.decimalPad)
            TextField("数量", text: $vm.qtyText).keyboardType(.numberPad)
            if vm.techMode == .buy {
                Picker("模式", selection: $vm.buyMode) {
                    Text("交叉").tag("cross"); Text("普通").tag("normal"); Text("纯批量").tag("batch")
                }.pickerStyle(.segmented)
                Toggle("自动支付", isOn: $vm.autoPay)
                if vm.autoPay { SecureField("支付密码", text: $vm.payPwd) }
            }
            if vm.techMode == .sell { SecureField("寄售密码", text: $vm.consignPwd) }
        case .batch:
            TextField("上架单价", text: $vm.priceText).keyboardType(.decimalPad)
            TextField("数量(0=全部)", text: $vm.qtyText).keyboardType(.numberPad)
            SecureField("寄售密码", text: $vm.consignPwd)
            Toggle("安全模式 固定3.5s", isOn: $vm.batchSafe)
        case .query:
            Picker("类型", selection: $vm.queryKind) {
                Text("挂单").tag("consignment"); Text("求购").tag("purchase")
            }.pickerStyle(.segmented)
            TextField("深度", text: $vm.queryDepth).keyboardType(.numberPad)
            if !vm.queryTiers.isEmpty {
                ForEach(vm.queryTiers.prefix(12)) { t in
                    Text(String(format: "¥%.2f × %d", t.price, t.count)).font(.caption.monospaced())
                }
            }
        case .synth:
            TextField("合成活动ID", text: $vm.synthIdText).keyboardType(.numberPad)
            TextField("数量", text: $vm.synthNumText).keyboardType(.numberPad)
            TextField("材料 albumIds 逗号分隔", text: $vm.albumIdsText)
            TextField("workers", text: $vm.workersText).keyboardType(.numberPad)
            timePickers
        case .presale, .nb_presale:
            if vm.techMode == .presale { TextField("saleId", text: $vm.saleIdText).keyboardType(.numberPad) }
            TextField("数量", text: $vm.qtyText).keyboardType(.numberPad)
            timePickers
            if vm.techMode == .presale {
                Toggle("自动支付", isOn: $vm.autoPay)
                if vm.autoPay { SecureField("支付密码", text: $vm.payPwd) }
            }
        case .announce:
            Text("订阅网站公告 feed，解析 GID 后锁定/购买。保持前台。")
                .font(.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var timePickers: some View {
        HStack {
            Text("开火(北京)")
            TextField("时", value: $vm.fireH, format: .number).frame(width: 40)
            TextField("分", value: $vm.fireM, format: .number).frame(width: 40)
            TextField("秒", value: $vm.fireS, format: .number).frame(width: 40)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        let running = !runner.runningKinds.isEmpty
        HStack {
            switch vm.techMode {
            case .buy:
                Button(running ? "停止" : "开始捡漏") { running ? runner.stopAll() : vm.startBuy() }
            case .sell:
                Button(running ? "停止" : "开始卖求购") { running ? runner.stopAll() : vm.startSell() }
            case .batch:
                Button("批量上架") { vm.startBatch(list: true) }
                Button("批量下架") { vm.startBatch(list: false) }
                if running { Button("停止") { runner.stop(.batch) } }
            case .query:
                Button(running ? "停止" : "开始查询") { running ? runner.stop(.query) : vm.startQuery() }
            case .announce:
                Button(running ? "停止" : "开始公告") { running ? runner.stop(.announce) : vm.startAnnounce() }
            case .synth:
                Button(running ? "停止" : "开始抢合") { running ? runner.stop(.synth) : vm.startSynth() }
            case .presale:
                Button(running ? "停止" : "开始抢购") { running ? runner.stop(.presale) : vm.startPresale() }
            case .nb_presale:
                Button(running ? "停止" : "NB抢购") { running ? runner.stop(.nbPresale) : vm.startNbPresale() }
            case .nb_snipe:
                Button(running ? "停止" : "NB捡漏") { running ? runner.stop(.nbSnipe) : vm.startNbSnipe() }
            default: EmptyView()
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

struct LogPanel: View {
    let logs: [LogLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("日志").font(.caption.bold()).padding(.horizontal).padding(.top, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { l in
                        HStack(alignment: .top, spacing: 6) {
                            Text(l.time).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Text(l.msg).font(.caption).foregroundStyle(l.type == "error" ? .red : (l.type == "buy" ? .green : .primary))
                        }
                    }
                }.padding(.horizontal).padding(.bottom)
            }
        }
        .background(Color(.systemGray6))
    }
}
