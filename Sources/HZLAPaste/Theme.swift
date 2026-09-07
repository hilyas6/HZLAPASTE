import SwiftUI

/// Dark, silver-and-gold palette — a nod to grim monster-hunter dark fantasy
/// without reusing any copyrighted names, wordmarks, or artwork. Native
/// controls (Form, List) get the look for free via forced dark appearance;
/// these colors are for the custom-drawn chrome (rows, nav bar, accents).
enum Theme {
    static let background = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let card = Color(red: 0.145, green: 0.145, blue: 0.17)
    static let silver = Color(red: 0.83, green: 0.84, blue: 0.87)
    static let silverDim = Color(red: 0.55, green: 0.56, blue: 0.60)
    static let gold = Color(red: 0.72, green: 0.58, blue: 0.28)
    static let danger = Color(red: 0.62, green: 0.22, blue: 0.20)

    // Per-kind accents for the card grid's icon chips — kept out of the gold/silver
    // duo so kind is instantly scannable without reading the icon glyph itself.
    static let linkBlue = Color(red: 0.45, green: 0.64, blue: 0.95)
    static let fileTeal = Color(red: 0.42, green: 0.72, blue: 0.66)

    static let headerFont = Font.system(.title2, design: .serif).weight(.semibold)
    static let bodyFont = Font.system(size: 13, weight: .regular, design: .rounded)
    static let cornerRadius: CGFloat = 10
    static let cardRadius: CGFloat = 16

    static func accent(for kind: ClipKind) -> Color {
        switch kind {
        case .url: return linkBlue
        case .file: return fileTeal
        case .image: return gold
        case .text: return silverDim
        }
    }
}
