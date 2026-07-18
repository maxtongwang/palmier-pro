// TimelineTranscriptProvider — cache-only CaptionWordSource for reactive resync. Reads transcripts
// already on disk, materialises the project glossary onto them (the same correction caption
// GENERATION applies via applyingGlossary), then maps their words to project frames. Never triggers
// ASR and never writes, which is the L1/L2 read-only guarantee the resync engine depends on.

import Foundation

final class TimelineTranscriptProvider: CaptionWordSource {
    struct Fragment { let clip: Clip; let url: URL; let mediaRef: String }
    private let fragments: [Fragment]
    private let fps: Int
    // Loaded once per provider (one resync = one glossary load) and applied per unique cached read,
    // so resync sees exactly the corrected text generation produced instead of the raw mis-heard ASR.
    private let corrector: GlossaryCorrector
    private let read: (URL) -> TranscriptionResult?
    private var transcripts: [URL: TranscriptionResult?] = [:]  // memoized materialised reads; stored nil = no cache

    /// Snapshots the editor's audible source clips (the same set get_transcript uses) on the main actor.
    @MainActor
    init(editor: EditorViewModel) {
        var frags: [Fragment] = []
        for clip in editor.captionTargets(ids: []) {
            guard let url = editor.mediaResolver.resolveURL(for: clip.mediaRef) else { continue }
            frags.append(Fragment(clip: clip, url: url, mediaRef: clip.mediaRef))
        }
        self.fragments = frags
        self.fps = editor.timeline.fps
        self.corrector = GlossaryStore.load(projectURL: editor.projectURL).corrector()
        self.read = { TranscriptCache.cachedOnDisk(for: $0) }
    }

    /// Test seam: inject fragments, the glossary corrector, and the raw-transcript reader directly.
    init(
        fragments: [Fragment],
        fps: Int,
        corrector: GlossaryCorrector,
        read: @escaping (URL) -> TranscriptionResult? = { TranscriptCache.cachedOnDisk(for: $0) }
    ) {
        self.fragments = fragments
        self.fps = fps
        self.corrector = corrector
        self.read = read
    }

    func audibleWords(in range: Range<Int>) -> [WordTiming] {
        var out: [WordTiming] = []
        for frag in fragmentsIntersecting(range) {
            guard let transcript = transcript(for: frag.url) else { continue }
            for w in CaptionTranscriptMapper.timelineWords(from: transcript, clip: frag.clip, fps: fps)
            where w.startFrame < range.upperBound && w.endFrame > range.lowerBound {
                out.append(w)
            }
        }
        return out.sorted { ($0.startFrame, $0.endFrame) < ($1.startFrame, $1.endFrame) }
    }

    func uncachedRefs(in range: Range<Int>) -> [String] {
        var refs: [String] = []
        var seen = Set<String>()
        for frag in fragmentsIntersecting(range) where transcript(for: frag.url) == nil {
            if seen.insert(frag.mediaRef).inserted { refs.append(frag.mediaRef) }
        }
        return refs
    }

    private func fragmentsIntersecting(_ range: Range<Int>) -> [Fragment] {
        fragments.filter { $0.clip.startFrame < range.upperBound && $0.clip.endFrame > range.lowerBound }
    }

    private func transcript(for url: URL) -> TranscriptionResult? {
        if let memo = transcripts[url] { return memo }
        let loaded = read(url).map { $0.applyingGlossary(corrector) }
        transcripts[url] = loaded
        return loaded
    }
}
