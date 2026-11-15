import SwiftUI

/// The pet. Pet it by rubbing a finger across it (a tap does nothing); hold still for 2 s for a silent alert.
struct BuddyView: View {
    let form: String
    var species: String? = "chick"
    let mood: Mood
    var size: CGFloat = 240
    var pedestal = true
    var onPet: (() -> Void)?
    var onDuress: (() -> Void)?

    @State private var bob = false
    @State private var shake = false
    @State private var badgeIn = false
    // Stroke state
    @State private var hand: CGPoint?
    @State private var lean: Double = 0
    @State private var squash: CGFloat = 1
    @State private var strokeDist: CGFloat = 0
    @State private var lastPoint: CGPoint?
    @State private var hearts: [Heart] = []

    struct Heart: Identifiable { let id = UUID(); let x: CGFloat; var rise = false }

    private var glow: Color {
        switch mood {
        case .calm, .happy: return Palette.gold
        case .asking: return Palette.sky
        case .worried: return Palette.warn
        case .alarmed: return Palette.alert
        }
    }

    private var badge: Sprite? {
        switch mood {
        case .asking: return .question
        case .worried: return .sweat
        case .alarmed: return .exclaim
        case .happy: return .sparkles
        case .calm: return nil
        }
    }

    private var bobSpeed: Double { mood == .alarmed ? 0.28 : mood == .worried ? 0.5 : 1.3 }
    /// Where the head is, as a fraction of sprite width from center (side-view pets face left).
    private var headX: CGFloat {
        switch species ?? "chick" { case "penguin", "sloth", "chick": return 0; case "seal", "turtle": return -0.3; default: return -0.24 }
    }
    private var strokeNeeded: CGFloat { size * 0.75 } // a real rub, not a flick

    var body: some View {
        let sprite = size * 0.74
        ZStack(alignment: .bottom) {
            if pedestal {
                Ellipse()
                    .fill(RadialGradient(colors: [glow.opacity(0.55), glow.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.5))
                    .frame(width: size * 1.1, height: size * 0.36)
                    .offset(y: -size * 0.02)
                    .animation(.easeInOut(duration: 0.4), value: mood)
                Ellipse().fill(Color(hex: 0x080b22)).frame(width: size * 0.66, height: size * 0.15).offset(y: -size * 0.03)
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0x323d80), Color(hex: 0x171d44)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.66, height: size * 0.14)
                    .overlay(Ellipse().stroke(.white.opacity(0.12), lineWidth: 1))
                    .offset(y: -size * 0.05)
            }
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: sprite * 0.5, height: sprite * 0.08)
                .scaleEffect(x: bob ? 0.8 : 1)
                .offset(y: -size * 0.09)
            ZStack(alignment: .top) {
                petSprite(species, form).image
                    .resizable().scaledToFit()
                    .frame(width: sprite, height: sprite)
                    .shadow(color: glow.opacity(0.35), radius: 24, y: 6)
                if let gear = petGear(species, form) {
                    gear.image.resizable().scaledToFit()
                        .frame(width: sprite * (gear == .crown ? 0.42 : 0.3))
                        .offset(x: gear == .crown ? sprite * headX : sprite * 0.32, y: gear == .crown ? -sprite * 0.12 : sprite * 0.52)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }
            }
            .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
            .rotationEffect(.degrees((shake ? 7 : 0) + lean), anchor: .bottom)
            .offset(y: -size * 0.1 - (bob ? (mood == .alarmed ? 5 : 14) : 0))
            .id("\(species ?? "chick")-\(form)") // new look pops in on evolution or a species change
            .transition(.scale(scale: 0.3).combined(with: .opacity))

            // Hearts from a finished stroke.
            ForEach(hearts) { h in
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.1, weight: .bold))
                    .foregroundStyle(Color(hex: 0xff6f91))
                    .shadow(color: Color(hex: 0xff6f91).opacity(0.6), radius: 6)
                    .offset(x: h.x, y: h.rise ? -size * 0.95 : -size * 0.45)
                    .opacity(h.rise ? 0 : 1)
                    .scaleEffect(h.rise ? 1.3 : 0.6)
            }
            // The stroking hand follows the finger.
            if let hand {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: size * 0.16, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                    .rotationEffect(.degrees(-20 + lean * 2))
                    .position(hand)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if let badge {
                badge.image.resizable().scaledToFit()
                    .frame(width: size * 0.26, height: size * 0.26)
                    .rotationEffect(.degrees(12))
                    .scaleEffect(badgeIn ? 1 : 0.2)
                    .opacity(badgeIn ? 1 : 0)
                    .offset(x: -size * 0.04, y: size * 0.02)
            }
        }
        .contentShape(Rectangle())
        .gesture(stroke)
        .simultaneousGesture(LongPressGesture(minimumDuration: 2).onEnded { _ in onDuress?() })
        .accessibilityElement()
        .accessibilityLabel("Your buddy")
        .accessibilityHint("Rub your finger across to pet")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { completePet() }
        .onAppear { animate() }
        .onChange(of: mood) { _, _ in animate() }
    }

    private var stroke: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { v in
                hand = v.location
                if let last = lastPoint { strokeDist += hypot(v.location.x - last.x, v.location.y - last.y) }
                lastPoint = v.location
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.6)) {
                    lean = Double(max(-12, min(12, v.translation.width / 8)))
                    squash = 0.93 + 0.07 * cos(Double(strokeDist) / 30)
                }
                if strokeDist >= strokeNeeded {
                    strokeDist = -10_000 // one pet per stroke
                    completePet()
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { lean = 0; squash = 1 }
                withAnimation(.easeOut(duration: 0.2)) { hand = nil }
                strokeDist = 0
                lastPoint = nil
            }
    }

    private func completePet() {
        Haptics.success()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { squash = 0.86 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { squash = 1 }
        }
        for i in 0..<5 {
            let h = Heart(x: CGFloat(i - 2) * size * 0.12 + CGFloat.random(in: -8...8))
            hearts.append(h)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeOut(duration: 1.0)) {
                    if let k = hearts.firstIndex(where: { $0.id == h.id }) { hearts[k].rise = true }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { hearts.removeAll { $0.id == h.id } }
        }
        onPet?()
    }

    private func animate() {
        bob = false
        withAnimation(.easeInOut(duration: bobSpeed).repeatForever(autoreverses: true)) { bob = true }
        shake = false
        if mood == .alarmed || mood == .worried {
            withAnimation(.easeInOut(duration: mood == .alarmed ? 0.08 : 0.14).repeatForever(autoreverses: true)) { shake = true }
        }
        badgeIn = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { badgeIn = true }
    }
}
