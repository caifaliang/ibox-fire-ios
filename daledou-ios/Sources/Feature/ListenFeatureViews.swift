import SwiftUI

/// 矿洞 / 劫镖 / 粮草监听页（对齐 MoreListenScreens / JieBiaoScreen）。
struct ListenHostView: View {
    let featureId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch featureId {
        case "kuangdong": KuangDongListenView(onClose: { dismiss() })
        case "jiebiao": JieBiaoListenView(onClose: { dismiss() })
        case "liangcao": LiangCaoListenView(onClose: { dismiss() })
        case "wending": WenDingListenView(onClose: { dismiss() })
        default:
            NavigationStack {
                Text("未知监听：\(featureId)")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
            }
        }
    }
}

// MARK: - 矿洞

struct KuangDongListenView: View {
    var onClose: () -> Void
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = "kuangdong"
    private let store = FeatureToggleStore.shared
    @State private var mode = "zhijie"
    @State private var kn = false
    @State private var bx = false
    @State private var dt = false
    @State private var wcGb = true
    @State private var hp = ""
    @State private var pos = ""
    @State private var tip = ""
    @State private var tick = 0

    private var listening: Bool { runner.isActive(fid) || store.isEnabled(fid) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !tip.isEmpty {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(DlColors.inkMuted)
                            .frame(maxWidth: .infinity)
                    }
                    Button("刷新矿洞") { refresh() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DlColors.accentBlue)
                        .frame(maxWidth: .infinity)

                    sectionTitle("打怪模式")
                    HStack {
                        radio("直接打", "zhijie")
                        radio("收残血", "canxie")
                    }
                    HStack {
                        radio("大于血量", "bighp")
                        radio("指定怪", "boss")
                    }
                    check("只打困难模式", kn) { kn = $0; persist() }
                    check("早上5点打完", bx) { bx = $0; persist() }
                    check("自动百炼钢打铁", dt) { dt = $0; persist() }
                    check("0次数时关闭监听", wcGb) { wcGb = $0; persist() }
                    HStack {
                        TextField("血量", text: $hp)
                            .font(.system(size: 13))
                            .keyboardType(.numberPad)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(DlColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                            .disabled(listening)
                        TextField("怪(1~15)", text: $pos)
                            .font(.system(size: 13))
                            .keyboardType(.numberPad)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(DlColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                            .disabled(listening)
                    }
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("矿洞")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                startButton
            }
            .onAppear { load(); _ = tick }
            .onChange(of: hp) { _ in persist() }
            .onChange(of: pos) { _ in persist() }
        }
    }

    private var startButton: some View {
        Button {
            if listening {
                runner.stop(fid)
            } else {
                persist()
                runner.start(fid)
            }
            tick &+= 1
        } label: {
            Text(listening ? "停止监听" : "开始监听")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(listening ? Color.orange : DlColors.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DlColors.canvas.opacity(0.96))
    }

    private func load() {
        mode = store.getString(fid, "mode", default: "zhijie")
        kn = store.getBool(fid, "kn")
        bx = store.getBool(fid, "bx")
        dt = store.getBool(fid, "dt")
        wcGb = store.getBool(fid, "wc_gb", default: true)
        hp = store.getString(fid, "hp")
        pos = store.getString(fid, "pos")
    }

    private func persist() {
        store.setString(fid, "mode", mode)
        store.setBool(fid, "kn", kn)
        store.setBool(fid, "bx", bx)
        store.setBool(fid, "dt", dt)
        store.setBool(fid, "wc_gb", wcGb)
        store.setString(fid, "hp", hp)
        store.setString(fid, "pos", pos)
    }

    private func refresh() {
        Task {
            let cookie = SessionStore.shared.cookieHeader
            let (_, body) = await LedouCGI.getPetPk(cmd: "factionmine", cookie: cookie)
            await MainActor.run {
                tip = CombatLog.fromBody(body)
                TaskLogStore.shared.append("矿洞", tip)
            }
        }
    }

    private func radio(_ title: String, _ value: String) -> some View {
        let on = mode == value
        return Button {
            guard !listening else { return }
            mode = value
            persist()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? DlColors.accentBlue : DlColors.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? DlColors.accentBlueSoft : DlColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }

    private func check(_ title: String, _ on: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            guard !listening else { return }
            set(!on)
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? DlColors.accentBlue : DlColors.inkMuted)
                Text(title).font(.system(size: 13)).foregroundStyle(DlColors.ink)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DlColors.ink)
    }
}

