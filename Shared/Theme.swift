import SwiftUI

/// A colour theme in the spirit of the editor / monkeytype themes developers love.
/// Every theme is described by the same seven colours so it can paint the app,
/// the widget and the Live Activity consistently.
struct Theme: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Screen background.
    let bg: UInt32
    /// The note card / grouped rows.
    let card: UInt32
    /// Main text.
    let text: UInt32
    /// Secondary text, placeholders, checked items.
    let sub: UInt32
    /// Accent: checkboxes, bullets, the Live dot, prominent buttons.
    let main: UInt32
    /// Text cursor.
    let caret: UInt32
    /// Errors / destructive.
    let error: UInt32

    var isDark: Bool { Theme.relativeLuminance(bg) < 0.2 }
    var colorScheme: ColorScheme { isDark ? .dark : .light }

    var bgColor: Color { Color(hex: bg) }
    var cardColor: Color { Color(hex: card) }
    var textColor: Color { Color(hex: text) }
    var subColor: Color { Color(hex: sub) }
    var mainColor: Color { Color(hex: main) }
    var caretColor: Color { Color(hex: caret) }
    var errorColor: Color { Color(hex: error) }

    /// Readable foreground for content drawn on top of `mainColor`.
    var onMainColor: Color {
        Theme.contrast(0xFFFFFF, main) >= Theme.contrast(0x111111, main) ? .white : Color(hex: 0x111111)
    }

    /// Accent that stays visible on the Dynamic Island's black background.
    var islandAccent: Color {
        Theme.contrast(main, 0x000000) < 4.5 ? .white : mainColor
    }

    /// The text cursor colour, swapped for something visible when the theme's caret blends into the card.
    var editorCaret: UInt32 {
        if Theme.contrast(caret, card) >= 3 { return caret }
        if Theme.contrast(main, card) >= 3 { return main }
        return text
    }

    /// Tint for toggles, whose white knob sits on the tint.
    var controlTint: Color {
        Theme.contrast(main, 0xFFFFFF) < 1.5 ? Color(hex: 0x34C759) : mainColor
    }

    /// Error colour that stays readable on the card.
    var readableErrorColor: Color {
        Theme.contrast(error, card) >= 3 ? errorColor : textColor
    }

    /// True when the card's text is light, i.e. the card behaves like a dark surface.
    var hasLightText: Bool { Theme.relativeLuminance(text) > Theme.relativeLuminance(card) }

    /// WCAG 2 relative luminance (0 = black, 1 = white).
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    /// WCAG 2 contrast ratio between two colours (1...21).
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let x = relativeLuminance(a) + 0.05
        let y = relativeLuminance(b) + 0.05
        return max(x, y) / min(x, y)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Color {
    /// The tint behind ==highlighted== words: the accent itself, or a highlighter
    /// yellow when the accent is black, white or grey (a grey wash reads as a mistake).
    var highlighterTint: Color {
        let c = resolve(in: EnvironmentValues())
        let spread = max(c.red, c.green, c.blue) - min(c.red, c.green, c.blue)
        return spread < 0.12 ? Color(hex: 0xFFD60A).opacity(0.45) : opacity(0.3)
    }
}

