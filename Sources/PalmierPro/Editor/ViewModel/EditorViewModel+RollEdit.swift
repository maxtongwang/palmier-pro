import Foundation

/// Roll edit: slide the cut between two adjacent clips without changing total length.
/// The left clip's tail extends/shrinks while the right clip's head does the inverse.
extension EditorViewModel {

    struct RollPlan {
        /// Boundary pairs that move together: the grabbed pair plus linked partners
        /// sharing the same cut (a-roll video + its audio).
        var pairs: [(leftId: String, rightId: String)]
        var boundaryFrame: Int
        var minDelta: Int
        var maxDelta: Int
    }

    /// The clip that starts exactly where `clip` ends, on the same track.
    func rollNeighbor(of clipId: String, edge: TrimEdge) -> Clip? {
        guard let loc = findClip(id: clipId) else { return nil }
        let clip = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
        return timeline.tracks[loc.trackIndex].clips.first {
            edge == .right ? $0.startFrame == clip.endFrame : $0.endFrame == clip.startFrame
        }
    }

    /// Builds the pair set and delta clamps for rolling the cut between two adjacent clips.
    func planRoll(leftId: String, rightId: String, propagateToLinked: Bool) -> RollPlan? {
        guard let left = clipFor(id: leftId), let right = clipFor(id: rightId),
              left.endFrame == right.startFrame else { return nil }
        let boundary = right.startFrame

        var pairs: [(leftId: String, rightId: String)] = [(leftId, rightId)]
        if propagateToLinked {
            var seen: Set<String> = ["\(leftId)|\(rightId)"]
            // Every linked partner sharing this cut must roll with it, whichever side
            // it hangs off; a partner cut that can't pair would fall out of sync — refuse.
            for partnerId in linkedPartnerIds(of: leftId) {
                guard let partner = clipFor(id: partnerId), partner.endFrame == boundary else { continue }
                guard let neighbor = rollNeighbor(of: partnerId, edge: .right) else { return nil }
                if seen.insert("\(partnerId)|\(neighbor.id)").inserted {
                    pairs.append((partnerId, neighbor.id))
                }
            }
            for partnerId in linkedPartnerIds(of: rightId) {
                guard let partner = clipFor(id: partnerId), partner.startFrame == boundary else { continue }
                guard let neighbor = rollNeighbor(of: partnerId, edge: .left) else { return nil }
                if seen.insert("\(neighbor.id)|\(partnerId)").inserted {
                    pairs.append((neighbor.id, partnerId))
                }
            }
        }

        var minDelta = Int.min
        var maxDelta = Int.max
        for pair in pairs {
            guard let l = clipFor(id: pair.leftId), let r = clipFor(id: pair.rightId) else { continue }
            let lUnbounded = l.mediaType == .image || l.mediaType == .text
            let rUnbounded = r.mediaType == .image || r.mediaType == .text
            // Positive delta: left tail extends into its remaining source; right shrinks.
            var hi = r.durationFrames - 1
            if !lUnbounded { hi = min(hi, Int((Double(l.trimEndFrame) / l.speed).rounded(.down))) }
            // Negative delta: left shrinks; right head extends into earlier source.
            var lo = -(l.durationFrames - 1)
            if !rUnbounded { lo = max(lo, -Int((Double(r.trimStartFrame) / r.speed).rounded(.down))) }
            minDelta = max(minDelta, lo)
            maxDelta = min(maxDelta, hi)
        }
        guard minDelta <= maxDelta else { return nil }
        return RollPlan(pairs: pairs, boundaryFrame: boundary, minDelta: minDelta, maxDelta: maxDelta)
    }

    /// Applies a roll as one undoable action. Returns the applied (clamped) delta.
    @discardableResult
    func rollEdit(leftId: String, rightId: String, deltaFrames: Int, propagateToLinked: Bool = true) -> Int {
        guard let plan = planRoll(leftId: leftId, rightId: rightId, propagateToLinked: propagateToLinked) else { return 0 }
        let delta = max(plan.minDelta, min(plan.maxDelta, deltaFrames))
        guard delta != 0 else { return 0 }

        withTimelineSwap(actionName: "Roll Edit") {
            applyRoll(plan, delta: delta)
        }
        return delta
    }

    struct RollError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Applies several rolls atomically: one undo step, and any failure restores the
    /// timeline untouched before throwing. Returns the applied (clamped) deltas.
    @discardableResult
    func rollEdits(_ rolls: [(leftId: String, rightId: String, deltaFrames: Int)]) throws -> [Int] {
        var applied: [Int] = []
        var failure: RollError?
        withTimelineSwap(actionName: rolls.count == 1 ? "Roll Edit" : "Roll Edits") {
            let snapshot = timeline
            for (i, roll) in rolls.enumerated() {
                guard let plan = planRoll(leftId: roll.leftId, rightId: roll.rightId, propagateToLinked: true) else {
                    failure = RollError(message: "rolls[\(i)]: the clips no longer meet at a rollable cut (a linked clip may share the cut without a butted neighbor).")
                    break
                }
                let delta = max(plan.minDelta, min(plan.maxDelta, roll.deltaFrames))
                guard delta != 0 else {
                    failure = RollError(message: "rolls[\(i)]: no headroom to roll this cut in that direction (source material or 1-frame minimum reached).")
                    break
                }
                applyRoll(plan, delta: delta)
                applied.append(delta)
            }
            if failure != nil { timeline = snapshot }
        }
        if let failure { throw failure }
        return applied
    }

    private func applyRoll(_ plan: RollPlan, delta: Int) {
        for pair in plan.pairs {
            if let loc = findClip(id: pair.leftId) {
                var clip = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
                let sourceDelta = Int((Double(delta) * clip.speed).rounded())
                clip.trimEndFrame -= sourceDelta
                clip.setDuration(clip.durationFrames + delta)
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex] = clip
            }
            if let loc = findClip(id: pair.rightId) {
                var clip = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
                let sourceDelta = Int((Double(delta) * clip.speed).rounded())
                clip.trimStartFrame += sourceDelta
                clip.startFrame += delta
                clip.setDuration(clip.durationFrames - delta)
                timeline.tracks[loc.trackIndex].clips[loc.clipIndex] = clip
            }
        }
    }
}
