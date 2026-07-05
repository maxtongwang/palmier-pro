import Foundation

struct MulticamError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Multicam: groups of sources aligned on a shared timebase. Clips stay ordinary `Clip`s
/// tagged with `multicamGroupId`; switching angles rewrites mediaRef + trims from the
/// group's per-source offsets (stored in seconds, so no frame-rate drift accumulates).
extension EditorViewModel {

    struct MulticamCreationReport: Sendable {
        var group: MulticamGroup
        var synced: [(mediaRef: String, offsetSeconds: Double, confidence: Double)] = []
        var failures: [(mediaRef: String, message: String)] = []
    }

    struct MulticamSwitchOutcome: Sendable {
        var switchedClipIds: [String] = []
        var overlayClipIds: [String] = []
        var mergedCount: Int = 0
        var failures: [(clipId: String, message: String)] = []
    }

    /// One switch instruction: a range plus either a single full-frame angle or a
    /// layout with one angle per slot (slot order follows `VideoLayout.slots`).
    struct MulticamSwitch: Sendable {
        var startFrame: Int
        var endFrame: Int
        var angle: String?
        var layout: VideoLayout?
        var layoutAngles: [String] = []
    }

    // MARK: - Lookup

    func multicamGroup(id: String) -> MulticamGroup? {
        multicamGroups.first { $0.id == id || $0.id.hasPrefix(id) }
    }

    func multicamGroup(forClip clipId: String) -> MulticamGroup? {
        guard let clip = clipFor(id: clipId), let gid = clip.multicamGroupId else { return nil }
        return multicamGroup(id: gid)
    }

    /// Group id an untagged clip belongs to through a linked partner (the master audio
    /// clip isn't tagged itself but its source is a group member).
    func multicamPartnerGroupId(of clip: Clip) -> String? {
        guard clip.multicamGroupId == nil, clip.linkGroupId != nil else { return nil }
        for partnerId in linkedPartnerIds(of: clip.id) {
            if let gid = clipFor(id: partnerId)?.multicamGroupId,
               let group = multicamGroup(id: gid),
               group.offsetSeconds(forMediaRef: clip.mediaRef) != nil {
                return gid
            }
        }
        return nil
    }

    // MARK: - Group creation (from media, offsets by audio correlation)

    /// Aligns every angle to the reference source (the master audio when given, else the
    /// first angle) by envelope cross-correlation and stores the lags as group offsets.
    func createMulticamGroup(
        name: String?,
        angleMediaIds: [String],
        audioMediaId: String? = nil,
        labels: [String: String] = [:],
        speakers: [String: String] = [:],
        searchWindowSeconds: Double = AudioSyncDefaults.searchWindowSeconds,
        minConfidence: Double = AudioSyncDefaults.minConfidence
    ) async throws -> MulticamCreationReport {
        guard Set(angleMediaIds).count == angleMediaIds.count else {
            throw MulticamError("Duplicate media in angles.")
        }
        var angleAssets: [MediaAsset] = []
        for id in angleMediaIds {
            guard let asset = mediaAssets.first(where: { $0.id == id }) else {
                throw MulticamError("Media asset not found: \(id)")
            }
            guard asset.type == .video else {
                throw MulticamError("Angle \(id) is \(asset.type.rawValue); multicam angles must be video.")
            }
            angleAssets.append(asset)
        }

        var audioAsset: MediaAsset?
        if let audioMediaId {
            guard let asset = mediaAssets.first(where: { $0.id == audioMediaId }) else {
                throw MulticamError("Audio media asset not found: \(audioMediaId)")
            }
            guard asset.type == .audio || (asset.type == .video && asset.hasAudio) else {
                throw MulticamError("Audio source \(audioMediaId) has no audio track.")
            }
            audioAsset = asset
        }

        let reference = audioAsset ?? angleAssets[0]
        guard reference.hasAudio || reference.type == .audio else {
            throw MulticamError("Reference source \(reference.id) has no audio to sync against.")
        }
        guard let refEnvelope = try? await AudioEnvelopeExtractor.extract(from: reference.url),
              !refEnvelope.samples.isEmpty else {
            throw MulticamError("Could not read audio from the reference source \(reference.id).")
        }

        let maxLag = max(1, Int((searchWindowSeconds / AudioEnvelopeExtractor.hopSeconds).rounded()))
        var report = MulticamCreationReport(group: MulticamGroup(name: "", angles: []))
        var angles: [MulticamAngle] = []

        for asset in angleAssets {
            var angle = MulticamAngle(
                mediaRef: asset.id,
                label: labels[asset.id],
                speaker: speakers[asset.id]
            )
            if asset.id == reference.id {
                angles.append(angle)
                report.synced.append((asset.id, 0, 1))
                continue
            }
            guard asset.hasAudio else {
                report.failures.append((asset.id, "No audio track — can't align this angle automatically."))
                continue
            }
            guard let envelope = try? await AudioEnvelopeExtractor.extract(from: asset.url),
                  !envelope.samples.isEmpty else {
                report.failures.append((asset.id, "Could not read audio."))
                continue
            }
            let refSamples = refEnvelope.samples
            let targetSamples = envelope.samples
            let match = await Task.detached(priority: .userInitiated) {
                AudioSyncCorrelator.correlate(reference: refSamples, target: targetSamples, maxLagHops: maxLag)
            }.value
            guard let match, match.confidence >= minConfidence else {
                report.failures.append((asset.id, "No confident alignment — sources may not overlap within the search window."))
                continue
            }
            angle.offsetSeconds = Double(match.lagHops) * AudioEnvelopeExtractor.hopSeconds
            angles.append(angle)
            report.synced.append((asset.id, angle.offsetSeconds, match.confidence))
        }

        guard angles.count >= 2 || (angles.count == 1 && audioAsset != nil) else {
            let detail = report.failures.map { "\($0.mediaRef): \($0.message)" }.joined(separator: "; ")
            throw MulticamError("Not enough angles aligned to form a multicam group. \(detail)")
        }

        var group = MulticamGroup(
            name: name ?? nextMulticamGroupName(),
            angles: angles,
            audioMediaRef: audioAsset?.id ?? reference.id
        )
        group.audioOffsetSeconds = group.audioMediaRef.flatMap { ref in
            angles.first { $0.mediaRef == ref }?.offsetSeconds
        } ?? 0
        report.group = group
        addMulticamGroup(group)
        return report
    }

