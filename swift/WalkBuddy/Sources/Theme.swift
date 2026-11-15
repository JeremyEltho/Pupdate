import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

enum Palette {
    static let bg = Color(hex: 0x0a0d1c)      // night sky
    static let bg2 = Color(hex: 0x141a44)
    static let card = Color(hex: 0x151a33)
    static let card2 = Color(hex: 0x1d2445)
    static let line = Color(hex: 0x2a3260)
    static let lineTop = Color(hex: 0x3b4687)
    static let text = Color(hex: 0xf3f4ff)
    static let muted = Color(hex: 0x9aa1c9)
    static let gold = Color(hex: 0xffbe3d)     // XP gold, the one accent
    static let goldDeep = Color(hex: 0xc97f00)
    static let ok = Color(hex: 0x3ee0a1)
    static let okDeep = Color(hex: 0x12996a)
    static let warn = Color(hex: 0xffc857)
    static let alert = Color(hex: 0xff4d6d)
    static let alertDeep = Color(hex: 0xb51a3c)
    static let ink = Color(hex: 0x1a1300)
    static let sky = Color(hex: 0x7aa2ff)
}

enum Typeface {
    static func display(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-ExtraBold", size: size) }
    static func displayBold(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-Bold", size: size) }
    static func body(_ size: CGFloat = 16) -> Font { .custom("Figtree-Medium", size: size) }
    static func semi(_ size: CGFloat = 16) -> Font { .custom("Figtree-SemiBold", size: size) }
    static func bold(_ size: CGFloat = 16) -> Font { .custom("Figtree-Bold", size: size) }
}

/// 3D sprites from Microsoft Fluent Emoji (MIT). See Resources/Sprites/FLUENT_EMOJI_LICENSE.txt.
enum Sprite: String {
    case hatchling = "hatching_chick", chick = "front-facing_baby_chick", owl
    case question = "red_question_mark", exclaim = "red_exclamation_mark", sparkles, sweat = "sweat_droplets"
    case fire, gem = "gem_stone", shield, footprints, house, bell, trophy, star = "glowing_star", crown
    case compass, books, pin = "round_pushpin"

    var image: Image {
        if let ui = UIImage(named: rawValue) ?? Bundle.main.path(forResource: rawValue, ofType: "png").flatMap(UIImage.init(contentsOfFile:)) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "questionmark.circle")
    }
}

enum Mood { case calm, asking, worried, alarmed, happy }

struct StateCopy { let title: String; let sub: String; let mood: Mood }

let STATE_COPY: [String: StateCopy] = [
    "calm": .init(title: "Walking together", sub: "Levin is keeping an eye out.", mood: .calm),
    "checkin": .init(title: "Still good?", sub: "Tap Levin to say you're OK.", mood: .asking),
    "nudge": .init(title: "Hey, you there?", sub: "Tap Levin now.", mood: .worried),
    "final": .init(title: "Last chance", sub: "Your friends get an alert soon.", mood: .worried),
    "countdown": .init(title: "Alerting friends", sub: "Tap Levin to cancel.", mood: .alarmed),
    "alert": .init(title: "Friends alerted", sub: "Tap Levin to tell them you're OK.", mood: .alarmed),
]

func formSprite(_ form: String) -> Sprite {
    switch form { case "strider": return .chick; case "guardian": return .owl; default: return .hatchling }
}

func formName(_ form: String) -> String {
    switch form { case "strider": return "Chick"; case "guardian": return "Night Owl"; default: return "Hatchling" }
}

func level(_ xp: Int) -> Int { xp / 25 + 1 }

enum Haptics {
    private static var on: Bool { UserDefaults.standard.object(forKey: "wb.haptics") as? Bool ?? true }
    static func tap() { if on { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func warning() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
}
