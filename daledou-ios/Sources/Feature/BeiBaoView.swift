import SwiftUI

/// 真源：`BeiBaoScreen` — 背包查询宫格。
struct BeiBaoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = FeatureToggleStore.shared.getString("beibao", "keyword")
    @State private var tabStorage = "0"
    @State private var items: [BeiBaoCatalog.Item] = []
    @State private var loading = false
    @State private var tip = ""
    @State private var usingId: String?

    private var filtered: [BeiBaoCatalog.Item] {
        let base = tabStorage == "0" ? items : items.filter { $0.storage == tabStorage }
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                tabRow
                content
            }
            .background(DlColors.canvas)
            .navigationTitle("背包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                keyword = FeatureToggleStore.shared.getString("beibao", "keyword")
            }
            .task { await reload() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("搜索物品", text: $keyword)
                .font(.system(size: 13))
                .onChange(of: keyword) { v in
                    FeatureToggleStore.shared.setString("beibao", "keyword", v)
                }
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(DlColors.inkSecondary)
            }
            .disabled(loading)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(DlColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DlColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(BeiBaoCatalog.tabs, id: \.1) { label, storage in
                    let selected = tabStorage == storage
                    Button {
                        tabStorage = storage
                    } label: {
                        Text(label)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : DlColors.inkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? DlColors.accentBlue : DlColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        if loading && items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            Text(loading ? "拉取中…" : (tip.isEmpty ? "没有匹配的物品" : tip))
                .font(.system(size: 14))
                .foregroundStyle(DlColors.inkMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 6)], spacing: 6) {
                    ForEach(filtered) { item in
                        itemCard(item)
                    }
                }
                .padding(8)
            }
        }
    }

    private func itemCard(_ item: BeiBaoCatalog.Item) -> some View {
        VStack(spacing: 4) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                default:
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DlColors.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("×\(item.num)")
                .font(.system(size: 11))
                .foregroundStyle(DlColors.accentBlue)

            if item.canuse == "1" {
                Button(usingId == item.id ? "…" : "使用") {
                    Task { await useItem(item) }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DlColors.accentBlue)
                .clipShape(Capsule())
                .disabled(usingId != nil)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(DlColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DlColors.border.opacity(0.7), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func reload() async {
        if loading { return }
        loading = true
        tip = ""
        defer { loading = false }
        let cookie = SessionStore.shared.cookieHeader
        guard LoginURLs.hasGameSession(cookie) else {
            tip = "请先登录"
            return
        }
        items = await BeiBaoCatalog.load(cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("背包", line) }
        }
        tip = items.isEmpty ? tip.ifEmpty("没有匹配的物品") : "共 \(items.count) 件"
    }

    private func useItem(_ item: BeiBaoCatalog.Item) async {
        usingId = item.id
        defer { usingId = nil }
        let cookie = SessionStore.shared.cookieHeader
        let (msg, delta) = await BeiBaoCatalog.use(item: item, cookie: cookie) { line in
            Task { @MainActor in TaskLogStore.shared.append("背包", line) }
        }
        tip = msg
        if let delta, let i = items.firstIndex(where: { $0.id == item.id }) {
            if delta <= 0 {
                items.remove(at: i)
            } else {
                items[i].num = delta
            }
        } else {
            await reload()
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