    /// Creates a group from clips already aligned on the timeline (offsets read from their
    /// current placement). Requires speed 1 on every clip.
    @discardableResult
    func createMulticamGroupFromClips(ids: Set<String>) throws -> MulticamGroup {
        let fps = Double(timeline.fps)
        var videoClips: [Clip] = []
        var audioClips: [Clip] = []
        for track in timeline.tracks {
            for clip in track.clips where ids.contains(clip.id) {
                guard clip.sourceClipType != .sequence, clip.mediaType == .video || clip.mediaType == .audio else { continue }
                guard clip.speed == 1.0 else {
                    throw MulticamError("A selected clip has speed \(clip.speed); reset to 1× before grouping.")
                }
                if clip.mediaType == .audio { audioClips.append(clip) } else { videoClips.append(clip) }
            }
        }

        var seen = Set<String>()
        let angleSources = videoClips.filter { seen.insert($0.mediaRef).inserted }
        guard angleSources.count >= 2 else {
            throw MulticamError("Select clips from at least two different cameras.")
        }

        // Timeline placement as the shared timebase: source t=0 sits at (start − trimStart)/fps.
        func timebaseOffset(_ clip: Clip) -> Double {
            Double(clip.startFrame - clip.trimStartFrame) / fps
        }

        let referenceOffset = timebaseOffset(angleSources[0])
        let angles = angleSources.map { clip in
            MulticamAngle(mediaRef: clip.mediaRef, offsetSeconds: timebaseOffset(clip) - referenceOffset)
        }

        // Prefer a standalone audio asset as master; else the first camera's own audio.
        let masterAudio = audioClips.first { clip in
            mediaAssets.first(where: { $0.id == clip.mediaRef })?.type == .audio
        } ?? audioClips.first

        var group = MulticamGroup(name: nextMulticamGroupName(), angles: angles)
        if let masterAudio {
            group.audioMediaRef = masterAudio.mediaRef
            group.audioOffsetSeconds = group.angle(forMediaRef: masterAudio.mediaRef)?.offsetSeconds
                ?? (timebaseOffset(masterAudio) - referenceOffset)
        } else {
            group.audioMediaRef = angles[0].mediaRef
        }

        undoManager?.beginUndoGrouping()
        addMulticamGroup(group)
        let videoIds = Set(videoClips.map(\.id))
        mutateClips(ids: videoIds, actionName: "Create Multicam") { $0.multicamGroupId = group.id }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Create Multicam")
        return group
    }