extension UIColor {
    var highlighterTint: UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let spread = max(r, g, b) - min(r, g, b)
        return spread < 0.12 ? UIColor(hex: 0xFFD60A, alpha: 0.45) : withAlphaComponent(0.3)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum ThemeCatalog {
    static let defaultLightID = "default-light"
    static let defaultDarkID = "default-dark"

    /// Themes everyone gets. The rest come with the one-off Supporter unlock.
    static let freeIDs: Set<String> = [defaultLightID, defaultDarkID]

    static let all: [Theme] = [
        // The classic mynote look (matches iOS light / dark).
        Theme(id: "default-light", name: "Default Light", bg: 0xF2F2F7, card: 0xFFFFFF, text: 0x000000, sub: 0x8E8E93, main: 0x111111, caret: 0x111111, error: 0xFF3B30),
        Theme(id: "default-dark", name: "Default Dark", bg: 0x000000, card: 0x1C1C1E, text: 0xFFFFFF, sub: 0x8E8E93, main: 0xFFFFFF, caret: 0xFFFFFF, error: 0xFF453A),

        // Dark themes
        Theme(id: "serika-dark", name: "Serika Dark", bg: 0x323437, card: 0x2C2E31, text: 0xD1D0C5, sub: 0x646669, main: 0xE2B714, caret: 0xE2B714, error: 0xCA4754),
        Theme(id: "dracula", name: "Dracula", bg: 0x282A36, card: 0x343746, text: 0xF8F8F2, sub: 0x6272A4, main: 0xBD93F9, caret: 0xFF79C6, error: 0xFF5555),
        Theme(id: "nord", name: "Nord", bg: 0x2E3440, card: 0x3B4252, text: 0xECEFF4, sub: 0x7B88A1, main: 0x88C0D0, caret: 0xD8DEE9, error: 0xBF616A),
        Theme(id: "gruvbox-dark", name: "Gruvbox Dark", bg: 0x282828, card: 0x3C3836, text: 0xEBDBB2, sub: 0x928374, main: 0xFABD2F, caret: 0xFE8019, error: 0xFB4934),
        Theme(id: "catppuccin-mocha", name: "Catppuccin Mocha", bg: 0x1E1E2E, card: 0x313244, text: 0xCDD6F4, sub: 0x7F849C, main: 0xCBA6F7, caret: 0xF5E0DC, error: 0xF38BA8),
        Theme(id: "catppuccin-macchiato", name: "Catppuccin Macchiato", bg: 0x24273A, card: 0x363A4F, text: 0xCAD3F5, sub: 0x8087A2, main: 0x8AADF4, caret: 0xF4DBD6, error: 0xED8796),
        Theme(id: "tokyo-night", name: "Tokyo Night", bg: 0x1A1B26, card: 0x24283B, text: 0xC0CAF5, sub: 0x565F89, main: 0x7AA2F7, caret: 0xBB9AF7, error: 0xF7768E),
        Theme(id: "one-dark", name: "One Dark", bg: 0x282C34, card: 0x2F343F, text: 0xABB2BF, sub: 0x7F848E, main: 0x61AFEF, caret: 0xC678DD, error: 0xE06C75),
        Theme(id: "github-dark", name: "GitHub Dark", bg: 0x0D1117, card: 0x161B22, text: 0xC9D1D9, sub: 0x8B949E, main: 0x58A6FF, caret: 0x58A6FF, error: 0xF85149),
        Theme(id: "vscode", name: "VS Code Dark+", bg: 0x1E1E1E, card: 0x252526, text: 0xD4D4D4, sub: 0x808080, main: 0x007ACC, caret: 0x569CD6, error: 0xF44747),
        Theme(id: "monokai", name: "Monokai", bg: 0x272822, card: 0x3E3D32, text: 0xF8F8F2, sub: 0x75715E, main: 0xF92672, caret: 0x66D9EF, error: 0xFD971F),
        Theme(id: "solarized-dark", name: "Solarized Dark", bg: 0x002B36, card: 0x073642, text: 0x93A1A1, sub: 0x586E75, main: 0x859900, caret: 0xDC322F, error: 0xD33682),
        Theme(id: "rose-pine", name: "Rosé Pine", bg: 0x191724, card: 0x1F1D2E, text: 0xE0DEF4, sub: 0x6E6A86, main: 0xEBBCBA, caret: 0xC4A7E7, error: 0xEB6F92),
        Theme(id: "everforest", name: "Everforest", bg: 0x2D353B, card: 0x343F44, text: 0xD3C6AA, sub: 0x859289, main: 0xA7C080, caret: 0xE69875, error: 0xE67E80),
        Theme(id: "kanagawa", name: "Kanagawa", bg: 0x1F1F28, card: 0x2A2A37, text: 0xDCD7BA, sub: 0x727169, main: 0x7E9CD8, caret: 0xC8C093, error: 0xE82424),
        Theme(id: "ayu-dark", name: "Ayu Dark", bg: 0x0B0E14, card: 0x131721, text: 0xBFBDB6, sub: 0x565B66, main: 0xE6B450, caret: 0xE6B450, error: 0xD95757),
        Theme(id: "night-owl", name: "Night Owl", bg: 0x011627, card: 0x0B2942, text: 0xD6DEEB, sub: 0x637777, main: 0x82AAFF, caret: 0xC792EA, error: 0xEF5350),
        Theme(id: "synthwave", name: "Synthwave '84", bg: 0x262335, card: 0x34294F, text: 0xF4EEE4, sub: 0x848BBD, main: 0xFF7EDB, caret: 0x36F9F6, error: 0xFE4450),
        Theme(id: "material", name: "Material", bg: 0x263238, card: 0x2E3C43, text: 0xEEFFFF, sub: 0x7A93A0, main: 0x80CBC4, caret: 0xFFCC00, error: 0xF07178),
        Theme(id: "iceberg-dark", name: "Iceberg Dark", bg: 0x161821, card: 0x1E2132, text: 0xC6C8D1, sub: 0x6B7089, main: 0x84A0C6, caret: 0xC6C8D1, error: 0xE27878),
        Theme(id: "cobalt2", name: "Cobalt2", bg: 0x193549, card: 0x1F4662, text: 0xFFFFFF, sub: 0x8FB2C9, main: 0xFFC600, caret: 0xFFC600, error: 0xFF628C),
        Theme(id: "horizon", name: "Horizon", bg: 0x1C1E26, card: 0x232530, text: 0xD5D8DA, sub: 0x6C6F93, main: 0xE95678, caret: 0xFAB795, error: 0xF43E5C),
        Theme(id: "matrix", name: "Matrix", bg: 0x000000, card: 0x0A140A, text: 0xD1FFCD, sub: 0x2F8F2F, main: 0x15FF00, caret: 0x15FF00, error: 0xDA3333),
        Theme(id: "terminal", name: "Terminal", bg: 0x191A1B, card: 0x232425, text: 0xE7EAE0, sub: 0x5A5C5F, main: 0x79A617, caret: 0x79A617, error: 0xA61717),
        Theme(id: "8008", name: "8008", bg: 0x333A45, card: 0x2E343D, text: 0xE9ECF0, sub: 0x939EAE, main: 0xF44C7F, caret: 0xF44C7F, error: 0xDA3333),
        Theme(id: "carbon", name: "Carbon", bg: 0x313131, card: 0x2B2B2B, text: 0xF5E6C8, sub: 0x6B6B6B, main: 0xF66E0D, caret: 0xF66E0D, error: 0xE72D2D),
        Theme(id: "bento", name: "Bento", bg: 0x2D394D, card: 0x263041, text: 0xFFFAF8, sub: 0x6B91A6, main: 0xFF7A90, caret: 0xFF7A90, error: 0xEE2A3A),
        Theme(id: "olivia", name: "Olivia", bg: 0x1C1B1D, card: 0x2B2A2D, text: 0xF2EFED, sub: 0x6E5A5A, main: 0xDEAF9D, caret: 0xDEAF9D, error: 0xBF616A),
        Theme(id: "laser", name: "Laser", bg: 0x221B44, card: 0x2C2457, text: 0xDBE7E8, sub: 0xB82356, main: 0x00B4C8, caret: 0x00B4C8, error: 0xA8D400),
        Theme(id: "miami-nights", name: "Miami Nights", bg: 0x18181A, card: 0x232326, text: 0xFFFFFF, sub: 0x47BAC0, main: 0xE4609B, caret: 0xE4609B, error: 0xFFF591),
        Theme(id: "aurora", name: "Aurora", bg: 0x011926, card: 0x032636, text: 0xFFFFFF, sub: 0x3F7A87, main: 0x00E980, caret: 0x00E980, error: 0xB94DA1),
        Theme(id: "tokyo-night-storm", name: "Tokyo Night Storm", bg: 0x24283B, card: 0x2F334D, text: 0xC0CAF5, sub: 0x7A82A8, main: 0x7DCFFF, caret: 0xBB9AF7, error: 0xF7768E),
        Theme(id: "rose-pine-moon", name: "Rosé Pine Moon", bg: 0x232136, card: 0x2A273F, text: 0xE0DEF4, sub: 0x908CAA, main: 0xEA9A97, caret: 0xC4A7E7, error: 0xEB6F92),
        Theme(id: "superuser", name: "Superuser", bg: 0x262A33, card: 0x2F3440, text: 0xE5F7EF, sub: 0x6A8496, main: 0x43FFAF, caret: 0x43FFAF, error: 0xFF5F5F),

        // Light themes
        Theme(id: "serika", name: "Serika", bg: 0xE1E1E3, card: 0xEDEDEF, text: 0x323437, sub: 0x868A8F, main: 0x9C7B00, caret: 0xE2B714, error: 0xDA3333),
        Theme(id: "nord-light", name: "Nord Light", bg: 0xECEFF4, card: 0xF8F9FB, text: 0x2E3440, sub: 0x8C96A8, main: 0x5E81AC, caret: 0x5E81AC, error: 0xBF616A),
        Theme(id: "gruvbox-light", name: "Gruvbox Light", bg: 0xFBF1C7, card: 0xF2E5BC, text: 0x3C3836, sub: 0x928374, main: 0xB57614, caret: 0xAF3A03, error: 0x9D0006),
        Theme(id: "catppuccin-latte", name: "Catppuccin Latte", bg: 0xEFF1F5, card: 0xFFFFFF, text: 0x4C4F69, sub: 0x8C8FA1, main: 0x8839EF, caret: 0xDC8A78, error: 0xD20F39),
        Theme(id: "tokyo-day", name: "Tokyo Night Day", bg: 0xE1E2E7, card: 0xF0F1F5, text: 0x3760BF, sub: 0x848CB5, main: 0x2E7DE9, caret: 0x9854F1, error: 0xF52A65),
        Theme(id: "github-light", name: "GitHub Light", bg: 0xF6F8FA, card: 0xFFFFFF, text: 0x24292F, sub: 0x6E7781, main: 0x0969DA, caret: 0x0969DA, error: 0xCF222E),
        Theme(id: "solarized-light", name: "Solarized Light", bg: 0xFDF6E3, card: 0xEEE8D5, text: 0x475B62, sub: 0x7D8C8C, main: 0x6F8000, caret: 0xDC322F, error: 0xD33682),
        Theme(id: "rose-pine-dawn", name: "Rosé Pine Dawn", bg: 0xFAF4ED, card: 0xFFFAF3, text: 0x575279, sub: 0x8C87A0, main: 0xB4637A, caret: 0x907AA9, error: 0xB4637A),
        Theme(id: "ayu-light", name: "Ayu Light", bg: 0xFCFCFC, card: 0xF3F4F5, text: 0x5C6166, sub: 0x8A9199, main: 0xD9661A, caret: 0xFFAA33, error: 0xE65050),
        Theme(id: "iceberg-light", name: "Iceberg Light", bg: 0xE8E9EC, card: 0xF4F5F7, text: 0x33374C, sub: 0x8389A3, main: 0x2D539E, caret: 0x262A3F, error: 0xCC517A),
        Theme(id: "paper", name: "Paper", bg: 0xEEEEEE, card: 0xF8F8F8, text: 0x444444, sub: 0x949494, main: 0x444444, caret: 0x444444, error: 0xD70000),
        Theme(id: "lil-dragon", name: "Lil Dragon", bg: 0xEBE1EF, card: 0xF5EEF8, text: 0x212B43, sub: 0xAC76E5, main: 0x8A5BD6, caret: 0x212B43, error: 0xF794CA),
        Theme(id: "milkshake", name: "Milkshake", bg: 0xFFFFFF, card: 0xF3FAFD, text: 0x212B43, sub: 0x2E97B0, main: 0x212B43, caret: 0x212B43, error: 0xF19DAC),
        Theme(id: "mizu", name: "Mizu", bg: 0xAFCBDD, card: 0xC3D8E6, text: 0x1A2633, sub: 0x6E8FA6, main: 0x1A2633, caret: 0xFCFBF6, error: 0xBF616A),
    ]

    private static let byID: [String: Theme] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func theme(_ id: String) -> Theme {
        byID[id] ?? byID[defaultLightID]!
    }

    static var darkThemes: [Theme] { all.filter(\.isDark) }
    static var lightThemes: [Theme] { all.filter { !$0.isDark } }
}

extension EnvironmentValues {
    @Entry var theme: Theme = ThemeCatalog.theme(ThemeCatalog.defaultLightID)
}
