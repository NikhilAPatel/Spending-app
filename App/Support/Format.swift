import SwiftUI
import UIKit
import WorthCore

enum Format {
    static func currency(_ value: Decimal, cents: Bool = false) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
    }

    /// "+$1,204" / "-$1,204", for changes over time.
    static func signedCurrency(_ value: Decimal) -> String {
        let magnitude = currency(abs(value))
        return value < 0 ? "-\(magnitude)" : "+\(magnitude)"
    }

    /// Axis-style compact amounts: $950, $8.5K, $120K, $1.2M.
    static func compactCurrency(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        func trimmed(_ number: Double) -> String {
            number >= 10 || number == number.rounded() ? String(format: "%.0f", number) : String(format: "%.1f", number)
        }
        switch magnitude {
        case 1_000_000_000...: return "\(sign)$\(trimmed(magnitude / 1_000_000_000))B"
        case 1_000_000...: return "\(sign)$\(trimmed(magnitude / 1_000_000))M"
        case 1_000...: return "\(sign)$\(trimmed(magnitude / 1_000))K"
        default: return "\(sign)$\(String(format: "%.0f", magnitude))"
        }
    }

    static func quantity(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}

extension Color {
    /// Chart and accent colors, stepped separately for light and dark mode.
    static let chartAccent = Color(light: 0x2A78D6, dark: 0x3987E5)
    static let chartAccentTrack = Color(light: 0xCDE2FB, dark: 0x184F95)
    static let chartMuted = Color(light: 0xC3C2B7, dark: 0x52514E)
    static let gain = Color(light: 0x006300, dark: 0x0CA30C)
    static let loss = Color(light: 0xD03B3B, dark: 0xE66767)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension CategoryKind {
    var title: String {
        switch self {
        case .expense: "Spending"
        case .income: "Income"
        case .transfer: "Transfers (not counted)"
        }
    }
}

/// An up/down change with an arrow, so direction never relies on color alone.
struct DeltaLabel: View {
    let change: Decimal
    let period: String

    var body: some View {
        let isUp = change >= 0
        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
            Text(Format.signedCurrency(change))
            Text(period).foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isUp ? Color.gain : Color.loss)
    }
}
