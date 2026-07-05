import Foundation

/// One switchable camera angle. `offsetSeconds` is where this source's t=0 sits on the
/// group timebase (the reference source's own time; the reference is 0). Stored as
/// seconds, not frames, so angle switches never accumulate frame-rate drift.
struct MulticamAngle: Codable, Sendable, Equatable {
    var mediaRef: String
    var offsetSeconds: Double = 0
    var label: String?
    var speaker: String?
}

/// Project-level metadata over ordinary clips: clips tagged with `Clip.multicamGroupId`
/// swap angles by rewriting mediaRef + trims from these offsets. No new clip type.
struct MulticamGroup: Codable, Sendable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var angles: [MulticamAngle]
    /// Master audio source; may be one of the angles or a standalone audio asset.
    var audioMediaRef: String?
    /// Offset of the master audio when it isn't an angle (reference audio = 0).
    var audioOffsetSeconds: Double = 0

    func angle(forMediaRef ref: String) -> MulticamAngle? {
        angles.first { $0.mediaRef == ref }
    }

    /// Group-time offset for any source in the group, including a non-angle master audio.
    func offsetSeconds(forMediaRef ref: String) -> Double? {
        if let angle = angle(forMediaRef: ref) { return angle.offsetSeconds }
        return ref == audioMediaRef ? audioOffsetSeconds : nil
    }

    /// Resolves an angle by mediaRef (full or prefix), label, or speaker (case-insensitive).
    func resolveAngle(_ ref: String) -> MulticamAngle? {
        if let exact = angle(forMediaRef: ref) { return exact }
        let lowered = ref.lowercased()
        if let byLabel = angles.first(where: { $0.label?.lowercased() == lowered }) { return byLabel }
        if let bySpeaker = angles.first(where: { $0.speaker?.lowercased() == lowered }) { return bySpeaker }
        let prefixed = angles.filter { $0.mediaRef.hasPrefix(ref) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    /// Display name for an angle: label, else speaker, else a short media prefix.
    static func displayName(_ angle: MulticamAngle) -> String {
        angle.label ?? angle.speaker ?? String(angle.mediaRef.prefix(8))
    }
}