    private func addMulticamGroup(_ group: MulticamGroup) {
        multicamGroups.append(group)
        let gid = group.id
        registerTimelineUndo { vm in
            vm.removeMulticamGroup(id: gid)
        }
        undoManager?.setActionName("Create Multicam")
        onProjectCheckpointRequired?()
    }

    /// Dissolves a group: untags its clips (cuts and media stay) and removes the metadata.
    func deleteMulticamGroup(id: String) throws {
        guard let group = multicamGroup(id: id) else { throw MulticamError("Multicam group not found: \(id)") }
        let taggedIds = Set(timeline.tracks.flatMap(\.clips).filter { $0.multicamGroupId == group.id }.map(\.id))
        undoManager?.beginUndoGrouping()
        if !taggedIds.isEmpty {
            mutateClips(ids: taggedIds, actionName: "Delete Multicam") { $0.multicamGroupId = nil }
        }
        removeMulticamGroup(id: group.id)
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Delete Multicam")
    }

    func removeMulticamGroup(id: String) {
        guard let index = multicamGroups.firstIndex(where: { $0.id == id }) else { return }
        let group = multicamGroups.remove(at: index)
        registerTimelineUndo { vm in
            vm.multicamGroups.insert(group, at: min(index, vm.multicamGroups.count))
        }
        undoManager?.setActionName("Delete Multicam")
        onProjectCheckpointRequired?()
    }

    private func nextMulticamGroupName() -> String {
        let used = Set(multicamGroups.map(\.name))
        var n = multicamGroups.count + 1
        while used.contains("Multicam \(n)") { n += 1 }
        return "Multicam \(n)"
    }

    // MARK: - Placement

    /// Places the group on the timeline: one video clip (the given/first angle) linked to
    /// the master audio, both trimmed to the span the two sources share. Returns clip ids.
    @discardableResult
    func placeMulticam(groupId: String, angleRef: String? = nil, atFrame: Int = 0) throws -> [String] {
        guard let group = multicamGroup(id: groupId) else { throw MulticamError("Multicam group not found: \(groupId)") }
        guard let angle = angleRef.map({ group.resolveAngle($0) }) ?? group.angles.first else {
            throw MulticamError("Group has no angles.")
        }
        guard let videoAsset = mediaAssets.first(where: { $0.id == angle.mediaRef }) else {
            throw MulticamError("Angle media missing: \(angle.mediaRef)")
        }
        let fps = Double(timeline.fps)
        guard fps > 0 else { throw MulticamError("Invalid timeline fps.") }

        var spanStart = angle.offsetSeconds
        var spanEnd = angle.offsetSeconds + videoAsset.duration
        var audioAsset: MediaAsset?
        var audioOffset: Double = 0
        if let audioRef = group.audioMediaRef, audioRef != angle.mediaRef,
           let asset = mediaAssets.first(where: { $0.id == audioRef }),
           let offset = group.offsetSeconds(forMediaRef: audioRef) {
            audioAsset = asset
            audioOffset = offset
            spanStart = max(spanStart, offset)
            spanEnd = min(spanEnd, offset + asset.duration)
        } else if group.audioMediaRef == angle.mediaRef, videoAsset.hasAudio {
            audioAsset = videoAsset
            audioOffset = angle.offsetSeconds
        }
        guard spanEnd > spanStart else {
            throw MulticamError("The angle and master audio don't overlap in time.")
        }

        let durationFrames = max(1, secondsToFrame(seconds: spanEnd - spanStart, fps: timeline.fps))
        let linkGroupId = audioAsset != nil ? UUID().uuidString : nil
        var placedIds: [String] = []

        withTimelineSwap(actionName: "Place Multicam") {
            let videoTrack = insertTrack(at: 0, type: .video)
            var video = Clip(
                mediaRef: videoAsset.id,
                mediaType: .video,
                sourceClipType: .video,
                startFrame: atFrame,
                durationFrames: durationFrames,
                transform: fitTransform(for: videoAsset)
            )
            video.trimStartFrame = max(0, Int(((spanStart - angle.offsetSeconds) * fps).rounded()))
            video.trimEndFrame = max(0, secondsToFrame(seconds: videoAsset.duration, fps: timeline.fps) - video.trimStartFrame - durationFrames)
            video.linkGroupId = linkGroupId
            video.multicamGroupId = group.id
            timeline.tracks[videoTrack].clips.append(video)
            sortClips(trackIndex: videoTrack)
            placedIds.append(video.id)

            if let audioAsset {
                let audioTrack = resolveOrCreateAudioTrack(startFrame: atFrame, duration: durationFrames)
                var audio = Clip(
                    mediaRef: audioAsset.id,
                    mediaType: .audio,
                    sourceClipType: audioAsset.type,
                    startFrame: atFrame,
                    durationFrames: durationFrames
                )
                audio.trimStartFrame = max(0, Int(((spanStart - audioOffset) * fps).rounded()))
                audio.trimEndFrame = max(0, secondsToFrame(seconds: audioAsset.duration, fps: timeline.fps) - audio.trimStartFrame - durationFrames)
                audio.linkGroupId = linkGroupId
                timeline.tracks[audioTrack].clips.append(audio)
                sortClips(trackIndex: audioTrack)
                placedIds.append(audio.id)
            }
        }
        return placedIds
    }

