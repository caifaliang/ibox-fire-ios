import SwiftUI

enum ShellTab: String, CaseIterable, Identifiable {
    case tech, running, officialH5, me
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tech: return "科技"
        case .running: return "进行中"
        case .officialH5: return "官方H5"
        case .me: return "我的"
        }
    }
}

struct FireBottomBar: View {
    @Binding var selected: ShellTab
    var onSelect: (ShellTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline.opacity(0.8))
                .frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(ShellTab.allCases) { tab in
                    let sel = tab == selected
                    Button {
                        Haptics.selection()
                        onSelect(tab)
                    } label: {
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(sel ? Palette.brand : Palette.textMuted.opacity(0.28))
                                .frame(width: sel ? 20 : 10, height: 3)
                                .animation(.easeInOut(duration: 0.18), value: sel)
                            Text(tab.label)
                                .font(.system(size: 12, weight: sel ? .semibold : .medium))
                                .foregroundStyle(sel ? Palette.textPrimary : Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
            .background(Palette.surface.opacity(0.96))
        }
    }
}
