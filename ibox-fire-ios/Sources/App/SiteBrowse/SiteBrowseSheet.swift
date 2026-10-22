import SwiftUI

/// 仿 App 全屏浏览线上站 ai.iboxai.top
struct SiteBrowseSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0
    @State private var pageTitle = "iBox 站"
    @State private var loading = true
    @State private var canGoBack = false

    private var siteURL: URL {
        URL(string: "https://ai.iboxai.top/")!
    }

    private var userCacheJSON: String {
        guard let u = vm.siteUser else { return "null" }
        let obj: [String: Any] = [
            "token": u.token,
            "username": u.username,
            "is_vip": u.isVip,
            "is_admin": u.isAdmin,
            "is_year_vip": u.isYearVip,
            "is_month_vip": u.isMonthVip,
            "vip_expires_at": u.vipExpiresAt,
        ]
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SiteWebView(
                    url: siteURL,
                    siteToken: vm.siteUser?.token ?? "",
                    userCacheJSON: userCacheJSON,
                    iboxToken: vm.iboxToken,
                    reloadToken: $reloadToken,
                    onTitle: { pageTitle = $0.isEmpty ? "iBox 站" : $0 },
                    onLoading: { loading = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                if loading {
                    ProgressView()
                        .padding(Space.s)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, Space.s)
                }
            }
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        Haptics.softTap()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Haptics.softTap()
                        reloadToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
        }
        .interactiveDismissDisabled(false)
    }
}

/// 右下角悬浮入口
struct SiteBrowseFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: Space.xs) {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .semibold))
                Text("网站")
                    .font(Typo.label)
            }
            .foregroundStyle(Palette.onBrand)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .background(Palette.brand, in: Capsule())
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 iBox 网站")
    }
}