    // MARK: - Angle switching

    /// Group time of a clip's first visible frame.
    func multicamGroupTime(of clip: Clip, in group: MulticamGroup) -> Double? {
        guard let offset = group.offsetSeconds(forMediaRef: clip.mediaRef) else { return nil }
        return offset + Double(clip.trimStartFrame) / Double(timeline.fps)
    }

    /// Switches whole clips to another angle. One undoable action, then merges redundant cuts.
    func switchMulticamAngle(clipIds: [String], toAngle angleRef: String) -> MulticamSwitchOutcome {
        var outcome = MulticamSwitchOutcome()
        withTimelineSwap(actionName: "Switch Angle") {
            for id in clipIds {
                if let message = switchSingleClip(id: id, toAngle: angleRef) {
                    outcome.failures.append((id, message))
                } else {
                    outcome.switchedClipIds.append(id)
                }
            }
            if !outcome.switchedClipIds.isEmpty {
                outcome.mergedCount = sanitizeMulticamCuts()
            }
        }
        return outcome
    }

    /// Splits the group's clips at each range boundary, then switches the pieces inside.
    /// Layout entries additionally place the extra angles as overlay clips on new top tracks.
    func switchMulticamAngle(
        groupId: String,
        switches: [MulticamSwitch],
        trackIndex explicitTrack: Int? = nil
    ) throws -> MulticamSwitchOutcome {
        guard let group = multicamGroup(id: groupId) else { throw MulticamError("Multicam group not found: \(groupId)") }
        for s in switches {
            guard s.startFrame < s.endFrame else {
                throw MulticamError("Invalid range [\(s.startFrame), \(s.endFrame)): startFrame must be less than endFrame.")
            }
            guard (s.angle != nil) != (s.layout != nil) else {
                throw MulticamError("Each switch needs exactly one of 'angle' or 'layout'+'angles'.")
            }
            if let layout = s.layout {
                guard s.layoutAngles.count == layout.slots.count else {
                    throw MulticamError("Layout '\(layout.rawValue)' has \(layout.slots.count) slots; got \(s.layoutAngles.count) angles.")
                }
            }
        }

        // The track the switches act on: explicit, or the group's primary (bottom-most) video track.
        let trackIndexes = timeline.tracks.indices.filter { i in
            timeline.tracks[i].type != .audio
                && timeline.tracks[i].clips.contains { $0.multicamGroupId == group.id }
        }
        let targetTrack: Int
        if let explicitTrack {
            guard trackIndexes.contains(explicitTrack) else {
                throw MulticamError("Track \(explicitTrack) has no clips of this multicam group.")
            }
            targetTrack = explicitTrack
        } else if let last = trackIndexes.last {
            targetTrack = last
        } else {
            throw MulticamError("No clips of this multicam group on the timeline. Place the group first.")
        }
        // Overlay placement inserts tracks and shifts indices; pin the track by id.
        let targetTrackId = timeline.tracks[targetTrack].id

        var outcome = MulticamSwitchOutcome()
        withTimelineSwap(actionName: "Switch Angle") {
            let trackIdx = { self.timeline.tracks.firstIndex { $0.id == targetTrackId } }

            // Splits propagate through link groups; detach the master audio first so angle
            // cuts never fragment it. Sync-locked tracks keep dialogue edits aligned.
            if let ti = trackIdx() { detachMasterAudioLinks(group: group, trackIndex: ti) }

            var splitPoints: [(trackIndex: Int, atFrame: Int)] = []
            if let ti = trackIdx() {
                for s in switches {
                    for frame in [s.startFrame, s.endFrame] {
                        let needsSplit = timeline.tracks[ti].clips.contains {
                            $0.multicamGroupId == group.id && frame > $0.startFrame && frame < $0.endFrame
                        }
                        if needsSplit { splitPoints.append((ti, frame)) }
                    }
                }
            }
            if !splitPoints.isEmpty {
                _ = splitClips(at: splitPoints)
            }

            for s in switches {
                guard let ti = trackIdx() else { break }
                let inside = timeline.tracks[ti].clips.filter {
                    $0.multicamGroupId == group.id
                        && $0.startFrame >= s.startFrame && $0.endFrame <= s.endFrame
                }
                guard !inside.isEmpty else {
                    outcome.failures.append(("-", "No clips of the group inside [\(s.startFrame), \(s.endFrame))."))
                    continue
                }

                if let angle = s.angle {
                    // Validate the whole range before touching anything: a failed range
                    // is skipped intact rather than half-dismantled.
                    var rangeFailed = false
                    for clip in inside {
                        if case .failure(let error) = switchedClip(clip, toAngle: angle) {
                            outcome.failures.append((clip.id, error.message))
                            rangeFailed = true
                        }
                    }
                    guard !rangeFailed else { continue }

                    // Full-frame entry ends any layout here: drop overlay clips in the
                    // range and restore default framing on the base clips.
                    removeLayoutOverlays(group: group, startFrame: s.startFrame, endFrame: s.endFrame, keepTrackId: targetTrackId)
                    for clip in inside {
                        _ = switchSingleClip(id: clip.id, toAngle: angle)
                        outcome.switchedClipIds.append(clip.id)
                        if let loc = findClip(id: clip.id),
                           let asset = mediaAssets.first(where: { $0.id == timeline.tracks[loc.trackIndex].clips[loc.clipIndex].mediaRef }) {
                            timeline.tracks[loc.trackIndex].clips[loc.clipIndex].transform = fitTransform(for: asset)
                            timeline.tracks[loc.trackIndex].clips[loc.clipIndex].crop = Crop()
                        }
                    }
                } else if let layout = s.layout {
                    applyLayoutSwitch(
                        s, layout: layout, group: group, inside: inside,
                        keepTrackId: targetTrackId, outcome: &outcome
                    )
                }
            }
            outcome.mergedCount = sanitizeMulticamCuts()
        }
        return outcome
    }

