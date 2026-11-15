import SwiftUI

/// Night sky: a soft vertical gradient with a sprinkle of stars.
struct Sky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bg2, Palette.bg, Palette.bg], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for i in 0..<46 {
                    let r = { (n: Double) -> Double in
                        let v = sin(Double(i) * 12.9898 + n * 78.233) * 43758.5453
                        return v - floor(v)
                    }
                    let p = CGPoint(x: r(1) * size.width, y: r(2) * size.height * 0.75)
                    let s = 0.6 + r(3) * 1.6
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: s, height: s)), with: .color(.white.opacity(0.12 + r(4) * 0.45)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Chunky game button: a darker lip underneath that the face presses down into.
struct GameButtonStyle: ButtonStyle {
    enum Kind { case gold, ok, danger, ghost }
    var kind: Kind = .gold
    @Environment(\.isEnabled) private var enabled

    private var colors: (face: Color, lip: Color, fg: Color) {
        switch kind {
        case .gold: return (Palette.gold, Palette.goldDeep, Palette.ink)
        case .ok: return (Palette.ok, Palette.okDeep, Color(hex: 0x032417))
        case .danger: return (Palette.alert, Palette.alertDeep, .white)
        case .ghost: return (Palette.card2, Color(hex: 0x0b1030), Palette.text)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let c = colors
        let down = configuration.isPressed
        return configuration.label
            .font(Typeface.display(17))
            .foregroundStyle(c.fg)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(c.face)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(kind == .ghost ? 0.08 : 0.25), lineWidth: 1).blendMode(.overlay))
            )
            .offset(y: down ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(c.lip).offset(y: 5)
            )
            .padding(.bottom, 5)
            .opacity(enabled ? 1 : 0.4)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: down)
    }
}

struct GameButton: View {
    let title: String
    var kind: GameButtonStyle.Kind = .gold
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            if busy { ProgressView().tint(kind == .ghost ? Palette.text : Palette.ink) } else { Text(title) }
        }
        .buttonStyle(GameButtonStyle(kind: kind))
        .disabled(busy)
    }
}

/// HUD chip: a 3D icon and a number, like a game's currency counter.
struct StatChip: View {
    let sprite: Sprite
    let value: String
    var tint: Color = Palette.text
    var body: some View {
        HStack(spacing: 6) {
            sprite.image.resizable().scaledToFit().frame(width: 26, height: 26)
            Text(value).font(Typeface.display(17)).foregroundStyle(tint).monospacedDigit()
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.09)))
        .fixedSize()
    }
}

struct GameCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.card2.opacity(0.95), Palette.card], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Palette.lineTop, Palette.line.opacity(0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = Palette.gold
    var body: some View {
        Text(text)
            .font(Typeface.bold(13))
            .foregroundStyle(tint)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct Banner: View {
    let text: String
    var alert = false
    var body: some View {
        Text(text)
            .font(Typeface.semi(15))
            .foregroundStyle(alert ? Color(hex: 0xffc2ca) : Color(hex: 0xffe1a0))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(alert ? Color(hex: 0x3a1620) : Color(hex: 0x3a2f14)))
    }
}

struct SectionTitle: View {
    let text: String
    var sub: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text).font(Typeface.displayBold(19)).foregroundStyle(Palette.text)
            if let sub { Text(sub).font(Typeface.body(14)).foregroundStyle(Palette.muted) }
        }
    }
}

/// Thick, glossy XP bar with level badge.
struct XPBar: View {
    let buddy: BuddyInfo
    let next: Int?
    var body: some View {
        let prev = buddy.form == "sprout" ? 0 : buddy.form == "strider" ? 100 : 250
        let pct = next.map { max(0, min(1, Double(buddy.xp - prev) / Double($0 - prev))) } ?? 1
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(buddy.name).font(Typeface.display(22)).foregroundStyle(Palette.text)
                Text(formName(buddy.form, species: buddy.species)).font(Typeface.semi(15)).foregroundStyle(Palette.muted)
                Spacer()
                Text(next.map { "\(buddy.xp) / \($0) XP" } ?? "\(buddy.xp) XP")
                    .font(Typeface.bold(14)).foregroundStyle(Palette.muted).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x0b1030))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0xffd66b), Palette.gold, Color(hex: 0xff9d2e)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(18, geo.size.width * pct))
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(0.35)).frame(height: 4).padding(.horizontal, 6).padding(.top, 3)
                        }
                        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: pct)
                }
            }
            .frame(height: 16)
        }
    }
}
