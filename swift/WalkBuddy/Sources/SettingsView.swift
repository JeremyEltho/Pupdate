import SwiftUI

struct SettingsView: View {
    let onClose: () -> Void
    @AppStorage("wb.role") private var role = ""
    @AppStorage("wb.routePref") private var routePref = "safe"
    @AppStorage("wb.demoDefault") private var demoDefault = true
    @AppStorage("wb.liveActivity") private var liveActivity = true
    @AppStorage("wb.haptics") private var haptics = true
    @AppStorage("wb.satellite") private var satellite = true
    @AppStorage("wb.speak") private var speak = false
    @AppStorage("wb.sounds") private var sounds = true
    @AppStorage("wb.strongVibe") private var strongVibe = true
    @AppStorage("wb.petStyle") private var petStyle = "rub"
    @AppStorage("wb.reduceMotion") private var reduceMotion = false
    @AppStorage("wb.textScale") private var textScale = 1.0
    @State private var friends: [FriendInfo] = []
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var friendError: String?
    @AppStorage("wb.checkinEvery") private var checkinEvery = 0
    @AppStorage("wb.watchRoute") private var watchRoute = true
    @AppStorage("wb.watchSpeed") private var watchSpeed = true
    @State private var server = API.shared.base
    @State private var status: String?
    @State private var busy = false
    @State private var resetDone = false
    @State private var customizing = false

