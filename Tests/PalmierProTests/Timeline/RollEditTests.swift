import Foundation
import Testing
@testable import PalmierPro

@MainActor
@Suite("Roll edit")
struct RollEditTests {

    private func makeEditor() -> EditorViewModel {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(fps: 30, tracks: [Fixtures.videoTrack(), Fixtures.audioTrack()])
        return e
    }

    @Test func rollMovesCutWithoutChangingTotalLength() {
        let e = makeEditor()
        e.timeline.tracks[0].clips = [
            Fixtures.clip(id: "a", mediaRef: "m1", start: 0, duration: 100, trimStart: 0, trimEnd: 50),
            Fixtures.clip(id: "b", mediaRef: "m2", start: 100, duration: 100, trimStart: 40, trimEnd: 0),
        ]

        let applied = e.rollEdit(leftId: "a", rightId: "b", deltaFrames: 20)

        #expect(applied == 20)
        let a = e.clipFor(id: "a")!, b = e.clipFor(id: "b")!
        #expect(a.durationFrames == 120)
        #expect(a.trimEndFrame == 30)
        #expect(b.startFrame == 120)
        #expect(b.durationFrames == 80)
        #expect(b.trimStartFrame == 60)
        #expect(a.endFrame == b.startFrame)
        #expect(a.durationFrames + b.durationFrames == 200)
    }

    @Test func rollClampsToSourceHeadroom() {
        let e = makeEditor()
        e.timeline.tracks[0].clips = [
            Fixtures.clip(id: "a", mediaRef: "m1", start: 0, duration: 100, trimEnd: 10),
            Fixtures.clip(id: "b", mediaRef: "m2", start: 100, duration: 100, trimStart: 5),
        ]

        // Left clip has only 10 source frames past its tail.
        #expect(e.rollEdit(leftId: "a", rightId: "b", deltaFrames: 50) == 10)
        // Right clip has only 5 source frames before its head.
        #expect(e.rollEdit(leftId: "a", rightId: "b", deltaFrames: -50) == -15)
        let b = e.clipFor(id: "b")!
        #expect(b.trimStartFrame == 0)
    }

    @Test func rollPropagatesToLinkedPairSharingTheCut() {
        let e = makeEditor()
        var v1 = Fixtures.clip(id: "v1", mediaRef: "m1", start: 0, duration: 100, trimEnd: 500)
        var v2 = Fixtures.clip(id: "v2", mediaRef: "m2", start: 100, duration: 100, trimStart: 100)
        var a1 = Fixtures.clip(id: "a1", mediaRef: "m1", mediaType: .audio, start: 0, duration: 100, trimEnd: 500)
        var a2 = Fixtures.clip(id: "a2", mediaRef: "m2", mediaType: .audio, start: 100, duration: 100, trimStart: 100)
        v1.linkGroupId = "g1"; a1.linkGroupId = "g1"
        v2.linkGroupId = "g2"; a2.linkGroupId = "g2"
        e.timeline.tracks[0].clips = [v1, v2]
        e.timeline.tracks[1].clips = [a1, a2]

        // Rolling the video cut needs partners of BOTH sides linked across the cut;
        // here a1 is v1's partner and a2 is v2's, and both butt at frame 100.
        let plan = e.planRoll(leftId: "v1", rightId: "v2", propagateToLinked: true)
        #expect(plan?.pairs.count == 2)

        e.rollEdit(leftId: "v1", rightId: "v2", deltaFrames: 10)
        #expect(e.clipFor(id: "v1")?.durationFrames == 110)
        #expect(e.clipFor(id: "a1")?.durationFrames == 110)
        #expect(e.clipFor(id: "a2")?.startFrame == 110)
        #expect(e.clipFor(id: "a2")?.durationFrames == 90)
    }

