import ActivityKit
import Foundation

/// Shared between the app and the widget extension: what the Lock Screen / Dynamic Island shows.
struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var state: String          // calm, checkin, nudge, final, countdown, alert
        var title: String
        var subtitle: String
        var deadline: Date?        // when the current stage times out (drives a self-ticking timer)
        var form: String           // sprout, strider, guardian
        var xp: Int
        var progress: Double       // 0...1 along the route
        var metersLeft: Int
    }

    var walkerName: String
    var buddyName: String
    var from: String
    var to: String
}

enum WalkStateStyle {
    static func isUrgent(_ s: String) -> Bool { ["final", "countdown", "alert"].contains(s) }
    static func needsTap(_ s: String) -> Bool { s != "calm" }
    static func spriteName(form: String) -> String {
        switch form { case "strider": return "front-facing_baby_chick"; case "guardian": return "owl"; default: return "hatching_chick" }
    }
    static func badgeName(state: String) -> String? {
        switch state {
        case "checkin": return "red_question_mark"
        case "nudge", "final": return "sweat_droplets"
        case "countdown", "alert": return "red_exclamation_mark"
        default: return nil
        }
    }
}
