import Foundation
import Testing
@testable import PalmierPro

@MainActor
@Suite("Multicam")
struct MulticamTests {

    // Two 60s cameras: B starts 2s after A on the group timebase. fps 30.
    private func makeEditor() -> (EditorViewModel, MulticamGroup) {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(fps: 30, tracks: [Fixtures.videoTrack(), Fixtures.audioTrack()])
        let camA = MediaAsset(id: "cam-a", url: URL(fileURLWithPath: "/tmp/a.mov"), type: .video, name: "A", duration: 60)
        let camB = MediaAsset(id: "cam-b", url: URL(fileURLWithPath: "/tmp/b.mov"), type: .video, name: "B", duration: 60)
        e.mediaAssets = [camA, camB]
        let group = MulticamGroup(
            id: "group-1",
            name: "Multicam 1",
            angles: [
                MulticamAngle(mediaRef: "cam-a", offsetSeconds: 0, label: "wide", speaker: "Ana"),
                MulticamAngle(mediaRef: "cam-b", offsetSeconds: 2.0, label: "close", speaker: "Ben"),
            ],
            audioMediaRef: "cam-a"
        )
        e.multicamGroups = [group]
        return (e, group)
    }

    private func groupClip(_ mediaRef: String, id: String = UUID().uuidString, start: Int, duration: Int, trimStart: Int = 0, trimEnd: Int = 0) -> Clip {
        var c = Fixtures.clip(id: id, mediaRef: mediaRef, start: start, duration: duration, trimStart: trimStart, trimEnd: trimEnd)
        c.multicamGroupId = "group-1"
        return c
    }

    // MARK: - Switch trim math

