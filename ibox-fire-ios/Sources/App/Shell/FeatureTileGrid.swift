import SwiftUI

struct FeatureTileGrid: View {
    let features: [ShellTechTab]
    var accentKey: String?
    var onSelect: (ShellTechTab) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(features) { f in
                    let accent = f.key == accentKey
                    Button {
                        Haptics.tap()
                        onSelect(f)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(f.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if f.isNew {
                                    Text("NEW")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Palette.liveAmber)
                                }
                            }
                            Text(f.key)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.textMuted)
                                .lineLimit(1)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(accent ? Palette.brandSubtle : Palette.surface)
                        )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
