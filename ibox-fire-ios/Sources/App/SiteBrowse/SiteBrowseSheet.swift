import SwiftUI

/// 右下角悬浮入口（打开逻辑见 SiteBrowsePresenter，纯 UIKit present）
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
