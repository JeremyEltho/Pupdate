import SwiftUI

struct BuddyView: View {
    let form: String
    let mood: Mood
    var size: CGFloat = 240
    var pedestal = true
    var onPet: (() -> Void)?
    var onDuress: (() -> Void)?

    @State private var bob = false
    @State private var squish = false
    @State private var shake = false
    @State private var badgeIn = false

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

    var body: some View {
        let sprite = size * 0.74
        ZStack(alignment: .bottom) {
            if pedestal {
                // Glow pool and a little stage disc.
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
            formSprite(form).image
                .resizable().scaledToFit()
                .frame(width: sprite, height: sprite)
                .shadow(color: glow.opacity(0.35), radius: 24, y: 6)
                .scaleEffect(x: squish ? 1.12 : 1, y: squish ? 0.84 : 1, anchor: .bottom)
                .rotationEffect(.degrees(shake ? 7 : 0), anchor: .bottom)
                .offset(y: -size * 0.1 - (bob ? (mood == .alarmed ? 5 : 14) : 0))
                .id(form) // new form pops in on evolution
                .transition(.scale(scale: 0.3).combined(with: .opacity))
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
        .onTapGesture {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { squish = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { squish = false }
            }
            onPet?()
        }
        .onLongPressGesture(minimumDuration: 2) { onDuress?() }
        .accessibilityElement()
        .accessibilityLabel("Your buddy")
        .accessibilityHint("Tap to pet")
        .accessibilityAddTraits(.isButton)
        .onAppear { animate() }
        .onChange(of: mood) { _, _ in animate() }
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
