import SwiftUI

/// Fonts available for the note text. All of them ship with iOS, so the
/// widget and the Live Activity can render them too.
enum NoteFont: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, rounded, serif, mono, menlo, courier, typewriter, avenir, georgia, futura

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "Default"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "SF Mono"
        case .menlo: "Menlo"
        case .courier: "Courier"
        case .typewriter: "Typewriter"
        case .avenir: "Avenir"
        case .georgia: "Georgia"
        case .futura: "Futura"
        }
    }

    private var postScriptNames: (regular: String, bold: String)? {
        switch self {
        case .menlo: ("Menlo-Regular", "Menlo-Bold")
        case .courier: ("CourierNewPSMT", "CourierNewPS-BoldMT")
        case .typewriter: ("AmericanTypewriter", "AmericanTypewriter-Semibold")
        case .avenir: ("AvenirNext-Regular", "AvenirNext-DemiBold")
        case .georgia: ("Georgia", "Georgia-Bold")
        case .futura: ("Futura-Medium", "Futura-Bold")
        default: nil
        }
    }

    func font(size: CGFloat, bold: Bool = false) -> Font {
        if let names = postScriptNames {
            return .custom(bold ? names.bold : names.regular, fixedSize: size)
        }
        let weight: Font.Weight = bold ? .semibold : .regular
        switch self {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        default: return .system(size: size, weight: weight)
        }
    }

    func uiFont(size: CGFloat, bold: Bool = false) -> UIFont {
        if let names = postScriptNames, let f = UIFont(name: bold ? names.bold : names.regular, size: size) {
            return f
        }
        let weight: UIFont.Weight = bold ? .semibold : .regular
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign? = switch self {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        default: nil
        }
        if let design, let descriptor = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}

enum TextSize: Int, CaseIterable, Identifiable, Codable, Sendable {
    case small = 0, regular = 1, large = 2

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .small: "Small"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    var appPointSize: CGFloat { [15, 17, 20][rawValue] }
    var livePointSize: CGFloat { [13, 14.5, 16][rawValue] }
    var widgetPointSize: CGFloat { [12, 13.5, 15][rawValue] }
}

/// How the Live Activity is painted on the Lock Screen.
enum LiveStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case theme, glass, clear

    var id: String { rawValue }

    var name: String {
        switch self {
        case .theme: "Theme"
        case .glass: "Dark Glass"
        case .clear: "Clear"
        }
    }

    var detail: String {
        switch self {
        case .theme: "Uses your theme's colours."
        case .glass: "A dark translucent card, like the system style."
        case .clear: "No background — just your list over the wallpaper."
        }
    }
}