    /// Removes the group's overlay clips (layout residue) inside [startFrame, endFrame) on
    /// every video track except the primary one, pruning tracks this empties. Caller owns undo.
    private func removeLayoutOverlays(group: MulticamGroup, startFrame: Int, endFrame: Int, keepTrackId: String) {
        var splitPoints: [(trackIndex: Int, atFrame: Int)] = []
        for (ti, track) in timeline.tracks.enumerated()
        where track.type != .audio && track.id != keepTrackId {
            for clip in track.clips where clip.multicamGroupId == group.id {
                for frame in [startFrame, endFrame] where frame > clip.startFrame && frame < clip.endFrame {
                    splitPoints.append((ti, frame))
                }
            }
        }
        if !splitPoints.isEmpty {
            _ = splitClips(at: splitPoints)
        }

        var removeIds: [String] = []
        var touchedTrackIds: Set<String> = []
        for track in timeline.tracks where track.type != .audio && track.id != keepTrackId {
            for clip in track.clips where clip.multicamGroupId == group.id
                && clip.startFrame >= startFrame && clip.endFrame <= endFrame {
                removeIds.append(clip.id)
                touchedTrackIds.insert(track.id)
            }
        }
        for id in removeIds { removeClipInternal(id: id) }

        let emptied = timeline.tracks
            .filter { touchedTrackIds.contains($0.id) && $0.clips.isEmpty }
            .map(\.id)
        if !emptied.isEmpty { removeTracks(ids: emptied) }
    }

