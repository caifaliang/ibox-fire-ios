import SwiftUI

struct ActivityMarketPane: View {
    @EnvironmentObject var vm: AppViewModel
    var onOpenDetail: (IboxMarketItem) -> Void = { _ in }

    @State private var segments: [IboxSegment] = []
    @State private var items: [IboxMarketItem] = []
    @State private var segId: Int = -1
    @State private var kw = ""
    @State private var pageNo = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadingMore = false
    @State private var err = ""
    @State private var searchTask: Task<Void, Never>?

    private let pageSize = 20
    private let cream = Color(red: 1, green: 0.988, blue: 0.969)
    private let creamLine = Color(red: 0.906, green: 0.878, blue: 0.831)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vm.iboxLoggedIn {
                Text("需登录 iBox 后拉取活动市场（本机请求）")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.warning)
                    .padding(12)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("全部", on: segId == -1) {
                            segId = -1
                            Task { await reload() }
                        }
                        ForEach(segments) { seg in
                            chip(seg.name, on: segId == Int(seg.id)) {
                                segId = Int(seg.id)
                                Task { await loadPage(1, append: false) }
                            }
                        }
                    }
                }
                TextField("输入藏品关键词", text: $kw)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: kw) { _ in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            await reload()
                        }
                    }
                HStack {
                    Text("藏品名称 | 发行流通").font(.system(size: 11)).foregroundStyle(Palette.textMuted)
                    Spacer()
                    Text("地板价 · 成交量").font(.system(size: 11)).foregroundStyle(Palette.textMuted)
                }
                if loading && items.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(0..<8, id: \.self) { _ in skeletonRow }
                        }
                    }
                } else if !err.isEmpty && items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(err).foregroundStyle(.red).font(.system(size: 13))
                        Button("重试") { Task { await reload() } }
                    }
                    .padding(12)
                } else if items.isEmpty {
                    Text("暂无行情").foregroundStyle(Palette.textMuted).font(.system(size: 13))
                } else {
                    List {
                        ForEach(items) { row in
                            Button {
                                onOpenDetail(row)
                            } label: {
                                marketRow(row)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(cream)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .onAppear {
                                if row.id == items.last?.id, hasMore, !loadingMore, !loading {
                                    Task { await loadPage(pageNo + 1, append: true) }
                                }
                            }
                        }
                        Section {
                            HStack {
                                Spacer()
                                if loadingMore {
                                    ProgressView().controlSize(.small)
                                } else if hasMore {
                                    Button("加载更多") {
                                        Task { await loadPage(pageNo + 1, append: true) }
                                    }
                                    .font(.system(size: 12))
                                } else {
                                    Text("已加载全部 · \(items.count) 条")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.textMuted)
                                }
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .task(id: vm.iboxToken) {
            if vm.iboxLoggedIn { await reload(resetSeg: true) }
            else { err = "请先登录 iBox"; items = [] }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10).fill(creamLine.opacity(0.7)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(creamLine.opacity(0.7)).frame(height: 12).frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4).fill(creamLine.opacity(0.5)).frame(width: 120, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 6).fill(creamLine.opacity(0.55)).frame(width: 40, height: 28)
        }
        .padding(10)
        .background(cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func marketRow(_ row: IboxMarketItem) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: iboxThumb(row.coverPicUrl, size: 88))) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                creamLine
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("发行\(fmtNum(row.issueNum)) · 流通\(fmtNum(row.circulationNum))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.floorPrice > 0 ? "¥\(fmtPrice(row.floorPrice))" : "—")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(row.tradeVolume)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color(red: 0.969, green: 0.957, blue: 0.933) : Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Palette.brand : cream)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reload(resetSeg: Bool = false) async {
        if resetSeg { segId = -1 }
        pageNo = 1
        hasMore = true
        await loadPage(1, append: false)
    }

    private func loadPage(_ page: Int, append: Bool) async {
        let token = vm.iboxToken
        guard !token.isEmpty else {
            err = "请先登录 iBox"
            items = []
            return
        }
        if append {
            guard hasMore, !loadingMore, !loading else { return }
            loadingMore = true
        } else {
            loading = true
            err = ""
        }
        defer {
            loading = false
            loadingMore = false
        }
        do {
            if segments.isEmpty {
                let segs = try await vm.api.fetchIboxSegments(iboxToken: token)
                segments = segs.filter {
                    $0.name.trimmingCharacters(in: .whitespaces) != "全部" && $0.id != -1 && $0.id != 0
                }
            }
            let pageData = try await vm.api.fetchIboxMarket(
                token: token,
                pageNo: page,
                pageSize: pageSize,
                segmentId: segId,
                name: kw.trimmingCharacters(in: .whitespaces),
                expandCollections: 2
            )
            let before = append ? items.count : 0
            if append {
                var seen = Set(items.map(\.id))
                let fresh = pageData.items.filter { seen.insert($0.id).inserted }
                items.append(contentsOf: fresh)
            } else {
                items = pageData.items
            }
            let added = items.count - before
            pageNo = page
            if pageData.items.isEmpty {
                hasMore = false
            } else if append && added == 0 {
                hasMore = false
            } else if pageData.hasMore {
                hasMore = true
            } else if pageData.items.count >= pageSize {
                hasMore = true
            } else if pageData.total > items.count {
                hasMore = true
            } else {
                hasMore = false
            }
        } catch {
            if !append {
                err = error.localizedDescription
                items = []
            }
        }
    }
}

private func fmtNum(_ n: Int64) -> String {
    if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10000.0) }
    return "\(n)"
}

private func fmtPrice(_ p: Double) -> String {
    p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))" : String(format: "%.2f", p)
}
