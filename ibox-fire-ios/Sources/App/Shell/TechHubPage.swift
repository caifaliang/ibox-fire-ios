import SwiftUI

struct TechHubPage: View {
    @Binding var platform: String
    var subtitle: String
    var recentMode: String?
    var onPlatformSelect: (String) -> Void
    var onFeatureSelect: (ShellTechTab) -> Void

    @State private var category: String = "tech"
    @State private var query: String = ""
    @State private var showList = false

    private var cats: [ShellFeatureCat] { FeatureCatalog.catsForPlatform(platform) }
    private var features: [ShellTechTab] {
        FeatureCatalog.filterFeatures(platform: platform, category: category, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("iBox科技")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Palette.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typo.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }
                PlatformSegment(platform: platform, onSelect: { key in
                    onPlatformSelect(key)
                    category = FeatureCatalog.defaultCategory(key)
                    query = ""
                })
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.textMuted)
                    TextField("搜功能", text: $query)
                        .font(Typo.caption)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Palette.surfaceMuted.opacity(0.7), in: Capsule(style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(cats) { c in
                            let sel = c.key == category && query.isEmpty
                            Button {
                                Haptics.tap()
                                category = c.key
                                query = ""
                                showList = true
                            } label: {
                                Text(c.label)
                                    .font(.system(size: 12, weight: sel ? .bold : .medium))
                                    .foregroundStyle(sel ? Palette.textPrimary : Palette.textMuted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(sel ? Palette.brandSubtle : Palette.surface.opacity(0.6))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(sel ? Color.clear : Palette.hairline, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showList = true
                        } label: {
                            Text("列表")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(
                    query.isEmpty
                        ? "\(cats.first(where: { $0.key == category })?.label ?? "") · \(features.count) 项"
                        : "搜索「\(query)」· \(features.count) 项"
                )
                .font(Typo.caption2)
                .foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            FeatureTileGrid(
                features: features,
                accentKey: recentMode,
                onSelect: onFeatureSelect
            )
            .padding(.horizontal, 20)
        }
        .onAppear {
            if !cats.contains(where: { $0.key == category }) {
                category = FeatureCatalog.defaultCategory(platform)
            }
        }
        .onChange(of: platform) { p in
            category = FeatureCatalog.defaultCategory(p)
        }
        .sheet(isPresented: $showList) {
            NavigationStack {
                List(features) { f in
                    Button {
                        showList = false
                        onFeatureSelect(f)
                    } label: {
                        HStack {
                            Text(f.label).foregroundStyle(Palette.textPrimary)
                            Spacer()
                            if f.isNew {
                                Text("NEW").font(.caption2.bold()).foregroundStyle(Palette.liveAmber)
                            }
                        }
                    }
                }
                .navigationTitle(cats.first(where: { $0.key == category })?.label ?? "功能")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showList = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
