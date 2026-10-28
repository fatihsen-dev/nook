import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0D0E0D)
    static let sidebar = Color(hex: 0x1B1E1B)
    static let raised = Color(hex: 0x232723)
    static let raisedStrong = Color(hex: 0x2A2F29)
    static let line = Color(hex: 0x2C312B)
    static let text = Color(hex: 0xF2F5EC)
    static let muted = Color(hex: 0x8D9389)
    static let faint = Color(hex: 0x5E645B)
    static let lime = Color(hex: 0xB8E62E)
    static let limeHover = Color(hex: 0xC8F04A)
    static let raisedHover = Color(hex: 0x353B34)
    static let rowHover = Color(hex: 0x232723, opacity: 0.55)
    static let limeSoft = Color(hex: 0xB8E62E, opacity: 0.12)
    static let limeOutline = Color(hex: 0xB8E62E, opacity: 0.4)
    static let danger = Color(hex: 0xFF6B57)
    static let dangerHover = Color(hex: 0xFF8572)
    static let dangerSoft = Color(hex: 0xFF6B57, opacity: 0.13)
    static let dangerLine = Color(hex: 0xFF6B57, opacity: 0.33)
    static let console = Color(hex: 0x0F110F)
    static let menu = Color(hex: 0x161916)
    static let scrim = Color(hex: 0x0B0C0B, opacity: 0.7)

    static let controlHeight: CGFloat = 36
    static let controlRadius: CGFloat = 10
    static let cardRadius: CGFloat = 14
    static let sidebarWidth: CGFloat = 272
    static let titlebarInset: CGFloat = 44
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}
