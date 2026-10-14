import SwiftUI

/// 查区设置页（M9）：配置落盘；完整「按等级扫区」后台逻辑后续切片再接。
struct ChaQuView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var autoUpdate = UserDefaults.standard.bool(forKey: "daledou.chaqu.cb_start")
    @State private var minDj = UserDefaults.standard.string(forKey: "daledou.chaqu.min_dj") ?? ""
    @State private var maxDj = UserDefaults.standard.string(forKey: "daledou.chaqu.max_dj") ?? ""
    @State private var zhanli = UserDefaults.standard.string(forKey: "daledou.chaqu.zhanli") ?? "5000"
    @State private var wlbmType = UserDefaults.standard.string(forKey: "daledou.chaqu.wlbm_type") ?? "16"
    @State private var saiQuPc = UserDefaults.standard.string(forKey: "daledou.chaqu.wlbm_saiqu_pc") ?? ""
    @State private var saiQuPhone = UserDefaults.standard.string(forKey: "daledou.chaqu.wlbm_saiqu_phone") ?? ""
    @State private var tip = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("查区设置") {
                    Toggle("（每日凌晨1点-5点）自动更新报名数据", isOn: $autoUpdate)
                    TextField("最低等级", text: $minDj)
                        .keyboardType(.numberPad)
                    TextField("最高等级", text: $maxDj)
                        .keyboardType(.numberPad)
                    TextField("输入战力", text: $zhanli)
                        .keyboardType(.numberPad)
                }
                Section("武林报名档位") {
                    TextField("档位 type(1-16)", text: $wlbmType)
                        .keyboardType(.numberPad)
                    HStack {
                        chip("120下", "8")
                        chip("无限制", "16")
                        chip("六周年", "9")
                        chip("180下", "15")
                    }
                    TextField("电脑赛区码01-05", text: $saiQuPc)
                    TextField("手机赛区码", text: $saiQuPhone)
                }
                Section {
                    Button("保存设置") {
                        persist()
                        tip = "已保存"
                    }
                    Button("打开报名页（游戏壳）") {
                        persist()
                        if let u = URL(string: "\(LedouCGI.petpkBase)?cmd=signup") {
                            vm.openExternalGameURL(u)
                            dismiss()
                        }
                    }
                }
                Section {
                    Text("「按等级查区」名册扫描将在后续切片接入；当前可先保存报名档位供领奖使用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !tip.isEmpty {
                        Text(tip).font(.footnote)
                    }
                }
            }
            .navigationTitle("查区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        persist()
                        dismiss()
                    }
                }
            }
        }
    }

    private func chip(_ title: String, _ type: String) -> some View {
        Button(title) { wlbmType = type }
            .font(.caption)
            .buttonStyle(.bordered)
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(autoUpdate, forKey: "daledou.chaqu.cb_start")
        d.set(minDj, forKey: "daledou.chaqu.min_dj")
        d.set(maxDj, forKey: "daledou.chaqu.max_dj")
        d.set(zhanli, forKey: "daledou.chaqu.zhanli")
        d.set(wlbmType, forKey: "daledou.chaqu.wlbm_type")
        d.set(saiQuPc, forKey: "daledou.chaqu.wlbm_saiqu_pc")
        d.set(saiQuPhone, forKey: "daledou.chaqu.wlbm_saiqu_phone")
    }
}
