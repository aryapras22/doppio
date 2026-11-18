import IslandCore
import SwiftUI

struct Sprite {
    let rows: [String]
    let palette: [Character: Color]
}

struct PixelView: View {
    let sprite: Sprite
    var scale: CGFloat = 3

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in sprite.rows.enumerated() {
                let y0 = (CGFloat(y) * scale).rounded()
                let y1 = (CGFloat(y + 1) * scale).rounded()
                for (x, ch) in row.enumerated() {
                    guard let color = sprite.palette[ch] else { continue }
                    let x0 = (CGFloat(x) * scale).rounded()
                    let x1 = (CGFloat(x + 1) * scale).rounded()
                    ctx.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)), with: .color(color))
                }
            }
        }
        .frame(
            width: (CGFloat(sprite.rows.first?.count ?? 0) * scale).rounded(),
            height: (CGFloat(sprite.rows.count) * scale).rounded()
        )
    }
}

enum Sprites {
    private static let bodyPalette: [Character: Color] = ["L": .latte, "E": .espresso, "M": .mocha, "C": .crema, "A": .amber, "G": .mint]

    static let barista = Sprite(rows: [
        ".....AA.....",
        ".LLLLLLLLLL.",
        ".LEEEEEEEEL.",
        ".LEAAEEAAEL.",
        ".LEEEEEEEEL.",
        ".LEAEEEEAEL.",
        ".LEEAAAAEEL.",
        ".LLLLLLLLLL.",
        ".....MM.....",
        "LLLLLLLLLLLL",
        "LLCCCCCCCCLL",
        ".LLLLLLLLLL.",
        "..MM....MM..",
    ], palette: bodyPalette)

    static let pourOver = Sprite(rows: [
        ".....GG.....",
        ".....G......",
        "...LLLLLL...",
        "..LLEEEELL..",
        "..LLEEGELL..",
        "..LLEEGELL..",
        "..LLEGGELL..",
        "...LLLLLL...",
        ".....MM.....",
        "..LLLLLLLL..",
        "..LGGGGGGL..",
        "...LLLLLL...",
        "..MM....MM..",
    ], palette: bodyPalette)

    static func robot(for agent: Agent) -> Sprite { agent == .claude ? barista : pourOver }

    private static let menuSteamFrames: [[String]] = [
        ["....a..a....", "...a..a....."],
        ["...a..a.....", "....a..a...."],
        ["....a...a...", "...a..a....."],
    ]

    /// The status item cup; steam only rises while a Claude session is brewing.
    static func menuBarCup(steamFrame: Int?) -> Sprite {
        let steam = steamFrame.map { menuSteamFrames[$0 % menuSteamFrames.count] } ?? ["............", "............"]
        return Sprite(rows: steam + [
            "............",
            ".LLLLLLLL...",
            ".LLLLLLLLLL.",
            ".LLLLLLLL.L.",
            ".LLLLLLLLLL.",
            "..LLLLLL....",
            "MMMMMMMMMM..",
        ], palette: ["L": .latte, "a": .amber, "M": .mocha])
    }

    private static let menuRobotEyes = ["EGEEGE", "GEEGEE", "EGEEGE", "EEGEEG"]

    /// The status item robot for agy builders; it looks around and blinks its antenna while one is brewing.
    static func menuBarRobot(frame: Int?) -> Sprite {
        let eyes = frame.map { menuRobotEyes[$0 % menuRobotEyes.count] } ?? "EGEEGE"
        let tip = frame.map { $0 % 2 == 0 ? "G" : "A" } ?? "M"
        return Sprite(rows: [
            "....\(tip).....",
            "....M.....",
            ".LLLLLLLL.",
            ".LEEEEEEL.",
            ".L\(eyes)L.",
            ".LEEEEEEL.",
            ".LLLLLLLL.",
            "...LLLL...",
            "..MM..MM..",
        ], palette: ["L": .latte, "E": .espresso, "G": .mint, "A": .amber, "M": .mocha])
    }

    private static let steamFrames: [[String]] = [
        ["...s.......", "....s..s..."],
        ["....s..s...", "...s......."],
        ["...s...s...", "....s......."],
    ]

    /// Four inner rows of coffee, filled from the bottom by context percent; steam rows are added above when brewing.
    static func cup(contextPercent: Double?, fillColor: Color, steamFrame: Int?) -> Sprite {
        let filled = Int(((contextPercent ?? 0) / 100 * 4).rounded(.up).clamped(0, 4))
        let inner = (0..<4).map { row in row >= 4 - filled ? "cccccc" : "eeeeee" }
        let body = [
            ".LLLLLLLL..",
            ".L\(inner[0])L.L",
            ".L\(inner[1])LLL",
            ".L\(inner[2])L.L",
            ".L\(inner[3])LL.",
            "..LLLLLL...",
            "LLLLLLLLLL.",
        ]
        let steam = steamFrame.map { steamFrames[$0 % steamFrames.count] } ?? ["...........", "..........."]
        return Sprite(rows: steam + body, palette: [
            "L": .latte, "e": .espresso, "c": fillColor, "s": .mocha,
        ])
    }
}

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { Swift.min(Swift.max(self, low), high) }
}

extension Session {
    var cupFillColor: Color {
        guard let p = contextPercent else { return Color(hex: 0x8B5A3C) }
        return p > 80 ? .tomato : p >= 50 ? .amber : Color(hex: 0x8B5A3C)
    }
}

struct CupView: View {
    let session: Session
    var scale: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let brewing = session.state == .working || session.state == .runningTool
        if brewing && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
                let frame = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3
                PixelView(sprite: Sprites.cup(contextPercent: session.contextPercent, fillColor: session.cupFillColor, steamFrame: frame), scale: scale)
            }
        } else {
            PixelView(sprite: Sprites.cup(contextPercent: session.contextPercent, fillColor: session.cupFillColor, steamFrame: nil), scale: scale)
        }
    }
}