    var body: some View {
        ZStack {
            Sky()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Settings").font(Typeface.display(34)).foregroundStyle(Palette.text)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.muted)
                                .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.07)))
                        }
                        .accessibilityLabel("Close settings")
                    }
                    .padding(.top, 8)

                    if role != "friend" {
                        group("Your buddy") {
                            GameButton(title: "Change pet and name", kind: .ghost) { customizing = true }
                            Text("Pick a pup, kitty, bunny, otter, sloth and more. Your friends see your pet too.")
                                .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        }
                    }

                    group("Check-ins") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Levin checks in").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                            HStack(spacing: 6) {
                                ForEach([(0, "Only if off"), (300, "5 min"), (600, "10 min"), (900, "15 min")], id: \.0) { v, label in
                                    choice(label, icon: v == 0 ? "exclamationmark.triangle.fill" : "clock.fill", on: checkinEvery == v, tint: Palette.gold) { checkinEvery = v }
                                }
                            }
                            Text(checkinEvery == 0 ? "Levin only checks in when something looks off." : "Every \(checkinEvery / 60) minutes, plus whenever something looks off.")
                                .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        }
                        divider
                        toggle("Leaving your route", "Check in if you're more than 60 m off your route for a minute", $watchRoute)
                        divider
                        toggle("Odd speed", "Check in if you move at car speed or stop for 5 minutes", $watchSpeed)
                        divider
                        VStack(alignment: .leading, spacing: 6) {
                            Text("If you don't answer").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                            Text("Check-in 30 s, nudge 30 s, last chance 30 s, countdown 20 s, then Maya and Sam get an alert. No phone check-in for 90 s also alerts them.")
                                .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        }
                    }

                    group("Walking") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default route").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                            HStack(spacing: 8) {
                                choice("Safer", icon: "shield.lefthalf.filled", on: routePref == "safe", tint: Palette.ok) { routePref = "safe" }
                                choice("Quickest", icon: "bolt.fill", on: routePref == "quick", tint: Palette.gold) { routePref = "quick" }
                            }
                            Text("Safer favors main streets and fewer turns. It's a guide, not a guarantee.")
                                .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        }
                        divider
                        toggle("Start planned walks as demos", "Simulate the walk at 2x instead of using GPS", $demoDefault)
                    }

                    group("On your phone") {
                        toggle("Lock Screen Live Activity", "Your walk and Levin on the Lock Screen and Dynamic Island", $liveActivity)
                        divider
                        toggle("Haptics", "Buzz when Levin checks in or an alert arrives", $haptics)
                        divider
                        toggle("Satellite map", "Real aerial imagery in 3D. Off for the dark map", $satellite)
                    }

                    group("Accessibility") {
                        toggle("Spoken prompts", "Read check-ins and alerts out loud", $speak)
                        divider
                        toggle("Sounds", "A chime for check-ins and an alarm for alerts", $sounds)
                        divider
                        toggle("Strong vibration for alerts", "Keeps buzzing until the alert is handled", $strongVibe)
                        divider
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How to pet").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                            HStack(spacing: 8) {
                                choice("Rub", icon: "hand.draw.fill", on: petStyle == "rub", tint: Palette.gold) { petStyle = "rub" }
                                choice("Tap", icon: "hand.tap.fill", on: petStyle == "tap", tint: Palette.gold) { petStyle = "tap" }
                            }
                            Text("Tap is easier if rubbing the screen is hard. Holding still for 2 seconds is always the silent alert.")
                                .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        }
                        divider
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Text size").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                            HStack(spacing: 8) {
                                choice("Default", icon: "textformat.size.smaller", on: textScale == 1.0, tint: Palette.gold) { textScale = 1.0 }
                                choice("Large", icon: "textformat.size", on: textScale == 1.15, tint: Palette.gold) { textScale = 1.15 }
                                choice("Largest", icon: "textformat.size.larger", on: textScale == 1.3, tint: Palette.gold) { textScale = 1.3 }
                            }
                            Text("Also follows your iPhone's text size.").font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        }
                        divider
                        toggle("Reduce motion", "Stop the bouncing and shaking (also follows your iPhone setting)", $reduceMotion)
                    }

                    group("Your circle") {
                        if friends.isEmpty {
                            Text("Nobody gets your alerts yet. Add someone below.").font(Typeface.body(13)).foregroundStyle(Palette.alert)
                        }
                        ForEach(friends) { f in
                            HStack(spacing: 12) {
                                Text(String(f.name.prefix(1))).font(Typeface.display(17)).foregroundStyle(Palette.ink)
                                    .frame(width: 38, height: 38).background(Circle().fill(avatarColor(f.id)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).font(Typeface.semi(16)).foregroundStyle(Palette.text)
                                    Text(f.phone.isEmpty ? "No phone number" : f.phone).font(Typeface.body(12)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Button {
                                    Task {
                                        try? await API.shared.removeFriend("jordan", f.id)
                                        await loadFriends()
                                    }
                                } label: {
                                    Text("Remove").font(Typeface.bold(13)).foregroundStyle(Palette.alert)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(Palette.alert.opacity(0.12)))
                                }
                                .accessibilityLabel("Remove \(f.name) from your circle")
                            }
                            divider
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a friend").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                            field("Name", text: $newName, keyboard: .default)
                            field("Phone (for the Call button)", text: $newPhone, keyboard: .phonePad)
                            GameButton(title: "Add to circle", kind: .ghost) {
                                Task {
                                    do {
                                        _ = try await API.shared.addFriend("jordan", name: newName, phone: newPhone)
                                        newName = ""; newPhone = ""; friendError = nil
                                        await loadFriends()
                                    } catch { friendError = error.localizedDescription }
                                }
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            if let friendError { Text(friendError).font(Typeface.body(12.5)).foregroundStyle(Palette.alert) }
                        }
                        Text("Everyone here gets your alerts. Only they can close one.")
                            .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                    }

                    group("Server") {
                        TextField("https://something.trycloudflare.com", text: $server)
                            .font(Typeface.body(15)).foregroundStyle(Palette.text)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0b1030)))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                        HStack(spacing: 12) {
                            GameButton(title: "Save and test", kind: .ghost, busy: busy) {
                                Task {
                                    API.shared.base = server
                                    busy = true
                                    do { _ = try await API.shared.health(); status = "Connected" } catch { status = "Can't reach it" }
                                    busy = false
                                }
                            }
                            Text(status ?? "").font(Typeface.bold(14)).foregroundStyle(status == "Connected" ? Palette.ok : Palette.alert)
                                .frame(width: 110, alignment: .leading)
                        }
                    }

                    group("Demo") {
                        GameButton(title: resetDone ? "Demo reset" : "Reset demo", kind: .ghost) {
                            Task {
                                try? await API.shared.demo("reset")
                                resetDone = true
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                resetDone = false
                            }
                        }
                        Text("Restores Levin to 90 XP, the streak and the friends list, and clears walks and alerts.")
                            .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                        divider
                        GameButton(title: "Switch role (now: \(role == "friend" ? "friend" : "walker"))", kind: .ghost) {
                            onClose()
                            role = ""
                        }
                    }

                    group("Privacy") {
                        Label("Your location is shared only while a walk is running.", systemImage: "location.slash")
                        Label("A silent alert never shows on your own screen.", systemImage: "eye.slash")
                    }
                    .font(Typeface.body(14)).foregroundStyle(Palette.text)

                    group("About") {
                        Text("WalkBuddy, built at SunHacks 2026.").font(Typeface.semi(15)).foregroundStyle(Palette.text)
                        Text("3D sprites: Microsoft Fluent Emoji (MIT). Fonts: Bricolage Grotesque and Figtree (SIL OFL). Maps and directions: Apple MapKit.")
                            .font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
            }
        }
        .task { await loadFriends() }
        .sheet(isPresented: $customizing) {
            CustomizeView { _ in customizing = false }.presentationBackground(Palette.bg)
        }
    }

    private func loadFriends() async {
        if let f = try? await API.shared.circle("jordan") { friends = f }
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .font(Typeface.body(15)).foregroundStyle(Palette.text)
            .keyboardType(keyboard).autocorrectionDisabled()
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0b1030)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
            .accessibilityLabel(placeholder)
    }

    private var divider: some View { Rectangle().fill(Palette.line).frame(height: 1) }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typeface.displayBold(17)).foregroundStyle(Palette.text).padding(.leading, 4)
            GameCard { VStack(alignment: .leading, spacing: 12) { content() } }
        }
    }

    private func toggle(_ title: String, _ sub: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typeface.semi(15)).foregroundStyle(Palette.text)
                Text(sub).font(Typeface.body(12.5)).foregroundStyle(Palette.muted)
            }
        }
        .tint(Palette.gold)
    }

    private func choice(_ title: String, icon: String, on: Bool, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(Typeface.bold(13)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(on ? tint : Palette.muted)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? tint.opacity(0.14) : Color(hex: 0x0f1433)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? tint : Palette.line, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func avatarColor(_ id: String) -> Color {
        let colors: [Color] = [Color(hex: 0xff8fb1), Color(hex: 0x7ad7ff), Color(hex: 0xb4f08a), Color(hex: 0xffd27a), Color(hex: 0xc9a7ff)]
        return colors[abs(id.hashValue) % colors.count]
    }

    private func circleRow(_ name: String, _ initial: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(initial).font(Typeface.display(17)).foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38).background(Circle().fill(color))
            Text(name).font(Typeface.semi(16)).foregroundStyle(Palette.text)
            Spacer()
            Pill(text: "Gets alerts", tint: Palette.ok)
        }
    }
}

/// Gear button. The sheet itself lives on the screen (see ScreenPanel) so polling re-renders can't dismiss it.
struct SettingsButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.muted)
                .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(.white.opacity(0.09)))
        }
        .accessibilityLabel("Settings")
    }
}

/// Which full-screen panel a screen is showing. Exactly one presenter per screen, driven by one
/// value, so a re-render can never make two presentation modifiers fight and dismiss each other.
enum ScreenPanel: Identifiable, Equatable {
    case settings, customize, plan(String?)
    var id: String {
        switch self {
        case .settings: return "settings"
        case .customize: return "customize"
        case .plan(let p): return "plan-\(p ?? "")"
        }
    }
}
