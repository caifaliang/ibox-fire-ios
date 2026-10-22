import SwiftUI

/// 仿 App 全屏浏览线上站 ai.iboxai.top
struct SiteBrowseSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0
    @State private var pageTitle = "iBox 站"
    @State private var loading = false
    /// 延后挂载 WebView，避开 fullScreenCover 动画期同步初始化崩溃
    @State private var mountWeb = false

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
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                Button("关闭") {
                    Haptics.softTap()
                    dismiss()
                }
                .font(Typo.label)
                .foregroundStyle(Palette.accent)

                Spacer()

                Text(pageTitle)
                    .font(Typo.label)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button {
                    Haptics.softTap()
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Palette.textPrimary)
                }
                .disabled(!mountWeb || loading)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .background(Palette.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.hairline).frame(height: 0.5)
            }

            ZStack {
                Palette.bg.ignoresSafeArea()
                if mountWeb {
                    SiteWebView(
                        url: siteURL,
                        siteToken: vm.siteUser?.token ?? "",
                        userCacheJSON: userCacheJSON,
                        iboxToken: vm.iboxToken,
                        reloadToken: $reloadToken,
                        onTitle: { t in
                            DispatchQueue.main.async {
                                pageTitle = t.isEmpty ? "iBox 站" : t
                            }
                        },
                        onLoading: { on in
                            DispatchQueue.main.async { loading = on }
                        }
                    )
                } else {
                    ProgressView("加载中…")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                if mountWeb && loading {
                    ProgressView()
                        .padding(Space.s)
                        .background(Palette.surface.opacity(0.92), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.bg.ignoresSafeArea())
        .onAppear {
            // present 完成后再建 WKWebView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                mountWeb = true
            }
        }
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
