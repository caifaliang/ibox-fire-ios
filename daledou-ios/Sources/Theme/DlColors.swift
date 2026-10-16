import SwiftUI

/// 对齐 `F:\DaLedou_App_Dev\...\ui\theme\Color.kt` DlColors（浅底科技）。
enum DlColors {
    static let brand = Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255)
    static let brandSoft = Color(red: 0x1F / 255, green: 0x29 / 255, blue: 0x37 / 255)
    static let onBrand = Color.white

    static let accentBlue = Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
    static let accentBlueSoft = Color(red: 0xEF / 255, green: 0xF6 / 255, blue: 0xFF / 255)

    static let canvas = Color(red: 0xF4 / 255, green: 0xF6 / 255, blue: 0xF9 / 255)
    static let surface = Color.white
    static let surfaceMuted = Color(red: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255)
    static let border = Color(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255)

    static let ink = Color(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255)
    static let inkSecondary = Color(red: 0x47 / 255, green: 0x55 / 255, blue: 0x69 / 255)
    static let inkMuted = Color(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255)

    static let primary = brand
    static let secondary = accentBlue
    static let cinnabar = Color(red: 0xC4 / 255, green: 0x5C / 255, blue: 0x3E / 255)
    /// 背包页悬浮钮（对齐 Android `FabBeiBao` 0xFFD4785C）
    static let fabBeiBao = Color(red: 0xD4 / 255, green: 0x78 / 255, blue: 0x5C / 255)
}
