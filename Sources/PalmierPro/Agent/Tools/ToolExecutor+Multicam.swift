import Foundation

private struct CreateMulticamInput: DecodableToolArgs {
    struct AngleEntry: Decodable {
        let mediaRef: String
        let label: String?
        let speaker: String?
        static let allowedKeys: Set<String> = ["mediaRef", "label", "speaker"]
    }
    let name: String?
    let angles: [AngleEntry]
    let audioMediaRef: String?
    let place: Bool?
    let startFrame: Int?
    let searchWindowSeconds: Double?
    let minConfidence: Double?
    static let allowedKeys: Set<String> = [
        "name", "angles", "audioMediaRef", "place", "startFrame", "searchWindowSeconds", "minConfidence",
    ]
}

private struct SwitchAngleInput: DecodableToolArgs {
    struct SwitchEntry: Decodable {
        let startFrame: Int
        let endFrame: Int
        let angle: String?
        let layout: String?
        let angles: [String]?
        static let allowedKeys: Set<String> = ["startFrame", "endFrame", "angle", "layout", "angles"]
    }
    let groupId: String?
    let switches: [SwitchEntry]?
    let clipIds: [String]?
    let angle: String?
    let trackIndex: Int?
    static let allowedKeys: Set<String> = ["groupId", "switches", "clipIds", "angle", "trackIndex"]
}

extension ToolExecutor {

    func createMulticam(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        let input: CreateMulticamInput = try decodeToolArgs(args, path: "create_multicam")
        for (i, raw) in (args["angles"] as? [Any] ?? []).enumerated() {
            if let d = raw as? [String: Any] {
                try validateUnknownKeys(d, allowed: CreateMulticamInput.AngleEntry.allowedKeys, path: "angles[\(i)]")
            }
        }
        guard !input.angles.isEmpty else { throw ToolError("create_multicam: 'angles' must not be empty.") }

        var labels: [String: String] = [:]
        var speakers: [String: String] = [:]
        for entry in input.angles {
            if let label = entry.label { labels[entry.mediaRef] = label }
            if let speaker = entry.speaker { speakers[entry.mediaRef] = speaker }
        }

        let report: EditorViewModel.MulticamCreationReport
        do {
            report = try await editor.createMulticamGroup(
                name: input.name,
                angleMediaIds: input.angles.map(\.mediaRef),
                audioMediaId: input.audioMediaRef,
                labels: labels,
                speakers: speakers,
                searchWindowSeconds: input.searchWindowSeconds ?? EditorViewModel.AudioSyncDefaults.searchWindowSeconds,
                minConfidence: input.minConfidence ?? EditorViewModel.AudioSyncDefaults.minConfidence
            )
        } catch {
            throw ToolError("create_multicam: \(error.localizedDescription)")
        }

        var placedIds: [String] = []
        if input.place ?? true {
            do {
                placedIds = try editor.placeMulticam(
                    groupId: report.group.id,
                    atFrame: max(0, input.startFrame ?? 0)
                )
            } catch {
                throw ToolError("create_multicam: group \(report.group.id) created, but placing it failed: \(error.localizedDescription)")
            }
        }

        var payload: [String: Any] = [
            "groupId": report.group.id,
            "name": report.group.name,
            "angles": report.group.angles.map { angle -> [String: Any] in
                var entry: [String: Any] = [
                    "mediaRef": angle.mediaRef,
                    "offsetSeconds": angle.offsetSeconds.jsonRounded(toPlaces: 3),
                ]
                if let label = angle.label { entry["label"] = label }
                if let speaker = angle.speaker { entry["speaker"] = speaker }
                if let match = report.synced.first(where: { $0.mediaRef == angle.mediaRef }) {
                    entry["confidence"] = (match.confidence * 1000).rounded() / 1000
                }
                return entry
            },
        ]
        if let audioRef = report.group.audioMediaRef { payload["audioMediaRef"] = audioRef }
        if !report.failures.isEmpty {
            payload["failedAngles"] = report.failures.map { ["mediaRef": $0.mediaRef, "reason": $0.message] }
        }
        if !placedIds.isEmpty {
            payload["placedClipIds"] = placedIds
            payload["note"] = "Master audio stays one continuous clip; angle cuts only touch video. remove_words and ripple deletes keep both aligned via sync-locked tracks. Use switch_angle to change cameras."
        }
        return .ok(Self.jsonString(payload) ?? "Created multicam group \(report.group.id).")
    }

