import SwiftUI

struct BeiBaoView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = UserDefaults.standard.string(forKey: "daledou.beibao.keyword") ?? ""
    @State private var tabStorage = "0"
    @State private var items: [BeiBaoItem] = []
    @State private var loading = false
    @State private var tip = ""

    private var filtered: [BeiBaoItem] {
        let base = tabStorage == "0" ? items : items.filter { $0.storage == tabStorage }
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { $0.name.contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("搜索道具名称", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: keyword) { v in
                        UserDefaults.standard.set(v, forKey: "daledou.beibao.keyword")
                    }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BeiBaoService.tabs, id: \.storage) { tab in
                            let selected = tabStorage == tab.storage
                            Button(tab.label) { tabStorage = tab.storage }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selected ? Color.accentColor : Color(.systemGray5))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if loading {
                    ProgressView("拉取背包…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if !item.id.isEmpty {
                                    Text("id=\(item.id)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("×\(item.num)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }

                if !tip.isEmpty {
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .navigationTitle("背包查询")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") { Task { await reload() } }
                        .disabled(loading)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("打开游戏背包页") {
                        if let u = URL(string: "\(LedouCGI.phonepkBase)?cmd=store&channel=0") {
                            vm.openExternalGameURL(u)
                            dismiss()
                        }
                    }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        tip = "拉取中…"
        let cookie = vm.session.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            items = []
            loading = false
            return
        }
        var last = ""
        let list = await BeiBaoService.loadCatalog(cookie: cookie) { last = $0 }
        items = list
        loading = false
        tip = list.isEmpty ? (last.isEmpty ? "无数据" : last) : "共 \(list.count) 件"
    }
}