// MARK: - 劫镖

struct JieBiaoListenView: View {
    var onClose: () -> Void
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = "jiebiao"
    private let store = FeatureToggleStore.shared
    @State private var isSqy = true
    @State private var isWlg = false
    @State private var beiXuan = false
    @State private var wcGb = false
    @State private var byCondition = true
    @State private var dengji = ""
    @State private var zhanli = ""
    @State private var shenqi = ""
    @State private var jingyan = ""
    @State private var zdQq = ""
    @State private var tip = ""
    @State private var count = "剩余拦截次数：—"
    @State private var tick = 0

    private var listening: Bool { runner.isActive(fid) || store.isEnabled(fid) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(count).font(.system(size: 14, weight: .semibold))
                    if !tip.isEmpty {
                        Text(tip).font(.system(size: 12)).foregroundStyle(DlColors.inkMuted)
                    }
                    Button("刷新镖车列表") { refresh() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.16, blue: 0.16))
                        .frame(maxWidth: .infinity)

                    Text("设置").font(.system(size: 13, weight: .semibold))
                    HStack {
                        toggleChip("盛秋月", isSqy) {
                            guard !listening else { return }
                            isSqy = true; isWlg = false; persist()
                        }
                        toggleChip("温良恭", isWlg) {
                            guard !listening else { return }
                            isWlg = true; isSqy = false; persist()
                        }
                    }
                    check("凌晨5点后截温良恭", beiXuan) { beiXuan = $0; persist() }
                    check("次数用完关闭监听", wcGb) { wcGb = $0; persist() }
                    HStack {
                        toggleChip("按条件劫镖", byCondition) {
                            guard !listening else { return }
                            byCondition = true; persist()
                        }
                        toggleChip("指定QQ劫镖", !byCondition) {
                            guard !listening else { return }
                            byCondition = false; persist()
                        }
                    }
                    if byCondition {
                        numField("最高等级", $dengji)
                        numField("最高战力", $zhanli)
                        numField("最高神器", $shenqi)
                        numField("最低经验", $jingyan)
                    } else {
                        TextField("指定QQ（每行一个）", text: $zdQq, axis: .vertical)
                            .font(.system(size: 13))
                            .lineLimit(3...6)
                            .padding(8)
                            .background(DlColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                            .disabled(listening)
                    }
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("劫镖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                }
            }
            .safeAreaInset(edge: .bottom) { startButton }
            .onAppear { load() }
            .onChange(of: dengji) { _ in persist() }
            .onChange(of: zhanli) { _ in persist() }
            .onChange(of: shenqi) { _ in persist() }
            .onChange(of: jingyan) { _ in persist() }
            .onChange(of: zdQq) { _ in persist() }
        }
    }

    private var startButton: some View {
        Button {
            if listening {
                runner.stop(fid)
            } else {
                if !isSqy && !isWlg {
                    tip = "温良恭和盛秋月最少选一个"
                    return
                }
                persist()
                runner.start(fid)
            }
            tick &+= 1
        } label: {
            Text(listening ? "停止监听" : "开始监听")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(listening ? Color.orange : DlColors.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DlColors.canvas.opacity(0.96))
    }

    private func load() {
        isSqy = store.getBool(fid, "isSQY", default: true)
        isWlg = store.getBool(fid, "isWLG", default: false)
        beiXuan = store.getBool(fid, "isBeiXuan")
        wcGb = store.getBool(fid, "is_WC_GB")
        byCondition = store.getBool(fid, "is_TJ_ZD", default: true)
        dengji = store.getString(fid, "maxDengJi")
        zhanli = store.getString(fid, "maxZhanLi")
        shenqi = store.getString(fid, "maxShenqi")
        jingyan = store.getString(fid, "minJingYan")
        zdQq = store.getString(fid, "QQ")
    }

    private func persist() {
        store.setBool(fid, "isSQY", isSqy)
        store.setBool(fid, "isWLG", isWlg)
        store.setBool(fid, "isBeiXuan", beiXuan)
        store.setBool(fid, "is_WC_GB", wcGb)
        store.setBool(fid, "is_TJ_ZD", byCondition)
        store.setString(fid, "maxDengJi", dengji)
        store.setString(fid, "maxZhanLi", zhanli)
        store.setString(fid, "maxShenqi", shenqi)
        store.setString(fid, "minJingYan", jingyan)
        store.setString(fid, "QQ", zdQq)
    }

    private func refresh() {
        Task {
            let cookie = SessionStore.shared.cookieHeader
            _ = await LedouCGI.getPetPk(cmd: "cargo", extra: ["op": "3"], cookie: cookie)
            let (_, body) = await LedouCGI.getPetPk(cmd: "cargo", cookie: cookie)
            await MainActor.run {
                tip = String(CombatLog.fromBody(body).prefix(120))
                if let m = body.range(of: #"剩余[^\d]*(\d+)"#, options: .regularExpression) {
                    let s = String(body[m])
                    if let r = s.range(of: #"\d+$"#, options: .regularExpression) {
                        count = "剩余拦截次数：\(s[r])"
                    }
                }
                TaskLogStore.shared.append("劫镖", "刷新:\(tip)")
            }
        }
    }

    private func toggleChip(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color(red: 0.78, green: 0.16, blue: 0.16) : DlColors.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(DlColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }

    private func check(_ title: String, _ on: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            guard !listening else { return }
            set(!on)
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? DlColors.accentBlue : DlColors.inkMuted)
                Text(title).font(.system(size: 13)).foregroundStyle(DlColors.ink)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }

    private func numField(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13))
            .keyboardType(.numberPad)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(DlColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
            .disabled(listening)
    }
}

