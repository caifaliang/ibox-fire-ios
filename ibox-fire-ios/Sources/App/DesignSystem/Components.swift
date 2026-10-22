import SwiftUI

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = Space.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            )
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.label)
            .foregroundStyle(Palette.onBrand)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Palette.brand.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: Radius.btn, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: Motion.feedback), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.label)
            .foregroundStyle(Palette.textPrimary.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Palette.surfaceMuted,
                in: RoundedRectangle(cornerRadius: Radius.btn, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.btn, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Motion.feedback), value: configuration.isPressed)
    }
}

struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.label)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Palette.danger.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: Radius.btn, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: Motion.feedback), value: configuration.isPressed)
    }
}

// MARK: - Field

struct AppTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var error: String = ""
    var autocap: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            Group {
                if isSecure {
                    SecureField(placeholder.isEmpty ? label : placeholder, text: $text)
                } else {
                    TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                        .textInputAutocapitalization(autocap)
                        .keyboardType(keyboard)
                }
            }
            .font(Typo.body)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.m)
            .background(
                Palette.surfaceMuted,
                in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(error.isEmpty ? Palette.hairline : Palette.danger, lineWidth: 0.5)
            )
            if !error.isEmpty {
                Text(error)
                    .font(Typo.caption2)
                    .foregroundStyle(Palette.danger)
            }
        }
    }
}

// MARK: - Chips / headers / rows

struct StatusChip: View {
    enum Kind { case neutral, success, warning, danger, accent }

    let title: String
    var kind: Kind = .neutral
    var selected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        let label = Text(title)
            .font(Typo.caption.weight(.semibold))
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .strokeBorder(border, lineWidth: selected || kind != .neutral ? 0 : 0.5)
            )
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    private var fg: Color {
        if selected { return Palette.onBrand }
        switch kind {
        case .neutral: return Palette.textPrimary
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        case .accent: return Palette.accent
        }
    }

    private var bg: Color {
        if selected { return Palette.brand }
        switch kind {
        case .neutral: return Palette.surfaceMuted
        case .success: return Palette.successSoft
        case .warning: return Palette.warningSoft
        case .danger: return Palette.dangerSoft
        case .accent: return Palette.accentSoft
        }
    }

    private var border: Color { Palette.hairline }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typo.label)
                .foregroundStyle(Palette.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(Typo.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = Palette.textPrimary
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.s)
            Text(value)
                .font(mono ? Typo.label.monospacedDigit() : Typo.label)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct EmptyState: View {
    let title: String
    var detail: String = ""
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textMuted)
            Text(title)
                .font(Typo.label)
                .foregroundStyle(Palette.textPrimary)
            if !detail.isEmpty {
                Text(detail)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xl)
    }
}

struct Skeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .fill(Palette.surfaceMuted)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .redacted(reason: .placeholder)
    }
}

// MARK: - Shared field chrome (legacy helpers → tokens)

extension View {
    func appFieldStyle() -> some View {
        self
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.m)
            .background(
                Palette.surfaceMuted,
                in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            )
    }

    func appScreenBackground() -> some View {
        self.background(Palette.bg.ignoresSafeArea())
    }

    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
    }
}