    @Test func switchRewritesTrimsFromGroupOffsets() {
        let (e, _) = makeEditor()
        // 5s into cam A (group time 5s), 3s long.
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 90, trimStart: 150, trimEnd: 1560)]

        let outcome = e.switchMulticamAngle(clipIds: ["c1"], toAngle: "close")

        #expect(outcome.failures.isEmpty)
        let clip = e.clipFor(id: "c1")!
        #expect(clip.mediaRef == "cam-b")
        // Group time 5s = 3s into cam B (offset 2s) = frame 90; source is 1800 frames.
        #expect(clip.trimStartFrame == 90)
        #expect(clip.trimEndFrame == 1800 - 90 - 90)
        #expect(clip.startFrame == 0)
        #expect(clip.durationFrames == 90)
    }

    @Test func switchAcceptsLabelSpeakerAndMediaPrefix() {
        let (e, group) = makeEditor()
        #expect(group.resolveAngle("Ben")?.mediaRef == "cam-b")
        #expect(group.resolveAngle("wide")?.mediaRef == "cam-a")
        #expect(group.resolveAngle("cam-b")?.mediaRef == "cam-b")
        #expect(group.resolveAngle("nope") == nil)
        _ = e
    }

    @Test func switchFailsWhenAngleDoesNotCoverSpan() {
        let (e, _) = makeEditor()
        // Group time 0.5s: cam B (offset 2s) would need negative source time.
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 30, trimStart: 15)]

        let outcome = e.switchMulticamAngle(clipIds: ["c1"], toAngle: "close")

        #expect(outcome.switchedClipIds.isEmpty)
        #expect(outcome.failures.count == 1)
        #expect(e.clipFor(id: "c1")?.mediaRef == "cam-a")
    }

    @Test func switchUndoRestoresOriginal() {
        let (e, _) = makeEditor()
        let undo = UndoManager()
        e.undoManager = undo
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 90, trimStart: 150)]
        undo.removeAllActions()

        _ = e.switchMulticamAngle(clipIds: ["c1"], toAngle: "close")
        #expect(e.clipFor(id: "c1")?.mediaRef == "cam-b")
        #expect(undo.canUndo)

        undo.undo()
        let clip = e.clipFor(id: "c1")!
        #expect(clip.mediaRef == "cam-a")
        #expect(clip.trimStartFrame == 150)
    }

    // MARK: - Range switching

    @Test func rangeSwitchSplitsAtBoundariesAndSwitchesInside() throws {
        let (e, _) = makeEditor()
        // One 20s clip of cam A at group time 2s (so cam B covers all of it).
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 600, trimStart: 60)]

        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [
            .init(startFrame: 150, endFrame: 300, angle: "close"),
        ])

        #expect(outcome.failures.isEmpty)
        let clips = e.timeline.tracks[0].clips.sorted { $0.startFrame < $1.startFrame }
        #expect(clips.count == 3)
        #expect(clips.map(\.mediaRef) == ["cam-a", "cam-b", "cam-a"])
        // Middle piece: group time = (60+150)/30 = 7s → cam B source 5s = frame 150.
        #expect(clips[1].startFrame == 150)
        #expect(clips[1].durationFrames == 150)
        #expect(clips[1].trimStartFrame == 150)
        // Outer pieces keep cam A source continuity.
        #expect(clips[0].trimStartFrame == 60)
        #expect(clips[2].trimStartFrame == 60 + 300)
    }

    @Test func rangeSwitchBackMergesRedundantCuts() throws {
        let (e, _) = makeEditor()
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 600, trimStart: 60)]

        _ = try e.switchMulticamAngle(groupId: "group-1", switches: [
            .init(startFrame: 150, endFrame: 300, angle: "close"),
        ])
        #expect(e.timeline.tracks[0].clips.count == 3)

        // Switching the middle back to cam A restores one continuous clip.
        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [
            .init(startFrame: 150, endFrame: 300, angle: "wide"),
        ])
        #expect(outcome.mergedCount == 2)
        let clips = e.timeline.tracks[0].clips
        #expect(clips.count == 1)
        #expect(clips[0].startFrame == 0)
        #expect(clips[0].durationFrames == 600)
        #expect(clips[0].trimStartFrame == 60)
        #expect(clips[0].mediaRef == "cam-a")
    }

    @Test func sanitizeKeepsRealCutsApart() {
        let (e, _) = makeEditor()
        // Same media but source-discontinuous (a removed span between them).
        e.timeline.tracks[0].clips = [
            groupClip("cam-a", id: "c1", start: 0, duration: 100, trimStart: 0),
            groupClip("cam-a", id: "c2", start: 100, duration: 100, trimStart: 250),
        ]
        #expect(e.sanitizeMulticamCuts() == 0)
        #expect(e.timeline.tracks[0].clips.count == 2)
    }

    // MARK: - Group creation from timeline clips

    @Test func createGroupFromClipsDerivesOffsetsFromPlacement() throws {
        let (e, _) = makeEditor()
        e.multicamGroups = []
        // Cam B placed so its source t=0 sits 60 frames (2s) after cam A's.
        e.timeline.tracks[0].clips = [
            Fixtures.clip(id: "c1", mediaRef: "cam-a", start: 0, duration: 300),
            Fixtures.clip(id: "c2", mediaRef: "cam-b", start: 60, duration: 300),
        ]
        e.selectedClipIds = ["c1", "c2"]

        let group = try e.createMulticamGroupFromClips(ids: ["c1", "c2"])

        #expect(group.angles.count == 2)
        #expect(group.angle(forMediaRef: "cam-a")?.offsetSeconds == 0)
        #expect(group.angle(forMediaRef: "cam-b")?.offsetSeconds == 2.0)
        #expect(e.clipFor(id: "c1")?.multicamGroupId == group.id)
        #expect(e.clipFor(id: "c2")?.multicamGroupId == group.id)
    }

    // MARK: - Placement

    @Test func placeMulticamTrimsToSharedSpan() throws {
        let (e, _) = makeEditor()
        // Master audio: standalone 100s recording starting 1s before cam A.
        let mic = MediaAsset(id: "mic-1", url: URL(fileURLWithPath: "/tmp/mic.wav"), type: .audio, name: "Mic", duration: 100)
        e.mediaAssets.append(mic)
        e.multicamGroups[0].audioMediaRef = "mic-1"
        e.multicamGroups[0].audioOffsetSeconds = -1.0

        let ids = try e.placeMulticam(groupId: "group-1", atFrame: 0)

        #expect(ids.count == 2)
        let video = e.clipFor(id: ids[0])!
        let audio = e.clipFor(id: ids[1])!
        // Shared span = cam A's 60s (mic covers it fully).
        #expect(video.durationFrames == 1800)
        #expect(video.trimStartFrame == 0)
        #expect(audio.durationFrames == 1800)
        // Mic starts 1s earlier, so the clip skips its first second.
        #expect(audio.trimStartFrame == 30)
        #expect(video.linkGroupId != nil)
        #expect(video.linkGroupId == audio.linkGroupId)
        #expect(video.multicamGroupId == "group-1")
    }

    @Test func fullFrameSwitchTearsDownLayout() throws {
        let (e, _) = makeEditor()
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 600, trimStart: 60)]
        let baseTrackCount = e.timeline.tracks.count

        // Side-by-side over [150, 300): overlay lands on a new top track,
        // base clip takes slot-0 framing.
        var layoutSwitch = EditorViewModel.MulticamSwitch(startFrame: 150, endFrame: 300)
        layoutSwitch.layout = .sideBySide
        layoutSwitch.layoutAngles = ["wide", "close"]
        let layoutOutcome = try e.switchMulticamAngle(groupId: "group-1", switches: [layoutSwitch])
        #expect(layoutOutcome.overlayClipIds.count == 1)
        #expect(e.timeline.tracks.count == baseTrackCount + 1)

        // Full-frame entry over the same frames removes the overlay, its track,
        // and the slot framing.
        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [
            .init(startFrame: 150, endFrame: 300, angle: "close"),
        ])
        #expect(outcome.failures.isEmpty)
        #expect(e.timeline.tracks.count == baseTrackCount)
        let groupClips = e.timeline.tracks.flatMap(\.clips).filter { $0.multicamGroupId == "group-1" }
        #expect(groupClips.allSatisfy { $0.crop.isIdentity })
        let middle = groupClips.first { $0.startFrame == 150 }!
        #expect(middle.mediaRef == "cam-b")
        let asset = e.mediaAssets.first { $0.id == "cam-b" }!
        #expect(middle.transform == e.fitTransform(for: asset))
    }

    @Test func failedFullFrameSwitchLeavesLayoutIntact() throws {
        let (e, _) = makeEditor()
        // A third angle that can't cover the span (offset far past the range).
        let camC = MediaAsset(id: "cam-c", url: URL(fileURLWithPath: "/tmp/c.mov"), type: .video, name: "C", duration: 60)
        e.mediaAssets.append(camC)
        e.multicamGroups[0].angles.append(MulticamAngle(mediaRef: "cam-c", offsetSeconds: 50, label: "far"))
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 600, trimStart: 60)]
        let baseTrackCount = e.timeline.tracks.count

        var layoutSwitch = EditorViewModel.MulticamSwitch(startFrame: 150, endFrame: 300)
        layoutSwitch.layout = .sideBySide
        layoutSwitch.layoutAngles = ["wide", "close"]
        _ = try e.switchMulticamAngle(groupId: "group-1", switches: [layoutSwitch])
        #expect(e.timeline.tracks.count == baseTrackCount + 1)

        // The failed full-frame switch must not dismantle the layout.
        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [
            .init(startFrame: 150, endFrame: 300, angle: "far"),
        ])
        #expect(!outcome.failures.isEmpty)
        #expect(outcome.switchedClipIds.isEmpty)
        #expect(e.timeline.tracks.count == baseTrackCount + 1)
        let middle = e.timeline.tracks.flatMap(\.clips)
            .first { $0.multicamGroupId == "group-1" && $0.startFrame == 150 && $0.mediaRef == "cam-a" }!
        let asset = e.mediaAssets.first { $0.id == "cam-a" }!
        #expect(middle.transform != e.fitTransform(for: asset))
    }

    @Test func reapplyingLayoutReplacesOverlaysInsteadOfStacking() throws {
        let (e, _) = makeEditor()
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 600, trimStart: 60)]
        let baseTrackCount = e.timeline.tracks.count

        var layoutSwitch = EditorViewModel.MulticamSwitch(startFrame: 150, endFrame: 300)
        layoutSwitch.layout = .sideBySide
        layoutSwitch.layoutAngles = ["wide", "close"]
        _ = try e.switchMulticamAngle(groupId: "group-1", switches: [layoutSwitch])
        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [layoutSwitch])

        #expect(outcome.failures.isEmpty)
        #expect(e.timeline.tracks.count == baseTrackCount + 1)
        let overlays = e.timeline.tracks.dropLast(baseTrackCount).flatMap(\.clips)
        #expect(overlays.count == 1)
    }

    @Test func failedLayoutLeavesBaseClipsUntouched() throws {
        let (e, _) = makeEditor()
        let camC = MediaAsset(id: "cam-c", url: URL(fileURLWithPath: "/tmp/c.mov"), type: .video, name: "C", duration: 60)
        e.mediaAssets.append(camC)
        e.multicamGroups[0].angles.append(MulticamAngle(mediaRef: "cam-c", offsetSeconds: 50, label: "far"))
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 600, trimStart: 60)]
        let baseTrackCount = e.timeline.tracks.count

        var layoutSwitch = EditorViewModel.MulticamSwitch(startFrame: 150, endFrame: 300)
        layoutSwitch.layout = .sideBySide
        layoutSwitch.layoutAngles = ["close", "far"]
        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [layoutSwitch])

        #expect(!outcome.failures.isEmpty)
        #expect(outcome.switchedClipIds.isEmpty)
        #expect(outcome.overlayClipIds.isEmpty)
        #expect(e.timeline.tracks.count == baseTrackCount)
        let clips = e.timeline.tracks[0].clips
        #expect(clips.allSatisfy { $0.mediaRef == "cam-a" && $0.crop.isIdentity })
    }

    @Test func rangeSwitchLeavesMasterAudioUncut() throws {
        let (e, _) = makeEditor()
        let mic = MediaAsset(id: "mic-1", url: URL(fileURLWithPath: "/tmp/mic.wav"), type: .audio, name: "Mic", duration: 100)
        e.mediaAssets.append(mic)
        e.multicamGroups[0].audioMediaRef = "mic-1"

        var video = groupClip("cam-a", id: "v", start: 0, duration: 600, trimStart: 60)
        var audio = Fixtures.clip(id: "a", mediaRef: "mic-1", mediaType: .audio, start: 0, duration: 600)
        video.linkGroupId = "lg"
        audio.linkGroupId = "lg"
        e.timeline.tracks[0].clips = [video]
        e.timeline.tracks[1].clips = [audio]

        let outcome = try e.switchMulticamAngle(groupId: "group-1", switches: [
            .init(startFrame: 150, endFrame: 300, angle: "close"),
        ])

        #expect(outcome.failures.isEmpty)
        #expect(e.timeline.tracks[0].clips.count == 3)
        // The master audio stays one continuous clip, no longer hard-linked.
        #expect(e.timeline.tracks[1].clips.count == 1)
        #expect(e.timeline.tracks[1].clips[0].durationFrames == 600)
        #expect(e.timeline.tracks[0].clips.allSatisfy { $0.linkGroupId == nil })
    }

    // MARK: - Delete

    @Test func deleteGroupUntagsClipsAndUndoRestores() throws {
        let (e, _) = makeEditor()
        let undo = UndoManager()
        e.undoManager = undo
        e.timeline.tracks[0].clips = [groupClip("cam-a", id: "c1", start: 0, duration: 100)]
        undo.removeAllActions()

        try e.deleteMulticamGroup(id: "group-1")
        #expect(e.multicamGroups.isEmpty)
        #expect(e.clipFor(id: "c1")?.multicamGroupId == nil)

        undo.undo()
        #expect(e.multicamGroups.count == 1)
        #expect(e.clipFor(id: "c1")?.multicamGroupId == "group-1")
    }

    // MARK: - Labels & offsync

    @Test func clipLabelShowsAngleNameInsteadOfFile() {
        let (e, _) = makeEditor()
        let clip = groupClip("cam-b", start: 0, duration: 100)
        #expect(e.clipDisplayLabel(for: clip) == "close · Ben")
    }

    @Test func inSyncMulticamLinkShowsNoOffsyncBadge() {
        let (e, _) = makeEditor()
        let mic = MediaAsset(id: "mic-1", url: URL(fileURLWithPath: "/tmp/mic.wav"), type: .audio, name: "Mic", duration: 100)
        e.mediaAssets.append(mic)
        e.multicamGroups[0].audioMediaRef = "mic-1"
        e.multicamGroups[0].audioOffsetSeconds = -1.0

        // cam B (offset 2s) with mic (offset −1s): in sync on the group timebase, the
        // mic clip's trimStart runs 3s (90 frames) ahead of the video's.
        var video = groupClip("cam-b", id: "v", start: 0, duration: 100, trimStart: 30)
        var audio = Fixtures.clip(id: "a", mediaRef: "mic-1", mediaType: .audio, start: 0, duration: 100, trimStart: 120)
        video.linkGroupId = "lg"
        audio.linkGroupId = "lg"
        e.timeline.tracks[0].clips = [video]
        e.timeline.tracks[1].clips = [audio]

        #expect(e.linkGroupOffsets().isEmpty)

        // Knock the audio a frame out of sync — the badge comes back.
        e.timeline.tracks[1].clips[0].trimStartFrame = 121
        #expect(!e.linkGroupOffsets().isEmpty)
    }

    // MARK: - Persistence

    @Test func projectFileRoundTripsGroups() throws {
        var file = ProjectFile(timelines: [Fixtures.timeline()], activeTimelineId: nil)
        file.multicamGroups = [
            MulticamGroup(
                id: "g1", name: "Pod",
                angles: [MulticamAngle(mediaRef: "m1", offsetSeconds: 1.25, label: "wide", speaker: "Ana")],
                audioMediaRef: "m2"
            )
        ]
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ProjectFile.self, from: data)
        #expect(decoded.multicamGroups == file.multicamGroups)
    }

    @Test func clipRoundTripsMulticamGroupId() throws {
        let clip = groupClip("cam-a", start: 0, duration: 10)
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        #expect(decoded.multicamGroupId == "group-1")
    }
}
