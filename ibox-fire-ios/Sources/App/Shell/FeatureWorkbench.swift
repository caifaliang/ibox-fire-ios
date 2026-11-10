import SwiftUI

struct FeatureWorkbench<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Palette.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typo.caption2)
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.bg)
    }
}
