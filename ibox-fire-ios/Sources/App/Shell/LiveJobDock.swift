import SwiftUI

struct LiveJobDock: View {
    let label: String
    var onOpen: () -> Void
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.liveAmber)
                .frame(width: 8, height: 8)
            Button(action: onOpen) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                Haptics.warn()
                onStop()
            } label: {
                Text("停止")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
