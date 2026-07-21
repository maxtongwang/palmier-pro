// Shared caption-edit → glossary promotion. Both MCP update_text and the inspector text-commit run this
// one chain, so a human correction teaches the glossary identically to an agent's and the two can't drift.
// §5.1 (mark clean) lives here; §5.2 (sibling resync) and the response/toast are the caller's. refs feature/glossary

import Foundation

extension EditorViewModel {
    /// A caption edit that promoted into the glossary. `canonical`/`variant` are the classifier's spans
    /// (drive §5.2 resync); `storedCanonical`/`storedVariants` are what actually landed after validation
    /// (drive the response row and the toast).
    struct CaptionEditPromotion: Equatable, Sendable {
        let clipId: String
        let canonical: String
        let variant: String
        let storedCanonical: String
        let storedVariants: [String]
    }

    /// Classify one caption content edit; if it's a clean single-substitution on a grouped caption, write
    /// it to the library glossary as an asserted term and mark the clip clean (§5.1) so later resyncs don't
    /// log a false conflict. Returns nil for any non-promotable edit. The glossary write is deliberately
    /// outside undo — undoing the text edit does not un-learn the term (glossary_remove reverses it).
    func promoteCaptionEditIfClean(old: String, new: String, clipId: String) -> CaptionEditPromotion? {
        guard clipFor(id: clipId)?.captionGroupId != nil else { return nil }
        guard case let .promote(promotion) = GlossaryClassifier.classifyWithReason(old: old, new: new),
              let stored = writeAssertedCaptionTerm(canonical: promotion.canonical, variant: promotion.variant, clipId: clipId)
        else { return nil }
        commitClipProperties(clipIds: [clipId]) { $0.generatedText = new }
        return CaptionEditPromotion(
            clipId: clipId, canonical: promotion.canonical, variant: promotion.variant,
            storedCanonical: stored.canonical, storedVariants: stored.variants
        )
    }

    /// Upsert an asserted caption-edit correction into the LIBRARY glossary (speaker/domain knowledge,
    /// reused across projects). MERGES with any existing same-canonical entry — several clips can carry
    /// different mis-hearings of one canonical — and upgrades an inferred (suggestion-only) entry to
    /// asserted: the user actively typed this correction, so it must auto-apply. nil if validation
    /// drops the variant or the write fails.
    private func writeAssertedCaptionTerm(canonical: String, variant: String, clipId: String) -> (canonical: String, variants: [String])? {
        let existing = (try? GlossaryStore.read(scope: .library, projectURL: projectURL))?
            .terms.first { $0.canonical == canonical }
        var variants = existing?.variants ?? []
        if !variants.contains(variant) { variants.append(variant) }
        let confidence = existing.map { $0.confidence.autoApplies ? $0.confidence : .asserted } ?? .asserted
        let term = GlossaryTerm(
            canonical: canonical, variants: variants,
            provenance: existing?.provenance ?? "auto:caption-edit@\(clipId)", confidence: confidence
        )
        do {
            let result = try glossaryWriteUpsert(term, scope: .library)
            guard !result.term.variants.isEmpty else { return nil }
            return (result.term.canonical, result.term.variants)
        } catch {
            // A failed write must not masquerade as "nothing to promote" — the caption edit looked
            // learned but wasn't persisted.
            Log.agent.warning("caption-edit promotion write failed clip=\(clipId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Inspector-origin caption edit: run the shared promotion chain and, on a promotion, resync sibling
    /// captions (§5.2) and surface a success toast — the visible proof that a human correction taught the
    /// glossary just like an agent's would. Silent on non-promotion.
    func promoteInspectorCaptionEdit(old: String, new: String, clipId: String) {
        guard let promotion = promoteCaptionEditIfClean(old: old, new: new, clipId: clipId) else { return }
        resyncCaptionsForGlossaryTerm(strings: [promotion.canonical, promotion.variant], trigger: "glossary_promotion")
        _ = takeResyncReport()  // deliberate promotion — don't also fire the A1 reactive-resync toast
        mediaPanelToast = MediaPanelToast(message: "Learned \(promotion.storedCanonical) — future transcripts corrected.", kind: .success)
    }
}
