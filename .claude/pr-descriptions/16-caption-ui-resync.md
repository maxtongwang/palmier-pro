# feat: resync visibility — toast, conflict badge, freeze toggle, inspector promotion parity

**Branch:** `feature/caption-ui-resync` · **Depends on:** caption-resync, glossary, glossary-persistence

## Summary

The automatic caption machinery was invisible to hands-on editors: a trim silently rewrote or removed captions, flagged conflicts had no visual, the persisted freeze flag was unreachable, and a human's caption correction taught the glossary nothing while an agent's identical edit auto-promoted.

## What's included

- **Resync toast** on human-initiated edits whose reactive resync changed captions ("Captions resynced · 3 updated, 1 removed."), with structural origin inference — agent tool calls consume their reports for the delta, so anything left at mouse-up is human; stranded reports from errored tool calls are cleared at drag start so no phantom toasts. Retimed-only changes stay silent.
- **Timeline conflict badge**: caption clips with `resyncConflict` draw a small amber pill (dot fallback when narrow) via the existing badge idiom — display-only, theme-constant styled.
- **Inspector conflict row** with deterministic resolution: "Keep mine" (clears the flag) and "Use transcript" (overwrite-scoped resync on exactly the flagged clips). Both undoable.
- **"Freeze captions" toggle**: commits `resyncExempt` group-wide — the previously-unreachable persisted flag becomes usable; engine exclusion pinned by test.
- **Default conflict policy `preserve` → `flag`**: manual text is kept identically either way; flag additionally sets the visible marker, which the new UI makes actionable. `preserve` remains selectable.
- **Inspector-edit promotion parity**: the inspector text-commit path runs the same promotion chain as MCP `update_text` via a single shared VM implementation (classifier, widened-span guards, §5.1 mark-clean, §5.2 sibling resync), with a "Learned <term>" success toast making the learning visible.

## Testing

Toast-decision matrix, resolve semantics, engine exemption, promotion-parity (identical outcomes MCP vs inspector, no double-promotion), policy-flip pins. Full suite green.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