    func switchAngle(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        let input: SwitchAngleInput = try decodeToolArgs(args, path: "switch_angle")
        for (i, raw) in (args["switches"] as? [Any] ?? []).enumerated() {
            if let d = raw as? [String: Any] {
                try validateUnknownKeys(d, allowed: SwitchAngleInput.SwitchEntry.allowedKeys, path: "switches[\(i)]")
            }
        }
        let hasSwitches = !(input.switches ?? []).isEmpty
        let hasClips = !(input.clipIds ?? []).isEmpty
        guard hasSwitches != hasClips else {
            throw ToolError("switch_angle: provide exactly one of 'switches' or 'clipIds'+'angle'.")
        }

        let outcome: EditorViewModel.MulticamSwitchOutcome
        if hasClips {
            guard let angle = input.angle else {
                throw ToolError("switch_angle: 'clipIds' requires 'angle'.")
            }
            for id in input.clipIds! where editor.multicamGroup(forClip: id) == nil {
                throw ToolError("switch_angle: clip \(id) is not part of a multicam group.")
            }
            outcome = editor.switchMulticamAngle(clipIds: input.clipIds!, toAngle: angle)
        } else {
            let group = try resolveMulticamGroup(editor, id: input.groupId)
            let switches = try (input.switches ?? []).enumerated().map { i, entry -> EditorViewModel.MulticamSwitch in
                var s = EditorViewModel.MulticamSwitch(startFrame: entry.startFrame, endFrame: entry.endFrame)
                s.angle = entry.angle
                if let raw = entry.layout {
                    guard let layout = VideoLayout(rawValue: raw) else {
                        throw ToolError("switches[\(i)]: unknown layout '\(raw)'. Valid: \(VideoLayout.allCases.map(\.rawValue).joined(separator: ", "))")
                    }
                    s.layout = layout
                    s.layoutAngles = entry.angles ?? []
                }
                return s
            }
            do {
                outcome = try editor.switchMulticamAngle(groupId: group.id, switches: switches, trackIndex: input.trackIndex)
            } catch {
                throw ToolError("switch_angle: \(error.localizedDescription)")
            }
        }

        guard !outcome.switchedClipIds.isEmpty || !outcome.overlayClipIds.isEmpty else {
            throw ToolError("switch_angle: \(outcome.failures.first?.message ?? "nothing switched")")
        }

        var payload: [String: Any] = ["switchedClipIds": outcome.switchedClipIds]
        if !outcome.overlayClipIds.isEmpty {
            payload["overlayClipIds"] = outcome.overlayClipIds
            payload["note"] = "Overlay angles landed on new top tracks — track indexes shifted."
        }
        if outcome.mergedCount > 0 { payload["mergedClips"] = outcome.mergedCount }
        if !outcome.failures.isEmpty {
            payload["failed"] = outcome.failures.map { ["clipId": $0.clipId, "reason": $0.message] }
        }
        return .ok(Self.jsonString(payload) ?? "Switched \(outcome.switchedClipIds.count) clip(s).")
    }

    func deleteMulticam(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: ["groupId"], path: "delete_multicam")
        let group = try resolveMulticamGroup(editor, id: args["groupId"] as? String, toolName: "delete_multicam")
        do {
            try editor.deleteMulticamGroup(id: group.id)
        } catch {
            throw ToolError("delete_multicam: \(error.localizedDescription)")
        }
        return .ok("Deleted multicam group '\(group.name)' (\(group.id)). Its clips keep their cuts and angles but are no longer switchable.")
    }

    private func resolveMulticamGroup(_ editor: EditorViewModel, id: String?, toolName: String = "switch_angle") throws -> MulticamGroup {
        if let id {
            guard let group = editor.multicamGroup(id: id) else {
                throw ToolError("\(toolName): multicam group not found: \(id)")
            }
            return group
        }
        switch editor.multicamGroups.count {
        case 0: throw ToolError("\(toolName): no multicam groups in this project. Create one with create_multicam.")
        case 1: return editor.multicamGroups[0]
        default: throw ToolError("\(toolName): several multicam groups exist — pass groupId.")
        }
    }
}
