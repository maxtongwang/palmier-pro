import Foundation

struct MulticamSource: Codable, Sendable, Equatable {
    enum MemberKind: String, Codable, Sendable {
        case angle
        case mic
        case both
    }

    struct SyncMap: Codable, Sendable, Equatable {
        /// Group time at which this member's source t=0 sits.
        var offsetSeconds: Double = 0
        /// Correlation confidence; 1 for the master, 0 = unsynced and unusable as an angle.
        var confidence: Double = 0
        /// Pinned by user/agent.
        var locked: Bool = false
    }

    struct Member: Codable, Sendable, Equatable, Identifiable {
        var id: String = UUID().uuidString
        var mediaRef: String
        var kind: MemberKind
        var angleLabel: String
        var sync: SyncMap = SyncMap()

        var providesVideo: Bool { kind != .mic }
        var providesAudio: Bool { kind != .angle }
        var usable: Bool { sync.confidence > 0 || sync.locked }
    }

    var members: [Member] = []
    var masterMemberId: String = ""
    var programTrackId: String = ""
    var overlayTrackIds: [String] = []

    var master: Member? { members.first { $0.id == masterMemberId } }
    var angles: [Member] { members.filter { $0.providesVideo && $0.usable } }
    var mics: [Member] { members.filter(\.providesAudio) }

    func member(labeled label: String) -> Member? {
        members.first { $0.angleLabel.caseInsensitiveCompare(label) == .orderedSame }
    }
}

extension MulticamSource.Member {
    /// Seconds into this member's source file for a given group time.
    func sourceSeconds(atGroupSeconds t: Double) -> Double {
        t - sync.offsetSeconds
    }

    /// Child frames [start, end) where this member has content.
    func coverage(sourceDuration: Double, fps: Int) -> Range<Int> {
        let start = Int((sync.offsetSeconds * Double(fps)).rounded())
        let end = Int(((sync.offsetSeconds + sourceDuration) * Double(fps)).rounded())
        return start..<max(start, end)
    }

    /// Source trim (frames at child fps) for a clip starting at `childFrame`.
    func trimFrame(atChildFrame childFrame: Int, fps: Int) -> Int {
        Int((sourceSeconds(atGroupSeconds: Double(childFrame) / Double(fps)) * Double(fps)).rounded())
    }
}