// MARK: - 粮草

struct LiangCaoListenView: View {
    var onClose: () -> Void
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = "liangcao"
    private let store = FeatureToggleStore.shared
    @State private var attack = true
    @State private var wcGb = false
    @State private var notZb = false
    @State private var tip = ""
    @State private var tick = 0

    private var listening: Bool { runner.isActive(fid) || store.isEnabled(fid) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !tip.isEmpty {
                        Text(tip).font(.system(size: 12)).foregroundStyle(DlColors.inkMuted)
                    }
                    Button("刷新状态") { refresh() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DlColors.accentBlue)
                        .frame(maxWidth: .infinity)
                    Text("设置").font(.system(size: 13, weight: .semibold))
                    check("自动攻击", attack) { attack = $0; persist() }
                    check("无次数/无目标时关闭", wcGb) { wcGb = $0; persist() }
                    check("不打已战败过的", notZb) { notZb = $0; persist() }
                    Text("开放：周二/周六 6 点后，或周三凌晨前")
                        .font(.system(size: 11))
                        .foregroundStyle(DlColors.inkMuted)
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("粮草掠夺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if listening {
                        runner.stop(fid)
                    } else {
                        persist()
                        runner.start(fid)
                    }
                    tick &+= 1
                } label: {
                    Text(listening ? "停止监听" : "开始监听")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(listening ? Color.orange : DlColors.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DlColors.canvas.opacity(0.96))
            }
            .onAppear { load() }
        }
    }

    private func load() {
        attack = store.getBool(fid, "attack", default: true)
        wcGb = store.getBool(fid, "wc_gb")
        notZb = store.getBool(fid, "not_zb")
    }

    private func persist() {
        store.setBool(fid, "attack", attack)
        store.setBool(fid, "wc_gb", wcGb)
        store.setBool(fid, "not_zb", notZb)
    }

    private func refresh() {
        Task {
            let cookie = SessionStore.shared.cookieHeader
            let (_, body) = await LedouCGI.getPhonePk(
                cmd: "forage_war", extra: ["subtype": "3"], cookie: cookie
            )
            await MainActor.run {
                tip = CombatLog.fromBody(body)
                TaskLogStore.shared.append("粮草", tip)
            }
        }
    }

    private func check(_ title: String, _ on: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            guard !listening else { return }
            set(!on)
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? DlColors.accentBlue : DlColors.inkMuted)
                Text(title).font(.system(size: 13)).foregroundStyle(DlColors.ink)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }
}

// MARK: - 问鼎

struct WenDingListenView: View {
    var onClose: () -> Void
    @ObservedObject private var runner = BackgroundListenRunner.shared
    private let fid = "wending"
    private let store = FeatureToggleStore.shared
    @State private var occupy = true
    @State private var noCd = false
    @State private var draw = false
    @State private var qyDh = false
    @State private var qyNh = false
    @State private var qyXz = false
    @State private var qyBh = false
    @State private var s2j = false
    @State private var s3j = true
    @State private var zbNot = false
    @State private var tzNotify = false
    @State private var ziYuan = "200"
    @State private var zhanliMax = "500"
    @State private var tip = ""
    @State private var tick = 0

