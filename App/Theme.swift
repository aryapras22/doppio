import AppKit
import CoreText
import IslandCore
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let espresso = Color(hex: 0x1E140E)
    static let roast = Color(hex: 0x3A2A20)
    static let mocha = Color(hex: 0xA88B74)
    static let crema = Color(hex: 0xD9A066)
    static let latte = Color(hex: 0xEED9B7)
    static let amber = Color(hex: 0xFFB000)
    static let mint = Color(hex: 0x8FD3B6)
    static let tomato = Color(hex: 0xE4572E)
}

enum Theme {
    static let fontName = "VT323-Regular"

    /// Finds the font in the app bundle first; Bundle.module only exists when running unbundled, so it is touched last.
    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "VT323-Regular", withExtension: "ttf")
                ?? Bundle.module.url(forResource: "VT323-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func readout(_ size: CGFloat) -> Font {
        NSFont(name: fontName, size: size) != nil ? .custom(fontName, size: size) : .system(size: size, design: .monospaced)
    }

    static func name(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension Session {
    var rowTitle: String {
        guard agent == .agy, let task = taskId else { return project }
        return title.map { "\(task) · \($0)" } ?? task
    }

    var stateLabel: String {
        if cupReady { return "CUP READY" }
        return switch state {
        case .working: "BREWING"
        case .runningTool: "GRINDING: \(currentTool ?? "tool")"
        case .needsYou: "ORDER UP!"
        case .idle: "ON THE WARMER"
        case .failed: "SPILLED"
        case .ended: "CUP CLEARED"
        }
    }

    var stateColor: Color {
        if cupReady { return .mint }
        return switch state {
        case .working, .runningTool: .amber
        case .needsYou, .failed: .tomato
        case .idle, .ended: .mocha
        }
    }

    var contextColor: Color {
        guard let p = contextPercent else { return .mocha }
        return p > 80 ? .tomato : p >= 50 ? .amber : .mocha
    }

    var contextText: String {
        guard let p = contextPercent else { return "ctx --" }
        return "ctx \(contextIsEstimate ? "~" : "")\(Int(p.rounded()))%"
    }

    var tokenText: String {
        let n = totalTokens
        let value = n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)K" : "\(n)"
        return "\(contextIsEstimate ? "~" : "")\(value) TOK"
    }
}
