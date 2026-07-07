import Foundation

/// Multicam switching: angle math, gaps, cut cleanup. Works on Timelines only.
enum MulticamEngine {

    struct SlotAssignment {
        let slot: LayoutSlot
        let member: MulticamSource.Member
    }

    struct Entry {
        var childRange: Range<Int>
        var layout: VideoLayout
        var assignments: [SlotAssignment]
        var fit: LayoutFit

        var program: SlotAssignment { assignments[0] }
    }

    struct Outcome {
        var switched = 0
        var filled = 0
        var merged = 0
    }

    typealias Placement = (Clip, LayoutRect, LayoutFit) -> (transform: Transform, crop: Crop)

    /// Limit lag search so every match uses at least half the shorter clip.
    static func maxLagHops(windowSeconds: Double, hopSeconds: Double, referenceCount: Int, targetCount: Int) -> Int {
        let windowHops = Int((windowSeconds / hopSeconds).rounded())
        return max(1, min(windowHops, min(referenceCount, targetCount) / 2))
    }

    // Entries should match member coverage; placement resolves source layout.
    static func apply(
        entries: [Entry],
        to child: inout Timeline,
        source: inout MulticamSource,
        sourceDurations: [String: Double],
        placement: Placement,
        fitTransform: (Clip) -> Transform
    ) -> Outcome {
        var outcome = Outcome()
        var touched: [Range<Int>] = []

        for entry in entries where !entry.childRange.isEmpty {
            guard let programIdx = child.tracks.firstIndex(where: { $0.id == source.programTrackId }) else { continue }
            let range = entry.childRange
            touched.append(range)

            split(track: &child.tracks[programIdx], at: range.lowerBound)
            split(track: &child.tracks[programIdx], at: range.upperBound)

            let fps = child.fps
            let member = entry.program.member
            let sourceLen = sourceDurations[member.mediaRef].map { Int(($0 * Double(fps)).rounded()) }
            for i in child.tracks[programIdx].clips.indices {
                let clip = child.tracks[programIdx].clips[i]
                guard clip.startFrame >= range.lowerBound, clip.endFrame <= range.upperBound else { continue }
                rewrite(&child.tracks[programIdx].clips[i], to: member, fps: fps, sourceLen: sourceLen)
                style(&child.tracks[programIdx].clips[i], entry: entry, placement: placement, fitTransform: fitTransform)
                outcome.switched += 1
            }

            for gap in gaps(in: child.tracks[programIdx], within: range) {
                var clip = Clip(mediaRef: member.mediaRef, startFrame: gap.lowerBound, durationFrames: gap.count)
                clip.trimStartFrame = member.trimFrame(atChildFrame: gap.lowerBound, fps: fps)
                if let sourceLen {
                    clip.trimEndFrame = max(0, sourceLen - clip.trimStartFrame - clip.sourceFramesConsumed)
                }
                style(&clip, entry: entry, placement: placement, fitTransform: fitTransform)
                child.tracks[programIdx].clips.append(clip)
                outcome.filled += 1
            }
            child.tracks[programIdx].clips.sort { $0.startFrame < $1.startFrame }

            applyOverlays(entry: entry, to: &child, source: &source, sourceDurations: sourceDurations, placement: placement)
        }

        for trackId in [source.programTrackId] + source.overlayTrackIds {
            guard let idx = child.tracks.firstIndex(where: { $0.id == trackId }) else { continue }
            outcome.merged += joinThroughEdits(track: &child.tracks[idx], within: touched)
        }
        return outcome
    }

    // MARK: - Overlays

