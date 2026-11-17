import SwiftUI
import WebKit

/// NewBee 官方 H5 全屏壳：默认市场 + 顶栏芯片回市场/首页/活动/我的
struct OfficialNbH5View: View {
    @ObservedObject private var session = OfficialNbH5Session.shared
    var onBackToTech: () -> Void

    private let chips: [(String, String)] = [
        ("市场", OfficialNbH5Session.marketPath),
        ("首页", OfficialNbH5Session.homePath),
        ("活动", OfficialNbH5Session.activityPath),
        ("我的", OfficialNbH5Session.minePath),
    ]
    @State private var active = "市场"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    onBackToTech()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("NewBee H5")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    Haptics.tap()
                    onBackToTech()
                } label: {
                    Text("科技")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.brandSubtle, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.surface)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.0) { label, path in
                        let sel = active == label
                        Button {
                            Haptics.tap()
                            active = label
                            session.navigate(path: path, label: label)
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(sel ? Palette.onBrand : Palette.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(sel ? Palette.brand : Palette.surfaceMuted)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Palette.surface)

            Text(session.status)
                .font(Typo.caption2)
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .background(Palette.surface)

            if let wv = session.webView {
                OfficialNbH5WebViewHost(webView: wv)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Palette.bg
                    .overlay(Text("加载中…").foregroundStyle(Palette.textMuted))
            }
        }
        .background(Palette.bg.ignoresSafeArea())
    }
}

private struct OfficialNbH5WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
