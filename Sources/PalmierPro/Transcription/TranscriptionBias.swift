// Glossary hotword registry, retained for legacy cache-read fallback only.
// Engines no longer consume hotwords: prompt biasing on the 0.6B qwen3 model measurably
// perturbed unrelated recognition, so decode output must be a pure function of audio + model.
// Corrections apply at read-time materialisation. TranscriptCache still reads the fingerprint
// to find pre-existing salted entries. §4
import Foundation
import Synchronization

enum TranscriptionBias {
    private struct State: Sendable {
        var hotwords: [String] = []
        var fingerprint: String?
    }

    private static let state = Mutex(State())

    /// Cache-key salt; nil when no bias is active so unbiased cache keys stay byte-identical.
    static var fingerprint: String? {
        state.withLock { $0.fingerprint }
    }

    static func update(hotwords: [String], fingerprint: String) {
        state.withLock {
            $0.hotwords = hotwords
            $0.fingerprint = hotwords.isEmpty ? nil : fingerprint
        }
    }
}
