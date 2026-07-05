import AppKit

extension TimelineView {

    /// "Switch Angle" submenu for group clips, or "Create Multicam Group" for a
    /// multi-camera selection. Empty when neither applies.
    func multicamMenuItems(for clip: Clip) -> [NSMenuItem] {
        if clip.mediaType == .video, let group = editor.multicamGroup(forClip: clip.id) {
            let submenu = NSMenu()
            let targets = multicamSwitchTargets(for: clip, group: group)
            for angle in group.angles {
                let item = NSMenuItem(title: MulticamGroup.displayName(angle), action: #selector(performSwitchAngle(_:)), keyEquivalent: "")
                item.target = self
                item.state = angle.mediaRef == clip.mediaRef ? .on : .off
                item.representedObject = ["angle": angle.mediaRef, "clipIds": targets] as [String: Any]
                submenu.addItem(item)
            }
            let switchItem = NSMenuItem(title: "Switch Angle", action: nil, keyEquivalent: "")
            switchItem.submenu = submenu

            let deleteItem = NSMenuItem(title: "Delete Multicam Group", action: #selector(performDeleteMulticamGroup(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = group.id
            return [switchItem, deleteItem]
        }
        if let candidates = multicamCreationCandidates(including: clip) {
            let item = NSMenuItem(title: "Create Multicam Group", action: #selector(performCreateMulticamGroup(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Array(candidates)
            return [item]
        }
        return []
    }

    /// Selected video clips of the same group, falling back to the clicked clip.
    private func multicamSwitchTargets(for clip: Clip, group: MulticamGroup) -> [String] {
        let selected = editor.selectedClipIds.compactMap(editor.clipFor(id:)).filter {
            $0.mediaType == .video && $0.multicamGroupId == clip.multicamGroupId
        }
        return selected.contains(where: { $0.id == clip.id }) ? selected.map(\.id) : [clip.id]
    }

    /// Selection eligible for grouping: 2+ cameras, no clip already grouped, all at 1×.
    private func multicamCreationCandidates(including clip: Clip) -> Set<String>? {
        var ids = editor.selectedClipIds
        ids.insert(clip.id)
        let clips = ids.compactMap(editor.clipFor(id:))
        let videos = clips.filter { $0.mediaType == .video && $0.sourceClipType != .sequence }
        guard videos.count >= 2,
              Set(videos.map(\.mediaRef)).count >= 2,
              videos.allSatisfy({ $0.multicamGroupId == nil && $0.speed == 1.0 })
        else { return nil }
        return ids
    }

    @objc func performSwitchAngle(_ sender: Any?) {
        guard let info = (sender as? NSMenuItem)?.representedObject as? [String: Any],
              let angle = info["angle"] as? String,
              let clipIds = info["clipIds"] as? [String], !clipIds.isEmpty else { return }
        let outcome = editor.switchMulticamAngle(clipIds: clipIds, toAngle: angle)
        if outcome.switchedClipIds.isEmpty, let failure = outcome.failures.first {
            editor.mediaPanelToast = MediaPanelToast(message: failure.message, kind: .warning)
        }
        needsDisplay = true
    }

    @objc func performDeleteMulticamGroup(_ sender: Any?) {
        guard let groupId = (sender as? NSMenuItem)?.representedObject as? String else { return }
        let name = editor.multicamGroup(id: groupId)?.name ?? "Multicam"
        do {
            try editor.deleteMulticamGroup(id: groupId)
            editor.mediaPanelToast = MediaPanelToast(message: "Deleted \(name).", kind: .success)
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription, kind: .warning)
        }
        needsDisplay = true
    }

    @objc func performCreateMulticamGroup(_ sender: Any?) {
        guard let ids = (sender as? NSMenuItem)?.representedObject as? [String] else { return }
        do {
            let group = try editor.createMulticamGroupFromClips(ids: Set(ids))
            editor.mediaPanelToast = MediaPanelToast(
                message: "Created \(group.name) with \(group.angles.count) angles.",
                kind: .success
            )
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription, kind: .warning)
        }
        needsDisplay = true
    }
}
