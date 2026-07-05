import SwiftUI

/// Session speaker identity for the try-it UI: identify → registry rows + waveform tint masks.
struct ProjectSpeaker: Identifiable {
    let id: Int
    var name: String
    var color: Color
}

extension EditorViewModel {

    static let speakerPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .indigo]

    /// Pushes the current tint palette to the renderer; call after any speaker/toggle change.
    func syncSpeakerColors() {
        ClipRenderer.speakerColors = markSpeakers
            ? Dictionary(uniqueKeysWithValues: projectSpeakers.map {
                ($0.id, NSColor($0.color).withAlphaComponent(AppTheme.Opacity.prominent).cgColor)
            })
            : [:]
        mediaVisualCache.timelineView?.needsDisplay = true
    }

    func removeSpeaker(id: Int) {
        projectSpeakers.removeAll { $0.id == id }
        for (ref, mask) in mediaVisualCache.speakerMasks {
            mediaVisualCache.speakerMasks[ref] = mask.map { $0 == id ? -1 : $0 }
        }
        syncSpeakerColors()
    }

    /// `transcribeMissing` is the explicit button only — it costs credits; the auto-run stays cached-only.
    func identifySpeakers(transcribeMissing: Bool = false) {
        guard !speakerIdentifyInFlight else { return }
        if transcribeMissing, !AccountService.shared.isSignedIn {
            speakerIdentifyError = "Sign in to use Cloud transcription."
            return
        }
        speakerIdentifyPhase = transcribeMissing ? "Transcribing…" : "Identifying…"
        speakerIdentifyError = nil
        let projectId = self.projectId
        let assets = mediaAssets.filter { $0.type == .audio || ($0.type == .video && $0.hasAudio) }
        // Cloud transcripts cache under the transcribed source range; mirror the transcript tool's math.
        let rate = Double(max(1, timeline.fps))
        var rangesByRef: [String: ClosedRange<Double>] = [:]
        for clip in captionTargets(ids: []) {
            let span = CaptionTranscriptMapper.sourceSpan(for: clip)
            guard span.end > span.start else { continue }
            let range = max(Double(span.start) / rate - 1.0, 0)...(Double(span.end) / rate + 1.0)
            if let existing = rangesByRef[clip.mediaRef] {
                rangesByRef[clip.mediaRef] = min(existing.lowerBound, range.lowerBound)...max(existing.upperBound, range.upperBound)
            } else {
                rangesByRef[clip.mediaRef] = range
            }
        }
        Task { [weak self] in
            var files: [(mediaRef: String, url: URL, turns: [SpeakerIdentity.Turn])] = []
            for asset in assets {
                var found = await TranscriptCache.shared.cachedCloudTranscript(for: asset.url, range: rangesByRef[asset.id], language: nil)
                if found == nil {
                    found = await TranscriptCache.shared.cachedCloudTranscript(for: asset.url, range: nil, language: nil)
                }
                if found == nil, transcribeMissing, rangesByRef[asset.id] != nil {
                    do {
                        found = try await CloudTranscription.transcribe(
                            fileURL: asset.url, range: rangesByRef[asset.id],
                            preferredLocale: nil, projectId: projectId
                        )
                    } catch {
                        Log.preview.error("identify speakers: transcription failed for \(asset.id): \(Log.detail(error))")
                        if self?.speakerIdentifyError == nil {
                            self?.speakerIdentifyError = Log.detail(error)
                        }
                    }
                }
                guard let transcript = found else {
                    Log.preview.notice("identify speakers: no cached cloud transcript for \(asset.id)")
                    continue
                }
                let turns = await SpeakerIdentity.speechConfirmed(
                    SpeakerIdentity.turns(from: transcript), url: asset.url, mediaRef: asset.id
                )
                if !turns.isEmpty { files.append((asset.id, asset.url, turns)) }
            }
            Log.preview.notice("identify speakers: \(files.count) files with speaker turns")
            self?.speakerIdentifyPhase = "Identifying…"
            let map = await SpeakerIdentity.globalLabels(files: files)
            guard let self else { return }
            await MainActor.run { [self] in
                self.applySpeakerIdentity(files: files, map: map)
                self.speakerIdentifyPhase = nil
            }
        }
    }

    private func applySpeakerIdentity(files: [(mediaRef: String, url: URL, turns: [SpeakerIdentity.Turn])], map: [String: [String: String]]) {
        var gidByLabel: [String: Int] = [:]
        var speakers: [Int: ProjectSpeaker] = [:]
        var masks: [String: [Int]] = [:]
        for file in files {
            guard let duration = mediaAssets.first(where: { $0.id == file.mediaRef })?.duration, duration > 0 else { continue }
            let cellCount = Int(duration / VoiceActivity.chunkDuration) + 1
            var mask = [Int](repeating: -1, count: cellCount)
            for turn in file.turns {
                // Aligned files share global labels; unaligned ones stay distinct per file.
                let label = map[file.mediaRef]?[turn.speaker] ?? "\(file.mediaRef)·\(turn.speaker)"
                let gid: Int
                if let existing = gidByLabel[label] {
                    gid = existing
                } else {
                    gid = gidByLabel.count + 1
                    gidByLabel[label] = gid
                    speakers[gid] = ProjectSpeaker(
                        id: gid, name: "Speaker \(gid)",
                        color: Self.speakerPalette[(gid - 1) % Self.speakerPalette.count]
                    )
                }
                let lo = max(0, Int(turn.start / VoiceActivity.chunkDuration))
                let hi = min(cellCount, Int((turn.end / VoiceActivity.chunkDuration).rounded(.up)))
                if lo < hi { for c in lo..<hi { mask[c] = gid } }
            }
            masks[file.mediaRef] = mask
        }
        projectSpeakers = speakers.values.sorted { $0.id < $1.id }
        mediaVisualCache.speakerMasks = masks
        syncSpeakerColors()
    }
}