    private static func applyOverlays(
        entry: Entry,
        to child: inout Timeline,
        source: inout MulticamSource,
        sourceDurations: [String: Double],
        placement: Placement
    ) {
        let range = entry.childRange
        let overlays = Array(entry.assignments.dropFirst())

        for (ordinal, trackId) in source.overlayTrackIds.enumerated() where ordinal >= overlays.count {
            if let idx = child.tracks.firstIndex(where: { $0.id == trackId }) {
                clear(track: &child.tracks[idx], within: range)
            }
        }
        guard !overlays.isEmpty else { return }

        let fps = child.fps
        for (ordinal, assignment) in overlays.enumerated() {
            let trackIdx = overlayTrackIndex(ordinal: ordinal, in: &child, source: &source)
            clear(track: &child.tracks[trackIdx], within: range)

            var clip = Clip(mediaRef: assignment.member.mediaRef, startFrame: range.lowerBound, durationFrames: range.count)
            clip.trimStartFrame = assignment.member.trimFrame(atChildFrame: range.lowerBound, fps: fps)
            if let duration = sourceDurations[assignment.member.mediaRef] {
                let sourceLen = Int((duration * Double(fps)).rounded())
                clip.trimEndFrame = max(0, sourceLen - clip.trimStartFrame - clip.sourceFramesConsumed)
            }
            let placed = placement(clip, assignment.slot.rect, entry.fit)
            clip.transform = placed.transform
            clip.crop = placed.crop
            child.tracks[trackIdx].clips.append(clip)
            child.tracks[trackIdx].clips.sort { $0.startFrame < $1.startFrame }
        }
    }

    /// Overlay tracks sit above the program track (lower index = on top); ordinal 0 is closest to it.
    private static func overlayTrackIndex(ordinal: Int, in child: inout Timeline, source: inout MulticamSource) -> Int {
        if source.overlayTrackIds.indices.contains(ordinal),
           let idx = child.tracks.firstIndex(where: { $0.id == source.overlayTrackIds[ordinal] }) {
            return idx
        }
        let programIdx = child.tracks.firstIndex { $0.id == source.programTrackId } ?? 0
        let track = Track(type: .video)
        let idx = max(0, programIdx - ordinal)
        child.tracks.insert(track, at: idx)
        if source.overlayTrackIds.indices.contains(ordinal) {
            source.overlayTrackIds[ordinal] = track.id
        } else {
            source.overlayTrackIds.append(track.id)
        }
        return idx
    }

    // MARK: - Clip surgery

    private static func rewrite(_ clip: inout Clip, to member: MulticamSource.Member, fps: Int, sourceLen: Int?) {
        guard clip.mediaRef != member.mediaRef else { return }
        clip.mediaRef = member.mediaRef
        clip.trimStartFrame = member.trimFrame(atChildFrame: clip.startFrame, fps: fps)
        clip.trimEndFrame = sourceLen.map { max(0, $0 - clip.trimStartFrame - clip.sourceFramesConsumed) } ?? 0
    }

    private static func style(
        _ clip: inout Clip,
        entry: Entry,
        placement: Placement,
        fitTransform: (Clip) -> Transform
    ) {
        if entry.layout == .full {
            clip.transform = fitTransform(clip)
            clip.crop = Crop()
        } else {
            let placed = placement(clip, entry.program.slot.rect, entry.fit)
            clip.transform = placed.transform
            clip.crop = placed.crop
        }
    }

