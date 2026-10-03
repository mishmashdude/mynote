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

    /// PostScript names of the bundled faces. A missing italic is drawn slanted instead.
    private var faces: (regular: String, bold: String, italic: String?, boldItalic: String?)? {
        switch self {
        case .menlo: ("Menlo-Regular", "Menlo-Bold", "Menlo-Italic", "Menlo-BoldItalic")
        case .courier: ("CourierNewPSMT", "CourierNewPS-BoldMT", "CourierNewPS-ItalicMT", "CourierNewPS-BoldItalicMT")
        case .typewriter: ("AmericanTypewriter", "AmericanTypewriter-Semibold", nil, nil)
        case .avenir: ("AvenirNext-Regular", "AvenirNext-DemiBold", "AvenirNext-Italic", "AvenirNext-DemiBoldItalic")
        case .georgia: ("Georgia", "Georgia-Bold", "Georgia-Italic", "Georgia-BoldItalic")
        case .futura: ("Futura-Medium", "Futura-Bold", "Futura-MediumItalic", nil)
        default: nil
        }
    }

    func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        if italic {
            return Font(uiFont(size: size, bold: bold, italic: true) as CTFont)
        }
        if let faces {
            return .custom(bold ? faces.bold : faces.regular, fixedSize: size)
        }
        let weight: Font.Weight = bold ? .semibold : .regular
        switch self {
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        default: return .system(size: size, weight: weight)
        }
    }

    func uiFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
        if let faces {
            if italic, let name = bold ? faces.boldItalic : faces.italic, let face = UIFont(name: name, size: size) {
                return face
            }
            if let face = UIFont(name: bold ? faces.bold : faces.regular, size: size) {
                return italic ? Self.slanted(face) : face
            }
        }
        let weight: UIFont.Weight = bold ? .semibold : .regular
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign? = switch self {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        default: nil
        }
        if let design, let descriptor = font.fontDescriptor.withDesign(design) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        return italic ? Self.italicized(font) : font
    }

    /// Monospaced font for `code`, a touch smaller so it sits well next to the note text.
    static func codeUIFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
        let font = UIFont.monospacedSystemFont(ofSize: size * 0.9, weight: bold ? .semibold : .regular)
        return italic ? italicized(font) : font
    }

    static func codeFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        Font(codeUIFont(size: size, bold: bold, italic: italic) as CTFont)
    }

    private static func italicized(_ font: UIFont) -> UIFont {
        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            let italic = UIFont(descriptor: descriptor, size: font.pointSize)
            if italic.fontDescriptor.symbolicTraits.contains(.traitItalic) { return italic }
        }
        return slanted(font)
    }

    /// A slanted copy for faces that have no italic of their own.
    private static func slanted(_ font: UIFont) -> UIFont {
        let matrix = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        return UIFont(descriptor: font.fontDescriptor.addingAttributes([.matrix: matrix]), size: font.pointSize)
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

/// How much bigger headings are than the note text. Widgets and the Lock Screen
/// use a flatter scale so headings don't eat the little room there is.
enum HeadingScale {
    static func factor(level: Int, compact: Bool) -> CGFloat {
        switch (level, compact) {
        case (1, false): 1.32
        case (2, false): 1.16
        case (_, false): 1.04
        case (1, true): 1.14
        case (2, true): 1.07
        default: 1
        }
    }
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
        case .glass: "A dark see-through card, like the system style."
        case .clear: "No background, just your list over the wallpaper."
        }
    }
}

/// Rich Text shows formatting as you type; Markdown shows the symbols.
enum EditorMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case rich, markdown

    var id: String { rawValue }

    var name: String {
        switch self {
        case .rich: "Rich Text"
        case .markdown: "Markdown"
        }
    }
}
