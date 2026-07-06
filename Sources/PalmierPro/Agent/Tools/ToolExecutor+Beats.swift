import Foundation

extension ToolExecutor {
    fileprivate struct DetectBeatsInput: DecodableToolArgs {
        let mediaRef: String
        let clipId: String?
        let startSeconds: Double?
        let endSeconds: Double?
        static let allowedKeys: Set<String> = ["mediaRef", "clipId", "startSeconds", "endSeconds"]
    }

    private static let detectBeatsCap = 2000

    func detectBeats(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        let input: DetectBeatsInput = try decodeToolArgs(args, path: "detect_beats")
        let asset = try asset(input.mediaRef, editor: editor)
        guard asset.type == .audio || (asset.type == .video && asset.hasAudio) else {
            throw ToolError("detect_beats: asset \(asset.id) has no audio track.")
        }
        guard FileManager.default.fileExists(atPath: asset.url.path) else {
            throw ToolError("detect_beats: media file for \(asset.id) is not on disk yet. Poll get_media and retry once generationStatus becomes 'none'.")
        }

        var clip: Clip?
        if let clipId = input.clipId {
            guard let c = editor.clipFor(id: clipId) else { throw ToolError("Clip not found: \(clipId)") }
            guard c.sourceClipType != .sequence else {
                throw ToolError("detect_beats: clip \(clipId) is a nested sequence; pass a clip that references the audio asset directly.")
            }
            guard c.mediaRef == asset.id else {
                throw ToolError("detect_beats: clip \(clipId) references \(c.mediaRef), not \(asset.id).")
            }
            clip = c
        }

        let analysis = try await editor.mediaVisualCache.beats.analysisAwaiting(for: asset)
        guard !analysis.beats.isEmpty else {
            return .ok("No beats detected — the audio may be too quiet, too short, or non-rhythmic.")
        }

        var beats = analysis.beats
        if let s = input.startSeconds { beats = beats.filter { $0 >= s } }
        if let e = input.endSeconds { beats = beats.filter { $0 < e } }

        var nextStartSeconds: Double?
        if beats.count > Self.detectBeatsCap {
            nextStartSeconds = beats[Self.detectBeatsCap]
            beats = Array(beats.prefix(Self.detectBeatsCap))
        }

        var payload: [String: Any] = ["bpm": analysis.bpm]
        if let clip {
            let fps = editor.timeline.fps
            payload["clipId"] = clip.id
            payload["beatFrames"] = beats.compactMap { clip.timelineFrame(sourceSeconds: $0, fps: fps) }
        } else {
            payload["beatSeconds"] = beats
        }
        payload["beatCount"] = (payload["beatFrames"] as? [Int])?.count ?? beats.count
        if let nextStartSeconds { payload["nextStartSeconds"] = nextStartSeconds }
        return .ok(Self.jsonString(roundJSONFloatingPointNumbers(payload, toPlaces: 3)) ?? "Detected \(Int(analysis.bpm.rounded())) BPM, \(beats.count) beats.")
    }
}
