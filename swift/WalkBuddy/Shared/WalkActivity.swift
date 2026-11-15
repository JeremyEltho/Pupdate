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
        var species: String        // chick, dog, cat, ...
        var xp: Int
        var progress: Double       // 0...1 along the route
        var metersLeft: Int
        var turnText: String? = nil     // next turn-by-turn instruction
        var turnSymbol: String? = nil   // SF Symbol for the maneuver
        var turnMeters: Int? = nil
    }

    var walkerName: String
    var buddyName: String
    var from: String
    var to: String
}

enum WalkStateStyle {
    static func isUrgent(_ s: String) -> Bool { ["final", "countdown", "alert"].contains(s) }
    static func needsTap(_ s: String) -> Bool { s != "calm" }
    static func spriteName(form: String, species: String = "chick") -> String {
        let pets = ["dog": "pet_dog", "cat": "pet_cat", "bunny": "pet_rabbit", "poodle": "pet_poodle", "hedgehog": "pet_hedgehog",
                    "chipmunk": "pet_chipmunk", "otter": "pet_otter", "seal": "pet_seal", "sloth": "pet_sloth",
                    "turtle": "pet_turtle", "penguin": "penguin"]
        if let p = pets[species] { return p }
        switch form { case "strider": return "front-facing_baby_chick"; case "guardian": return "owl"; default: return "hatching_chick" }
    }
    static func gearName(form: String, species: String) -> String? {
        guard species != "chick" else { return nil }
        switch form { case "strider": return "glowing_star"; case "guardian": return "crown"; default: return nil }
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