    @discardableResult
    private static func split(track: inout Track, at frame: Int) -> Bool {
        guard let i = track.clips.firstIndex(where: { frame > $0.startFrame && frame < $0.endFrame }) else { return false }
        let clip = track.clips[i]
        let offset = frame - clip.startFrame
        let leftSource = Int((Double(offset) * clip.speed).rounded())
        let rightSource = Int((Double(clip.durationFrames - offset) * clip.speed).rounded())

        var left = clip
        left.durationFrames = offset
        left.trimEndFrame = clip.trimEndFrame + rightSource
        left.fadeOutFrames = 0

        var right = clip
        right.id = UUID().uuidString
        right.startFrame = frame
        right.durationFrames = clip.durationFrames - offset
        right.trimStartFrame = clip.trimStartFrame + leftSource
        right.fadeInFrames = 0

        // Users may keyframe/fade clips inside the group — split like the main path.
        (left.opacityTrack, right.opacityTrack) = EditorViewModel.splitKeyframeTrack(clip.opacityTrack, at: offset, fallback: clip.opacity)
        (left.volumeTrack, right.volumeTrack) = EditorViewModel.splitKeyframeTrack(clip.volumeTrack, at: offset, fallback: clip.volume)
        (left.positionTrack, right.positionTrack) = EditorViewModel.splitKeyframeTrack(clip.positionTrack, at: offset, fallback: AnimPair(a: 0, b: 0))
        (left.scaleTrack, right.scaleTrack) = EditorViewModel.splitKeyframeTrack(clip.scaleTrack, at: offset, fallback: AnimPair(a: 1, b: 1))
        (left.rotationTrack, right.rotationTrack) = EditorViewModel.splitKeyframeTrack(clip.rotationTrack, at: offset, fallback: 0)
        (left.cropTrack, right.cropTrack) = EditorViewModel.splitKeyframeTrack(clip.cropTrack, at: offset, fallback: clip.crop)
        left.clampFadesToDuration()
        right.clampFadesToDuration()

        track.clips[i] = left
        track.clips.insert(right, at: i + 1)
        return true
    }

    private static func clear(track: inout Track, within range: Range<Int>) {
        split(track: &track, at: range.lowerBound)
        split(track: &track, at: range.upperBound)
        track.clips.removeAll { $0.startFrame >= range.lowerBound && $0.endFrame <= range.upperBound }
    }

    private static func gaps(in track: Track, within range: Range<Int>) -> [Range<Int>] {
        var gaps: [Range<Int>] = []
        var cursor = range.lowerBound
        for clip in track.clips.sorted(by: { $0.startFrame < $1.startFrame }) where clip.endFrame > range.lowerBound && clip.startFrame < range.upperBound {
            if clip.startFrame > cursor { gaps.append(cursor..<clip.startFrame) }
            cursor = max(cursor, clip.endFrame)
        }
        if cursor < range.upperBound { gaps.append(cursor..<range.upperBound) }
        return gaps
    }

    // MARK: - Sanitization

    /// True when b continues a with no visible seam — the lossless inverse of a split.
    private static func isThroughEdit(_ a: Clip, _ b: Clip) -> Bool {
        a.mediaRef == b.mediaRef
            && a.mediaType == b.mediaType
            && b.startFrame == a.endFrame
            && b.trimStartFrame == a.trimStartFrame + a.sourceFramesConsumed
            && a.speed == b.speed
            && a.volume == b.volume
            && a.opacity == b.opacity
            && a.transform == b.transform
            && a.crop == b.crop
            && a.effects == b.effects
            && a.blendMode == b.blendMode
            && a.fadeOutFrames == 0 && b.fadeInFrames == 0
            && !a.hasKeyframes && !b.hasKeyframes
    }

    /// Merges through-edit seams whose join point falls inside a touched range. Returns seams merged.
    private static func joinThroughEdits(track: inout Track, within ranges: [Range<Int>]) -> Int {
        guard !ranges.isEmpty else { return 0 }
        var merged = 0
        var clips = track.clips.sorted { $0.startFrame < $1.startFrame }
        var i = 0
        while i + 1 < clips.count {
            let seam = clips[i].endFrame
            if ranges.contains(where: { $0.lowerBound <= seam && seam <= $0.upperBound }),
               isThroughEdit(clips[i], clips[i + 1]) {
                clips[i].durationFrames += clips[i + 1].durationFrames
                clips[i].trimEndFrame = clips[i + 1].trimEndFrame
                clips[i].fadeOutFrames = clips[i + 1].fadeOutFrames
                clips.remove(at: i + 1)
                merged += 1
            } else {
                i += 1
            }
        }
        track.clips = clips
        return merged
    }
}

private extension Clip {
    var hasKeyframes: Bool {
        opacityTrack != nil || positionTrack != nil || scaleTrack != nil
            || rotationTrack != nil || cropTrack != nil || volumeTrack != nil
    }
}
