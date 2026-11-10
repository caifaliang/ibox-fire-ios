import SwiftUI
import UIKit

// MARK: - Color helpers

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

// MARK: - Design tokens（对齐 Android FireDesign）

enum Palette {
    /// 象牙墨色 — 对齐 Android FireDesign 0.2.75+
    static let bg = Color(light: 0xF7F4EE, dark: 0x0B0F14)
    static let surface = Color(light: 0xFFFCF7, dark: 0x111827)
    static let surfaceMuted = Color(light: 0xEBE6DC, dark: 0x1F2937)
    static let hairline = Color(light: 0xE7E0D4, dark: 0x374151)
    static let textPrimary = Color(light: 0x111827, dark: 0xE5E7EB)
    static let textSecondary = Color(light: 0x6B7280, dark: 0x9CA3AF)
    static let textMuted = Color(light: 0x9CA3AF, dark: 0x6B7280)
    /// 主按钮 / 选中态 — 墨色品牌
    static let brand = Color(light: 0x111827, dark: 0xE5E7EB)
    static let onBrand = Color(light: 0xF7F4EE, dark: 0x0F172A)
    static let brandSubtle = Color(light: 0xEBE6DC, dark: 0x1F2937)
    static let liveAmber = Color(light: 0xC4A574, dark: 0xC4A574)
    /// 唯一强调色 — 链接/选中辅色（Android Accent）
    static let accent = Color(light: 0x2563EB, dark: 0x60A5FA)
    static let accentSoft = Color(light: 0xEFF6FF, dark: 0x1E293B)
    static let success = Color(light: 0x059669, dark: 0x4ADE80)
    static let successSoft = Color(light: 0xECFDF5, dark: 0x052E1C)
    static let warning = Color(light: 0xB45309, dark: 0xFBBF24)
    static let warningSoft = Color(light: 0xFFFBEB, dark: 0x3B2A0A)
    static let danger = Color(light: 0xDC2626, dark: 0xF87171)
    static let dangerSoft = Color(light: 0xFEF2F2, dark: 0x3B1212)
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let btn: CGFloat = 14
}

enum Typo {
    static let title = Font.system(.title3, design: .default, weight: .semibold)
    static let headline = Font.system(.headline, design: .default)
    static let body = Font.system(.body, design: .default)
    static let label = Font.system(.subheadline, design: .default, weight: .medium)
    static let caption = Font.system(.footnote, design: .default)
    static let caption2 = Font.system(.caption2, design: .default)
    static let number = Font.system(.title2, design: .default, weight: .semibold)
}

enum Motion {
    static let feedback: Double = 0.15
    static let transition: Double = 0.35
}
