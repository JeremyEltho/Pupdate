import AudioToolbox
import AVFoundation
import UIKit

/// Sound, speech and vibration, each switchable in Settings > Accessibility.
enum Feedback {
    private static let voice = AVSpeechSynthesizer()
    private static func flag(_ key: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? def }

    static var speakOn: Bool { flag("wb.speak", false) }
    static var soundsOn: Bool { flag("wb.sounds", true) }
    static var strongVibration: Bool { flag("wb.strongVibe", true) }

    /// Read text aloud (spoken prompts). Ducks other audio briefly.
    static func speak(_ text: String) {
        guard speakOn, !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        voice.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        voice.speak(u)
    }

    static func checkInChime() {
        if soundsOn { AudioServicesPlaySystemSound(1007) }
        Haptics.warning()
    }

    static func alertSound() {
        if soundsOn { AudioServicesPlaySystemSound(1005) }
        if strongVibration { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) } else { Haptics.warning() }
    }

    static func petted() {
        if soundsOn { AudioServicesPlaySystemSound(1104) }
        Haptics.success()
    }
}
