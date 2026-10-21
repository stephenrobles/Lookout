import SwiftUI

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA". Falls back to the accent color.
    nonisolated init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard let number = UInt64(value, radix: 16) else {
            self = .accentColor
            return
        }
        let r, g, b, a: Double
        switch value.count {
        case 6:
            r = Double((number >> 16) & 0xFF) / 255
            g = Double((number >> 8) & 0xFF) / 255
            b = Double(number & 0xFF) / 255
            a = 1
        case 8:
            r = Double((number >> 24) & 0xFF) / 255
            g = Double((number >> 16) & 0xFF) / 255
            b = Double((number >> 8) & 0xFF) / 255
            a = Double(number & 0xFF) / 255
        default:
            self = .accentColor
            return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

#if canImport(UIKit)
import UIKit

extension CGColor {
    /// "#RRGGBB" for an EventKit calendar color (any color space).
    nonisolated var lookoutHex: String {
        let ui = UIColor(cgColor: self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#0A84FF" }
        func clamp(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
#endif
