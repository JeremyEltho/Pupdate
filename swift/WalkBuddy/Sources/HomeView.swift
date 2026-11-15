import SwiftUI

struct HomeView: View {
    @ObservedObject var store: WalkerStore
    let onExit: () -> Void
    @State private var appear = false
    @State private var panel: ScreenPanel?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 ? "Late night, Jordan" : h < 12 ? "Good morning, Jordan" : h < 18 ? "Good afternoon, Jordan" : "Good evening, Jordan"
    }

    var body: some View {
        let buddy = store.user?.buddy ?? BuddyInfo(name: "Levin", xp: 90, form: "sprout")
        let streak = store.user?.streak ?? 0
        ZStack {
            Sky()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TopBar(onBack: onExit) {
                        HStack(spacing: 8) {
                            SettingsButton { panel = .settings }
                            StatChip(sprite: .fire, value: "\(streak)")
                            StatChip(sprite: .gem, value: "\(buddy.xp)", tint: Palette.gold)
                        }
                    }
                    if store.error != nil && store.user == nil {
                        Banner(text: "Can't reach the server. Go back and check the address.", alert: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(Typeface.display(32)).foregroundStyle(Palette.text)
                        Text("\(buddy.name) is ready to walk you home.").font(Typeface.body(16)).foregroundStyle(Palette.muted)
                    }

                    // Hero: the buddy on its stage.
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(RadialGradient(colors: [Color(hex: 0x2a2f78), Color(hex: 0x141a44), Palette.card], center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 260))
                            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Palette.lineTop))
                        VStack(spacing: 6) {
                            BuddyView(form: buddy.form, species: buddy.species, mood: store.happy ? .happy : .calm, size: 250, onPet: { Task { await store.pet() } })
                                .scaleEffect(appear ? 1 : 0.85).opacity(appear ? 1 : 0)
                            XPBar(buddy: buddy, next: buddy.xp < 100 ? 100 : buddy.xp < 250 ? 250 : nil)
                                .padding(.horizontal, 20).padding(.bottom, 20)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { panel = .customize } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paintbrush.pointed.fill").font(.system(size: 12, weight: .bold))
                                Text("Customize").font(Typeface.bold(13))
                            }
                            .foregroundStyle(Palette.gold)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Palette.gold.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.4)))
                        }
                        .padding(14)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 12)

                    // Primary action: looks like a search field, opens the map.
                    Button { panel = .plan(nil) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .heavy)).foregroundStyle(Palette.ink)
                                .frame(width: 46, height: 46).background(Circle().fill(Palette.gold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Where to tonight?").font(Typeface.display(21)).foregroundStyle(Palette.text)
                                Text("Pick a destination and \(buddy.name) walks with you").font(Typeface.body(14)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.muted)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.card2))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.gold.opacity(0.55), lineWidth: 1.5))
                        .shadow(color: Palette.gold.opacity(0.18), radius: 18, y: 6)
                    }
                    .buttonStyle(.plain)

                    // Quick destinations.
                    HStack(spacing: 10) {
                        QuickPlace(title: "Home", sub: "Tooker House", sprite: .house) { panel = .plan("Tooker House") }
                        QuickPlace(title: "Library", sub: "Hayden Library", sprite: .books) { panel = .plan("Hayden Library") }
                    }


                    Button { panel = .flags } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "flag.fill").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 46, height: 46).background(Circle().fill(Palette.alert))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Flagged spots").font(Typeface.displayBold(18)).foregroundStyle(Palette.text)
                                Text("Spots your circle marked Avoid or Caution. Routes steer around them").font(Typeface.body(13)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.muted)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.card2))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.lineTop))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-flags")

                    // Stats.
                    HStack(spacing: 10) {
                        StatCard(sprite: .fire, value: "\(streak)", label: "safe walks in a row")
                        StatCard(sprite: .trophy, value: "Lv \(level(buddy.xp))", label: formName(buddy.form, species: buddy.species))
                        StatCard(sprite: .shield, value: "\(store.circle.count)", label: "friends watching")
                    }

                    SafetyPowers(buddyName: buddy.name)
                    CircleCard(friends: store.circle)
                    EvolutionTrack(buddy: buddy)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) { appear = true }
            #if targetEnvironment(simulator)
            // Simulator-only: -previewPlan "<place>" opens the map page for layout checks.
            if let i = CommandLine.arguments.firstIndex(of: "-previewPlan"), i + 1 < CommandLine.arguments.count {
                panel = .plan(CommandLine.arguments[i + 1])
            }
            #endif
        }
        .fullScreenCover(item: $panel) { p in
            Group {
                switch p {
                case .settings: SettingsView(onClose: { panel = nil; Task { await store.loadCircle() } })
                case .customize:
                    CustomizeView { saved in
                        panel = nil
                        if saved != nil { Task { await store.refresh() } }
                    }
                case .plan(let preset):
                    PlanView(store: store, onClose: { panel = nil }, preset: preset)
                case .flags:
                    FlagsView(me: "jordan", onClose: { panel = nil })
                }
            }
        }
    }
}

private struct QuickPlace: View {
    let title: String
    let sub: String
    let sprite: Sprite
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                sprite.image.resizable().scaledToFit().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typeface.displayBold(16)).foregroundStyle(Palette.text)
                    Text(sub).font(Typeface.body(12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line))
        }
        .buttonStyle(.plain)
    }
}

private struct StatCard: View {
    let sprite: Sprite
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sprite.image.resizable().scaledToFit().frame(width: 34, height: 34)
            Text(value).font(Typeface.display(22)).foregroundStyle(Palette.text).monospacedDigit()
            Text(label).font(Typeface.body(12)).foregroundStyle(Palette.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line))
    }
}

/// Hatchling -> Chick -> Night Owl, with the forms not yet reached shown as silhouettes.
private struct EvolutionTrack: View {
    let buddy: BuddyInfo
    private let stages: [(form: String, xp: Int)] = [("sprout", 0), ("strider", 100), ("guardian", 250)]
    var body: some View {
        GameCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Evolution", sub: "Answer check-ins on your walks to help \(buddy.name) grow.")
                HStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { i, st in
                        let reached = buddy.xp >= st.xp
                        VStack(spacing: 6) {
                            PetImage(species: buddy.species, form: st.form, size: 62)
                                .overlay(alignment: .topTrailing) { if let g = petGear(buddy.species, st.form) { g.image.resizable().scaledToFit().frame(width: 24).offset(x: 6, y: -6) } }
                                .colorMultiply(reached ? .white : .black)
                                .opacity(reached ? 1 : 0.55)
                                .padding(8)
                                .background(Circle().fill(reached ? Palette.gold.opacity(0.16) : Color(hex: 0x0f1433)))
                                .overlay(Circle().strokeBorder(buddy.form == st.form ? Palette.gold : .clear, lineWidth: 2))
                            Text(formName(st.form, species: buddy.species)).font(Typeface.bold(13)).foregroundStyle(reached ? Palette.text : Palette.muted)
                            Text(reached ? "Unlocked" : "\(st.xp) XP").font(Typeface.body(11)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                        if i < stages.count - 1 {
                            Capsule().fill(buddy.xp >= stages[i + 1].xp ? Palette.gold : Palette.line)
                                .frame(height: 4).frame(maxWidth: 34).offset(y: -22)
                        }
                    }
                }
            }
        }
    }
}
