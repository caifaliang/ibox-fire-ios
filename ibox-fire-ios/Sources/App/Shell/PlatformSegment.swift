import SwiftUI

struct PlatformSegment: View {
    let platform: String
    var onSelect: (String) -> Void

    private let items: [(String, String)] = [
        ("ibox", "iBox"),
        ("newbee", "NewBee"),
        ("ibpro", "ibPro"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { key, label in
                let sel = platform == key
                Button {
                    Haptics.selection()
                    onSelect(key)
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: sel ? .bold : .medium))
                        .foregroundStyle(sel ? Palette.onBrand : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(sel ? Palette.brand : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.surfaceMuted, in: Capsule(style: .continuous))
    }
}
