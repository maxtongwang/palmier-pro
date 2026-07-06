import AppKit

extension TimelineView {
    @objc func performDetectBeats(_ sender: Any?) {
        guard let mediaRef = (sender as? NSMenuItem)?.representedObject as? String,
              let asset = editor.mediaAssets.first(where: { $0.id == mediaRef }) else { return }
        let force = editor.mediaVisualCache.beats.analysis(for: mediaRef) != nil
        editor.mediaVisualCache.beats.generate(for: asset, force: force) { [weak self] analysis in
            guard let self else { return }
            if let analysis, !analysis.beats.isEmpty {
                editor.mediaPanelToast = MediaPanelToast(
                    message: "Detected \(Int(analysis.bpm.rounded())) BPM, \(analysis.beats.count) beats.",
                    kind: .success
                )
            } else {
                editor.mediaPanelToast = MediaPanelToast(message: "No beats detected.", kind: .warning)
            }
            needsDisplay = true
        }
    }
}