    /// Base clips become slot 0; each remaining slot gets an overlay clip on a new top track.
    /// Everything is validated first — a range that can't fully apply is left untouched.
    private func applyLayoutSwitch(
        _ s: MulticamSwitch,
        layout: VideoLayout,
        group: MulticamGroup,
        inside: [Clip],
        keepTrackId: String,
        outcome: inout MulticamSwitchOutcome
    ) {
        let slots = layout.slots.sorted { $0.z < $1.z }
        let anchor = inside[0]

        for clip in inside {
            if case .failure(let error) = switchedClip(clip, toAngle: s.layoutAngles[0]) {
                outcome.failures.append((clip.id, error.message))
                return
            }
        }

        var overlayPlan: [(slot: LayoutSlot, angle: MulticamAngle)] = []
        for (i, slot) in slots.enumerated() where i > 0 {
            guard let angle = group.resolveAngle(s.layoutAngles[i]) else {
                let names = group.angles.map(MulticamGroup.displayName).joined(separator: ", ")
                outcome.failures.append(("-", "Unknown angle '\(s.layoutAngles[i])'. Angles: \(names)."))
                return
            }
            do {
                _ = try overlayStartSeconds(group: group, angle: angle, anchor: anchor, startFrame: s.startFrame, endFrame: s.endFrame)
            } catch {
                outcome.failures.append(("-", error.localizedDescription))
                return
            }
            overlayPlan.append((slot, angle))
        }

        // Replace, don't stack: clear this range's previous overlays before placing.
        removeLayoutOverlays(group: group, startFrame: s.startFrame, endFrame: s.endFrame, keepTrackId: keepTrackId)

        for clip in inside {
            _ = switchSingleClip(id: clip.id, toAngle: s.layoutAngles[0])
            outcome.switchedClipIds.append(clip.id)
            if let loc = findClip(id: clip.id) {
                let current = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
                let p = layoutPlacement(for: current, in: slots[0].rect, fit: .fill)
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex].transform = p.transform
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex].crop = p.crop
            }
        }

        for (slot, angle) in overlayPlan {
            guard let overlayId = try? placeMulticamOverlay(
                group: group, angle: angle, anchor: anchor,
                startFrame: s.startFrame, endFrame: s.endFrame
            ) else { continue }
            if let loc = findClip(id: overlayId) {
                let clip = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
                let p = layoutPlacement(for: clip, in: slot.rect, fit: .fill)
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex].transform = p.transform
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex].crop = p.crop
            }
            outcome.overlayClipIds.append(overlayId)
        }
    }

    /// Unlinks the group's video clips from their master-audio partners (untagged audio),
    /// so boundary splits stay on the video track. Caller owns undo.
    private func detachMasterAudioLinks(group: MulticamGroup, trackIndex: Int) {
        var toClear: Set<String> = []
        for clip in timeline.tracks[trackIndex].clips
        where clip.multicamGroupId == group.id && clip.linkGroupId != nil {
            let partners = linkedPartnerIds(of: clip.id).compactMap(clipFor(id:))
            let masterAudio = partners.filter { $0.mediaType == .audio && $0.multicamGroupId == nil }
            guard !masterAudio.isEmpty, masterAudio.count == partners.count else { continue }
            toClear.insert(clip.id)
            toClear.formUnion(masterAudio.map(\.id))
        }
        for id in toClear {
            if let loc = findClip(id: id) {
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex].linkGroupId = nil
            }
        }
    }

    /// Core swap math, mutation-free: the clip rewritten to show the same group-time span
    /// on another angle. Callers use it both to validate and to apply.
    private func switchedClip(_ clip: Clip, toAngle angleRef: String) -> Result<Clip, MulticamError> {
        guard clip.mediaType != .audio else {
            return .failure(MulticamError("Angle switching applies to video clips; the master audio stays."))
        }
        guard let group = clip.multicamGroupId.flatMap({ multicamGroup(id: $0) }) else {
            return .failure(MulticamError("Clip is not part of a multicam group."))
        }
        guard let target = group.resolveAngle(angleRef) else {
            let names = group.angles.map(MulticamGroup.displayName).joined(separator: ", ")
            return .failure(MulticamError("Unknown angle '\(angleRef)'. Angles: \(names)."))
        }
        guard let groupStart = multicamGroupTime(of: clip, in: group) else {
            return .failure(MulticamError("Clip's media \(clip.mediaRef) is not an angle of its group."))
        }
        guard let targetAsset = mediaAssets.first(where: { $0.id == target.mediaRef }) else {
            return .failure(MulticamError("Angle media missing: \(target.mediaRef)"))
        }
        if clip.mediaRef == target.mediaRef { return .success(clip) }

        let fps = Double(timeline.fps)
        let consumedSeconds = Double(clip.sourceFramesConsumed) / fps
        let newStartSeconds = groupStart - target.offsetSeconds
        let tolerance = 1.0 / fps
        guard newStartSeconds >= -tolerance,
              newStartSeconds + consumedSeconds <= targetAsset.duration + tolerance else {
            return .failure(MulticamError("Angle '\(MulticamGroup.displayName(target))' doesn't cover this span (needs \(String(format: "%.2f", newStartSeconds))s–\(String(format: "%.2f", newStartSeconds + consumedSeconds))s of a \(String(format: "%.2f", targetAsset.duration))s source)."))
        }

        let oldAsset = mediaAssets.first { $0.id == clip.mediaRef }
        let newTrimStart = max(0, Int((newStartSeconds * fps).rounded()))
        let totalFrames = secondsToFrame(seconds: targetAsset.duration, fps: timeline.fps)
        var updated = clip
        updated.mediaRef = target.mediaRef
        updated.trimStartFrame = newTrimStart
        updated.trimEndFrame = max(0, totalFrames - newTrimStart - clip.sourceFramesConsumed)
        // Keep custom framing (layouts); refit only when the clip still wore the default fit.
        if let oldAsset, clip.crop.isIdentity, clip.transform == fitTransform(for: oldAsset) {
            updated.transform = fitTransform(for: targetAsset)
        }
        return .success(updated)
    }

    /// Writes the swap for one clip. Returns an error message, or nil on success. Caller owns undo.
    private func switchSingleClip(id: String, toAngle angleRef: String) -> String? {
        guard let loc = findClip(id: id) else { return "Clip not found." }
        switch switchedClip(timeline.tracks[loc.trackIndex].clips[loc.clipIndex], toAngle: angleRef) {
        case .success(let updated):
            timeline.tracks[loc.trackIndex].clips[loc.clipIndex] = updated
            return nil
        case .failure(let error):
            return error.message
        }
    }

    // MARK: - Cut sanitization

    /// Merges adjacent multicam clips that are the same angle and source-continuous — the
    /// residue of switching split segments back to one camera. Linked audio partners merge
    /// with them. Returns the number of merges. Caller owns undo/notification.
    @discardableResult
    func sanitizeMulticamCuts() -> Int {
        var merged = 0
        var didMerge = true
        while didMerge {
            didMerge = false
            outer: for ti in timeline.tracks.indices where timeline.tracks[ti].type != .audio {
                let clips = timeline.tracks[ti].clips.sorted { $0.startFrame < $1.startFrame }
                guard clips.count >= 2 else { continue }
                for i in 0..<(clips.count - 1) {
                    let a = clips[i], b = clips[i + 1]
                    guard a.multicamGroupId != nil, mergeable(a, b) else { continue }
                    let aPartner = singleAudioPartner(of: a)
                    let bPartner = singleAudioPartner(of: b)
                    switch (aPartner, bPartner) {
                    case (nil, nil):
                        merge(left: a, right: b)
                    case (let pa?, let pb?):
                        guard mergeable(pa, pb) else { continue }
                        merge(left: a, right: b)
                        merge(left: pa, right: pb)
                        // Keep the merged pair in one link group.
                        if let gid = a.linkGroupId, let mergedLoc = findClip(id: pa.id) {
                            timeline.tracks[mergedLoc.trackIndex].clips[mergedLoc.clipIndex].linkGroupId = gid
                        }
                    default:
                        continue
                    }
                    merged += 1
                    didMerge = true
                    break outer
                }
            }
        }
        return merged
    }

    private func mergeable(_ a: Clip, _ b: Clip) -> Bool {
        guard b.startFrame == a.endFrame,
              a.mediaRef == b.mediaRef,
              a.mediaType == b.mediaType,
              a.multicamGroupId == b.multicamGroupId,
              a.speed == b.speed,
              a.volume == b.volume,
              a.opacity == b.opacity,
              a.blendMode == b.blendMode,
              a.transform == b.transform,
              a.crop == b.crop,
              a.effects == b.effects,
              a.fadeOutFrames == 0, b.fadeInFrames == 0,
              !hasActiveKeyframes(a), !hasActiveKeyframes(b)
        else { return false }
        // Source-continuous within a frame of rounding slop.
        return abs(b.trimStartFrame - (a.trimStartFrame + a.sourceFramesConsumed)) <= 1
    }

    private func hasActiveKeyframes(_ clip: Clip) -> Bool {
        clip.hasTransformAnimation
            || (clip.opacityTrack?.isActive ?? false)
            || (clip.volumeTrack?.isActive ?? false)
            || (clip.cropTrack?.isActive ?? false)
    }

    /// The lone linked audio partner of a clip, or nil when it has none or several.
    private func singleAudioPartner(of clip: Clip) -> Clip? {
        guard clip.linkGroupId != nil else { return nil }
        let partners = linkedPartnerIds(of: clip.id).compactMap(clipFor(id:))
        let audio = partners.filter { $0.mediaType == .audio }
        return partners.count == 1 && audio.count == 1 ? audio.first : nil
    }

    private func merge(left: Clip, right: Clip) {
        guard let loc = findClip(id: left.id) else { return }
        var mergedClip = left
        mergedClip.durationFrames = left.durationFrames + right.durationFrames
        mergedClip.trimEndFrame = right.trimEndFrame
        mergedClip.fadeOutFrames = right.fadeOutFrames
        mergedClip.fadeOutInterpolation = right.fadeOutInterpolation
        timeline.tracks[loc.trackIndex].clips[loc.clipIndex] = mergedClip
        removeClipInternal(id: right.id)
    }

    // MARK: - Layout overlays

    /// Validation half of overlay placement: the angle's source start seconds for the span,
    /// or a thrown error when the angle can't cover it. Mutation-free.
    private func overlayStartSeconds(
        group: MulticamGroup,
        angle: MulticamAngle,
        anchor: Clip,
        startFrame: Int,
        endFrame: Int
    ) throws -> Double {
        guard let asset = mediaAssets.first(where: { $0.id == angle.mediaRef }) else {
            throw MulticamError("Angle media missing: \(angle.mediaRef)")
        }
        guard let anchorOffset = group.offsetSeconds(forMediaRef: anchor.mediaRef) else {
            throw MulticamError("Anchor clip's media is not in the group.")
        }
        let fps = Double(timeline.fps)
        // Group time at `startFrame` through the anchor clip's placement.
        let anchorSourceSeconds = (Double(anchor.trimStartFrame) + Double(startFrame - anchor.startFrame) * anchor.speed) / fps
        let groupStart = anchorOffset + anchorSourceSeconds
        let spanSeconds = Double(endFrame - startFrame) / fps
        let newStartSeconds = groupStart - angle.offsetSeconds
        let tolerance = 1.0 / fps
        guard newStartSeconds >= -tolerance,
              newStartSeconds + spanSeconds <= asset.duration + tolerance else {
            throw MulticamError("Angle '\(MulticamGroup.displayName(angle))' doesn't cover frames \(startFrame)–\(endFrame).")
        }
        return newStartSeconds
    }

    /// Adds one angle as an overlay clip on a fresh top track over [startFrame, endFrame),
    /// trimmed by group offsets using `anchor` (a group clip covering the span) as timebase.
    /// Returns the new clip id. Caller owns undo (call inside withTimelineSwap).
    func placeMulticamOverlay(
        group: MulticamGroup,
        angle: MulticamAngle,
        anchor: Clip,
        startFrame: Int,
        endFrame: Int
    ) throws -> String {
        let newStartSeconds = try overlayStartSeconds(
            group: group, angle: angle, anchor: anchor, startFrame: startFrame, endFrame: endFrame
        )
        guard let asset = mediaAssets.first(where: { $0.id == angle.mediaRef }) else {
            throw MulticamError("Angle media missing: \(angle.mediaRef)")
        }
        let fps = Double(timeline.fps)
        let durationFrames = endFrame - startFrame

        let trackIndex = insertTrack(at: 0, type: .video)
        var clip = Clip(
            mediaRef: asset.id,
            mediaType: .video,
            sourceClipType: .video,
            startFrame: startFrame,
            durationFrames: durationFrames,
            transform: fitTransform(for: asset)
        )
        clip.trimStartFrame = max(0, Int((newStartSeconds * fps).rounded()))
        clip.trimEndFrame = max(0, secondsToFrame(seconds: asset.duration, fps: timeline.fps) - clip.trimStartFrame - durationFrames)
        clip.multicamGroupId = group.id
        timeline.tracks[trackIndex].clips.append(clip)
        sortClips(trackIndex: trackIndex)
        return clip.id
    }
}
