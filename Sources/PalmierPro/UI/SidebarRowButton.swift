import SwiftUI

struct SidebarRowButton: View {
    let label: String
    let systemImage: String
    var isSelected: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.smMd) {
                Image(systemName: systemImage)
                    .font(.system(size: AppTheme.FontSize.md))
                    .frame(width: AppTheme.IconSize.sm)
                Text(label)
                    .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .foregroundStyle(AppTheme.Text.primaryColor)
            .background(Capsule(style: .continuous).fill(rowFill))
            .contentShape(Capsule(style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: isHovered)
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var rowFill: Color {
        switch (isSelected, isHovered) {
        case (true, true): Color.white.opacity(AppTheme.Opacity.muted)
        case (true, false): Color.white.opacity(AppTheme.Opacity.soft)
        case (false, true): Color.white.opacity(AppTheme.Opacity.faint)
        case (false, false): .clear
        }
    }
}
