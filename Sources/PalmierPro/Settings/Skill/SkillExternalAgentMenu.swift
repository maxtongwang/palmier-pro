import AppKit
import SwiftUI

struct SkillExternalAgentMenu: View {
    let skill: Skill
    let store: SkillStore
    let onCopied: (SkillExternalAgent, URL) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("Add to External Agent")
                Image(systemName: "chevron.down")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
            }
        }
        .buttonStyle(.capsule(.secondary, fill: AnyShapeStyle(AppTheme.Background.raisedColor)))
        .help("Add this skill to an external agent")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
                ForEach(SkillExternalAgent.allCases, id: \.self) { agent in
                    Button {
                        if let url = store.copy(skill, to: agent) {
                            onCopied(agent, url)
                        }
                        isPresented = false
                    } label: {
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            SkillAgentLogo(agent: agent)
                            Text("Add to \(agent.label)")
                                .font(.system(size: AppTheme.FontSize.sm))
                                .foregroundStyle(AppTheme.Text.primaryColor)
                            Spacer(minLength: AppTheme.Spacing.sm)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .hoverHighlight(cornerRadius: AppTheme.Radius.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
            .frame(minWidth: AppTheme.Settings.skillMenuWidth)
        }
    }
}

private struct SkillAgentLogo: View {
    let agent: SkillExternalAgent

    var body: some View {
        Group {
            if let image = SkillAgentAssets.image(for: agent) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
        }
        .frame(width: AppTheme.IconSize.sm, height: AppTheme.IconSize.sm)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
        .accessibilityHidden(true)
    }
}

private enum SkillAgentAssets {
    static func image(for agent: SkillExternalAgent) -> NSImage? {
        switch agent {
        case .claude: claude
        case .codex: codex
        case .cursor: cursor
        }
    }

    private static let claude = load("claude")
    private static let codex = load("codex")
    private static let cursor = load("cursor")

    private static func load(_ name: String) -> NSImage? {
        guard let root = Bundle.main.resourceURL else { return nil }
        let path = "Images/Agents/\(name).png"
        let candidates = [
            root.appendingPathComponent(path),
            root.appendingPathComponent("PalmierPro_PalmierPro.bundle/\(path)"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}
