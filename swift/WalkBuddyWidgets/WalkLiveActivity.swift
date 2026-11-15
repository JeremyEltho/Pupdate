import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WalkBuddyWidgetsBundle: WidgetBundle {
    var body: some Widget { WalkLiveActivity() }
}

private let gold = Color(red: 1, green: 0.745, blue: 0.239)
private let alertRed = Color(red: 1, green: 0.302, blue: 0.427)
private let okGreen = Color(red: 0.243, green: 0.878, blue: 0.631)
private let night = Color(red: 0.06, green: 0.075, blue: 0.16)
private let muted = Color(red: 0.6, green: 0.63, blue: 0.79)

private func stateTint(_ s: String) -> Color { WalkStateStyle.isUrgent(s) ? alertRed : s == "calm" ? okGreen : gold }

private func spriteImage(_ name: String) -> Image {
    if let ui = UIImage(named: name) ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:)) {
        return Image(uiImage: ui)
    }
    return Image(systemName: "bird.fill")
}

struct BuddyBadge: View {
    let state: WalkActivityAttributes.ContentState
    var size: CGFloat
    var body: some View {
        ZStack(alignment: .topTrailing) {
            spriteImage(WalkStateStyle.spriteName(form: state.form)).resizable().scaledToFit()
                .frame(width: size, height: size)
            if let b = WalkStateStyle.badgeName(state: state.state) {
                spriteImage(b).resizable().scaledToFit().frame(width: size * 0.42, height: size * 0.42).offset(x: size * 0.12, y: -size * 0.08)
            }
        }
    }
}

struct Countdown: View {
    let state: WalkActivityAttributes.ContentState
    var font: Font = .system(size: 30, weight: .heavy, design: .rounded)
    var body: some View {
        if let d = state.deadline, d > Date(), state.state != "alert", state.state != "calm" {
            Text(timerInterval: Date()...d, countsDown: true)
                .font(font).monospacedDigit()
                .foregroundStyle(stateTint(state.state))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ProgressTrack: View {
    let state: WalkActivityAttributes.ContentState
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(stateTint(state.state)).frame(width: max(8, geo.size.width * state.progress))
                spriteImage("house").resizable().scaledToFit().frame(width: 18, height: 18)
                    .offset(x: geo.size.width - 14, y: 0)
            }
        }
        .frame(height: 8)
    }
}

struct WalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { ctx in
            // Lock Screen / banner
            let s = ctx.state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    BuddyBadge(state: s, size: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        Text(s.subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Countdown(state: s)
                }
                ProgressTrack(state: s)
                HStack {
                    Text("\(ctx.attributes.buddyName) is walking you to \(ctx.attributes.to)")
                    Spacer()
                    Text(s.metersLeft >= 1000 ? String(format: "%.1f km", Double(s.metersLeft) / 1000) : "\(s.metersLeft) m")
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(muted)
            }
            .padding(16)
            .activityBackgroundTint(night.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "walkbuddy://walk"))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BuddyBadge(state: s, size: 46).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s, font: .system(size: 26, weight: .heavy, design: .rounded)).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(s.title).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        Text(s.subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressTrack(state: s).padding(.horizontal, 8).padding(.top, 6)
                }
            } compactLeading: {
                BuddyBadge(state: s, size: 22)
            } compactTrailing: {
                if WalkStateStyle.needsTap(s.state), let d = s.deadline, d > Date(), s.state != "alert" {
                    Text(timerInterval: Date()...d, countsDown: true)
                        .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(stateTint(s.state)).frame(width: 38)
                } else {
                    Image(systemName: s.state == "alert" ? "exclamationmark.triangle.fill" : "figure.walk")
                        .foregroundStyle(stateTint(s.state))
                }
            } minimal: {
                BuddyBadge(state: s, size: 20)
            }
            .keylineTint(stateTint(s.state))
        }
    }
}
