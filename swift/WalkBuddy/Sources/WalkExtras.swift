import SwiftUI

func turnSymbol(_ m: String) -> String {
    switch m {
    case "left": return "arrow.turn.up.left"
    case "right": return "arrow.turn.up.right"
    case "slight_left": return "arrow.up.left"
    case "slight_right": return "arrow.up.right"
    case "uturn": return "arrow.uturn.down"
    case "arrive": return "flag.checkered"
    default: return "arrow.up"
    }
}

func formatMeters(_ m: Int) -> String { m >= 1000 ? String(format: "%.1f km", Double(m) / 1000) : "\(m) m" }

/// "In 80 m, turn left onto E University Dr", with the buddy cheering at the turn itself.
struct NextTurnCard: View {
    let turn: NextTurn
    var buddyName = "Levin"
    var species: String? = "chick"
    var form = "sprout"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: turnSymbol(turn.maneuver))
                .font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.ink)
                .frame(width: 62, height: 62)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(turn.near ? Palette.gold : Palette.sky))
                .scaleEffect(turn.near && !Motion.reduced ? 1.06 : 1)
                .animation(Motion.reduced ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: turn.near)
            VStack(alignment: .leading, spacing: 3) {
                Text(turn.near ? (turn.maneuver == "arrive" ? "Almost there!" : "Turn here") : "In \(formatMeters(turn.inM))")
                    .font(Typeface.display(24)).foregroundStyle(turn.near ? Palette.gold : Palette.text)
                    .contentTransition(.numericText())
                Text(turn.text).font(Typeface.semi(15)).foregroundStyle(Palette.text).lineLimit(2)
                if turn.near {
                    HStack(spacing: 5) {
                        petSprite(species, form).image.resizable().scaledToFit().frame(width: 18, height: 18)
                        Text(buddyLine).font(Typeface.body(13)).foregroundStyle(Palette.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.card2))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(turn.near ? Palette.gold : Palette.lineTop, lineWidth: turn.near ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(turn.near ? "Turn here: \(turn.text)" : "In \(formatMeters(turn.inM)), \(turn.text)")
        .accessibilityIdentifier("next-turn")
    }

    private var buddyLine: String {
        switch turn.maneuver {
        case "left", "slight_left": return "\(buddyName): this way, turn left!"
        case "right", "slight_right": return "\(buddyName): over here, turn right!"
        case "arrive": return "\(buddyName): we made it!"
        default: return "\(buddyName): keep going straight!"
        }
    }
}

func paceModeText(_ m: String?) -> (String, String, Color) {
    switch m {
    case "vehicle": return ("In a vehicle", "car.fill", Palette.alert)
    case "running": return ("Running", "figure.run", Palette.warn)
    case "still": return ("Standing still", "figure.stand", Palette.muted)
    case "walking": return ("Walking", "figure.walk", Palette.ok)
    default: return ("Measuring pace", "figure.walk", Palette.muted)
    }
}

/// Live pace: mode, speed, a small speed trace, and Gemini's read when it judged something.
struct PaceCard: View {
    let pace: PaceInfo
    var body: some View {
        let (label, icon, tint) = paceModeText(pace.mode)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 36, height: 36).background(Circle().fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(Typeface.displayBold(17)).foregroundStyle(Palette.text)
                    Text(pace.kmh.map { String(format: "%.1f km/h", $0) } ?? "Waiting for movement")
                        .font(Typeface.body(13)).foregroundStyle(Palette.muted).monospacedDigit()
                }
                Spacer()
                if pace.judging {
                    HStack(spacing: 5) { ProgressView().tint(Palette.gold).scaleEffect(0.7); Text("Gemini is checking").font(Typeface.bold(11)) }
                        .foregroundStyle(Palette.gold)
                } else if pace.pattern != "steady" {
                    Pill(text: patternText(pace.pattern), tint: Palette.warn)
                } else {
                    Pill(text: "Steady", tint: Palette.ok)
                }
            }
            Sparkline(values: pace.samples, tint: tint).frame(height: 34)
                .accessibilityHidden(true)
            if let note = pace.note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: pace.source == "gemini" ? "sparkles" : "ruler").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(pace.source == "gemini" ? Palette.gold : Palette.muted)
                    Text(note).font(Typeface.body(13)).foregroundStyle(Palette.text)
                }
            }
            Text("Your pace is watched for running, stop-and-go, turning back and car speed. Gemini decides when it's worth a check-in.")
                .font(Typeface.body(11.5)).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pace-card")
    }

    private func patternText(_ p: String) -> String {
        switch p {
        case "running": return "Running"
        case "stop_and_go": return "Stop and go"
        case "backtracking": return "Turned back"
        case "sudden_stop": return "Sudden stop"
        case "vehicle": return "Car speed"
        default: return p
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint: Color = Palette.gold
    var body: some View {
        GeometryReader { geo in
            let maxV = max(4.0, values.max() ?? 1)
            Path { p in
                guard values.count > 1 else { return }
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                    let y = geo.size.height * (1 - CGFloat(min(v, maxV) / maxV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Heads-up for a flag the walker is near or inside.
struct FlagAheadBanner: View {
    let flag: FlagBrief
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: flag.status == "avoid" ? "nosign" : "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(Circle().fill(flagTint(flag.status)))
            VStack(alignment: .leading, spacing: 2) {
                Text(flag.inside == true ? "You're in a flagged spot" : "Flagged spot \(formatMeters(flag.inM ?? 0)) ahead")
                    .font(Typeface.displayBold(16)).foregroundStyle(Palette.text)
                Text("\(flag.byName): \(flag.reason)\(flag.note.map { $0.isEmpty ? "" : ". \($0)" } ?? "")")
                    .font(Typeface.body(13)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(flagTint(flag.status).opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(flagTint(flag.status).opacity(0.6)))
        .accessibilityElement(children: .combine)
    }
}

/// Warnings that were also sent to friends: long check-in gaps, check-ins off, slow alerts, car speed.
struct NoticeList: View {
    let notices: [Notice]
    var friendView = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(notices.enumerated()), id: \.offset) { _, n in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(n.kind)).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.warn)
                        .frame(width: 28, height: 28).background(Circle().fill(Palette.warn.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.text).font(Typeface.body(13.5)).foregroundStyle(Palette.text)
                        if !friendView { Text("Your circle was told.").font(Typeface.body(11.5)).foregroundStyle(Palette.muted) }
                    }
                }
            }
        }
        .accessibilityIdentifier("notices")
    }
    private func icon(_ k: String) -> String {
        switch k {
        case "checkins_off": return "bell.slash.fill"
        case "long_checkins": return "clock.badge.exclamationmark"
        case "slow_alerts": return "hourglass"
        case "in_vehicle": return "car.fill"
        default: return "exclamationmark.circle.fill"
        }
    }
}

/// One-phone testing: trigger every safety feature from the walker's own phone during a demo walk.
struct TestToolsCard: View {
    let walk: Walk
    let flagHere: () -> Void
    @State private var busy: String?
    @State private var msg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Test tools", sub: "Try every feature from this phone. The demo walker moves at 2x; you still do all the petting.")
            Text("Pace (Gemini decides)").font(Typeface.semi(13)).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                tool("Run", "figure.run", "pace-run") { try await API.shared.demo("pace", ["mode": "run"]) }
                tool("Stop & go", "pause.fill", "pace-stopgo") { try await API.shared.demo("pace", ["mode": "stop_go"]) }
            }
            HStack(spacing: 8) {
                tool("Turn back", "arrow.uturn.backward", "pace-back") { try await API.shared.demo("pace", ["mode": "backtrack"]) }
                tool("Car speed", "car.fill", "pace-car") { try await API.shared.demo("pace", ["mode": "car"]) }
            }
            Text("Check-ins and alerts").font(Typeface.semi(13)).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                tool("Check in now", "questionmark.bubble.fill", "ci") { try await API.shared.demo("checkin") }
                tool("Stop answering", "hand.raised.slash.fill", "stop") { try await API.shared.demo("stop-answering") }
            }
            HStack(spacing: 8) {
                tool("Go off route", "arrow.triangle.branch", "dev") { try await API.shared.demo("deviate") }
                Button(action: flagHere) { label("Flag this spot", "flag.fill") }.buttonStyle(.plain)
            }
            if let msg { Text(msg).font(Typeface.body(12)).foregroundStyle(Palette.muted) }
            Text("To see what friends get: Settings > Switch role > Friend. Alerts wait there for you.")
                .font(Typeface.body(11.5)).foregroundStyle(Palette.muted)
        }
        .accessibilityIdentifier("test-tools")
    }

    private func tool(_ title: String, _ icon: String, _ key: String, _ run: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                busy = key
                do { try await run(); msg = "\(title): sent." } catch { msg = error.localizedDescription }
                busy = nil
                Haptics.tap()
            }
        } label: { label(title, icon, busy == key) }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func label(_ title: String, _ icon: String, _ spinning: Bool = false) -> some View {
        HStack(spacing: 6) {
            if spinning { ProgressView().scaleEffect(0.7).tint(Palette.gold) } else { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
            Text(title).font(Typeface.bold(13)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0f1433)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }
}