    @Test func rollPairsPartnerCutEvenWhenOtherSideUnlinked() {
        let e = makeEditor()
        // v1↔a1 linked; v2 and a2 unlinked. The audio cut must still roll with the video cut.
        var v1 = Fixtures.clip(id: "v1", mediaRef: "m1", start: 0, duration: 100, trimEnd: 500)
        let v2 = Fixtures.clip(id: "v2", mediaRef: "m2", start: 100, duration: 100, trimStart: 100)
        var a1 = Fixtures.clip(id: "a1", mediaRef: "m1", mediaType: .audio, start: 0, duration: 100, trimEnd: 500)
        let a2 = Fixtures.clip(id: "a2", mediaRef: "m2", mediaType: .audio, start: 100, duration: 100, trimStart: 100)
        v1.linkGroupId = "g1"; a1.linkGroupId = "g1"
        e.timeline.tracks[0].clips = [v1, v2]
        e.timeline.tracks[1].clips = [a1, a2]

        let plan = e.planRoll(leftId: "v1", rightId: "v2", propagateToLinked: true)
        #expect(plan?.pairs.count == 2)

        e.rollEdit(leftId: "v1", rightId: "v2", deltaFrames: 10)
        #expect(e.clipFor(id: "a1")?.durationFrames == 110)
        #expect(e.clipFor(id: "a2")?.startFrame == 110)
    }

    @Test func rollRefusesWhenLinkedPartnerHasNoButtedNeighbor() {
        let e = makeEditor()
        // a1 shares the cut frame but nothing butts it — rolling would desync v1/a1.
        var v1 = Fixtures.clip(id: "v1", mediaRef: "m1", start: 0, duration: 100, trimEnd: 500)
        let v2 = Fixtures.clip(id: "v2", mediaRef: "m2", start: 100, duration: 100, trimStart: 100)
        var a1 = Fixtures.clip(id: "a1", mediaRef: "m1", mediaType: .audio, start: 0, duration: 100, trimEnd: 500)
        v1.linkGroupId = "g1"; a1.linkGroupId = "g1"
        e.timeline.tracks[0].clips = [v1, v2]
        e.timeline.tracks[1].clips = [a1]

        #expect(e.planRoll(leftId: "v1", rightId: "v2", propagateToLinked: true) == nil)
        #expect(e.rollEdit(leftId: "v1", rightId: "v2", deltaFrames: 10) == 0)
        #expect(e.clipFor(id: "v1")?.durationFrames == 100)
    }

    @Test func batchRollsAreAtomicOnFailure() {
        let e = makeEditor()
        e.timeline.tracks[0].clips = [
            Fixtures.clip(id: "a", mediaRef: "m1", start: 0, duration: 100, trimEnd: 100),
            Fixtures.clip(id: "b", mediaRef: "m2", start: 100, duration: 100, trimStart: 0),
            Fixtures.clip(id: "c", mediaRef: "m3", start: 200, duration: 100, trimStart: 50),
        ]

        // Second roll has zero headroom (b.trimEnd is 0), so the whole batch must revert.
        #expect(throws: EditorViewModel.RollError.self) {
            try e.rollEdits([
                (leftId: "a", rightId: "b", deltaFrames: 20),
                (leftId: "b", rightId: "c", deltaFrames: 20),
            ])
        }
        #expect(e.clipFor(id: "a")?.durationFrames == 100)
        #expect(e.clipFor(id: "b")?.startFrame == 100)
        #expect(e.clipFor(id: "b")?.trimStartFrame == 0)
    }

    @Test func rollUndoRestoresBothClips() {
        let e = makeEditor()
        let undo = UndoManager()
        e.undoManager = undo
        e.timeline.tracks[0].clips = [
            Fixtures.clip(id: "a", mediaRef: "m1", start: 0, duration: 100, trimEnd: 100),
            Fixtures.clip(id: "b", mediaRef: "m2", start: 100, duration: 100, trimStart: 50),
        ]
        undo.removeAllActions()

        e.rollEdit(leftId: "a", rightId: "b", deltaFrames: 25)
        #expect(e.clipFor(id: "b")?.startFrame == 125)

        undo.undo()
        #expect(e.clipFor(id: "a")?.durationFrames == 100)
        #expect(e.clipFor(id: "b")?.startFrame == 100)
        #expect(e.clipFor(id: "b")?.trimStartFrame == 50)
    }

    @Test func neighborLookupRequiresButtedCut() {
        let e = makeEditor()
        e.timeline.tracks[0].clips = [
            Fixtures.clip(id: "a", mediaRef: "m1", start: 0, duration: 100),
            Fixtures.clip(id: "b", mediaRef: "m2", start: 110, duration: 100),
        ]
        #expect(e.rollNeighbor(of: "a", edge: .right) == nil)
        #expect(e.rollEdit(leftId: "a", rightId: "b", deltaFrames: 10) == 0)
    }
}
