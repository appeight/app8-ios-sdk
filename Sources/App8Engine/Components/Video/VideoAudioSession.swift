import AVFoundation

/// Centralizes the engine's audio-session policy for inline video so a silent
/// background loop never interrupts whatever the device is already playing
/// (music, a podcast, another app's audio).
///
/// iOS apps default to `AVAudioSession.Category.soloAmbient`. The instant an
/// `AVPlayer` starts, it *activates* the shared session, and activating
/// `soloAmbient` deactivates every other audio source on the device. That
/// happens even when the player is muted — it's the session activation, not the
/// audio output, that silences other audio. So the engine must declare a
/// policy itself, chosen by the clip's `audioMix` (see `Video.AudioMix`).
@MainActor
enum VideoAudioSession {

    /// A resolved session policy (the DSL's `.auto` is resolved to one of these
    /// by the caller, since the mapping depends on `muted`).
    enum Policy {
        /// Mix silently alongside other audio, governed by the ringer switch.
        case mix
        /// Lower other audio while this clip plays, then restore it.
        case duck
        /// Take over device audio, stopping other sources; plays through the
        /// ringer switch.
        case interrupt
    }

    static func configure(_ policy: Policy) {
        switch policy {
        case .mix:       apply(category: .ambient, options: [.mixWithOthers])
        case .duck:      apply(category: .playback, options: [.duckOthers])
        case .interrupt: apply(category: .playback, options: [])
        }
    }

    private static func apply(category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        let session = AVAudioSession.sharedInstance()
        // Skip redundant churn — re-setting the live policy can glitch playback,
        // and `beginPlayback` runs on every start/resume/replay.
        guard session.category != category || session.categoryOptions != options else { return }
        do {
            try session.setCategory(category, options: options)
            try session.setActive(true)
        } catch {
            // Non-fatal: leave the host app's existing session policy in place.
        }
    }
}