    private var listening: Bool { runner.isActive(fid) || store.isEnabled(fid) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !tip.isEmpty {
                        Text(tip).font(.system(size: 12)).foregroundStyle(DlColors.inkMuted)
                    }
                    Button("刷新状态") { refresh() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DlColors.accentBlue)
                        .frame(maxWidth: .infinity)

                    Text("设置").font(.system(size: 13, weight: .semibold))
                    check("自动占领", occupy) { occupy = $0; persist() }
                    check("无次数时跳过", noCd) { noCd = $0; persist() }
                    check("领取奖励/枯竭奖", draw) { draw = $0; persist() }
                    check("东海", qyDh) { qyDh = $0; persist() }
                    check("南荒", qyNh) { qyNh = $0; persist() }
                    check("西泽", qyXz) { qyXz = $0; persist() }
                    check("北寒", qyBh) { qyBh = $0; persist() }
                    check("占二级", s2j) { s2j = $0; persist() }
                    check("占三级", s3j) { s3j = $0; persist() }
                    check("跳过战败点", zbNot) { zbNot = $0; persist() }
                    check("无空地时提示", tzNotify) { tzNotify = $0; persist() }

                    TextField("最低资源", text: $ziYuan)
                        .font(.system(size: 13))
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(DlColors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                        .disabled(listening)
                    TextField("最高战力", text: $zhanliMax)
                        .font(.system(size: 13))
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(DlColors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
                        .disabled(listening)

                    Text("周一全天 / 周六 6 点后不做占领（领奖仍可）")
                        .font(.system(size: 11))
                        .foregroundStyle(DlColors.inkMuted)
                }
                .padding(16)
            }
            .background(DlColors.canvas)
            .navigationTitle("问鼎")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onClose() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if listening {
                        runner.stop(fid)
                    } else {
                        persist()
                        runner.start(fid)
                    }
                    tick &+= 1
                } label: {
                    Text(listening ? "停止监听" : "开始监听")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(listening ? Color.orange : DlColors.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DlColors.canvas.opacity(0.96))
            }
            .onAppear { load() }
            .onChange(of: ziYuan) { _ in persist() }
            .onChange(of: zhanliMax) { _ in persist() }
        }
    }

    private func load() {
        occupy = store.getBool(fid, "occupy", default: true)
        noCd = store.getBool(fid, "no_cd")
        draw = store.getBool(fid, "draw")
        qyDh = store.getBool(fid, "qy_dh")
        qyNh = store.getBool(fid, "qy_nh")
        qyXz = store.getBool(fid, "qy_xz")
        qyBh = store.getBool(fid, "qy_bh")
        s2j = store.getBool(fid, "s2j")
        s3j = store.getBool(fid, "s3j", default: true)
        zbNot = store.getBool(fid, "zb_not")
        tzNotify = store.getBool(fid, "tz_notify")
        ziYuan = store.getString(fid, "zi_yuan", default: "200")
        zhanliMax = store.getString(fid, "zhanli_max", default: "500")
    }

    private func persist() {
        store.setBool(fid, "occupy", occupy)
        store.setBool(fid, "no_cd", noCd)
        store.setBool(fid, "draw", draw)
        store.setBool(fid, "qy_dh", qyDh)
        store.setBool(fid, "qy_nh", qyNh)
        store.setBool(fid, "qy_xz", qyXz)
        store.setBool(fid, "qy_bh", qyBh)
        store.setBool(fid, "s2j", s2j)
        store.setBool(fid, "s3j", s3j)
        store.setBool(fid, "zb_not", zbNot)
        store.setBool(fid, "tz_notify", tzNotify)
        store.setString(fid, "zi_yuan", ziYuan)
        store.setString(fid, "zhanli_max", zhanliMax)
    }

    private func refresh() {
        Task {
            let cookie = SessionStore.shared.cookieHeader
            let (_, body) = await LedouCGI.getPetPk(cmd: "tbattle", cookie: cookie)
            await MainActor.run {
                tip = CombatLog.fromBody(body)
                TaskLogStore.shared.append("问鼎", tip)
            }
        }
    }

    private func check(_ title: String, _ on: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            guard !listening else { return }
            set(!on)
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? DlColors.accentBlue : DlColors.inkMuted)
                Text(title).font(.system(size: 13)).foregroundStyle(DlColors.ink)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(listening)
    }
}
