import SwiftUI

// Shared bottom-sheet content for the voting flow: icon + title + body and one
// or two stacked action buttons. Presentation is handled by `zashiSheet`.
// The top button is the lighter/cancel-style action; the bottom button is the
// primary affirmative action — this matches the visual hierarchy used in the
// Figma designs and the existing Unanswered Questions sheet.
struct VotingSheetContent: View {
    @Environment(\.colorScheme) var colorScheme

    enum ButtonStyle {
        case primary
        case secondary
    }

    struct ButtonConfig {
        let title: String
        let style: ButtonStyle
        let action: () -> Void
    }

    let iconSystemName: String
    let iconStyle: Colorable
    let title: String
    let message: String
    let primary: ButtonConfig
    let secondary: ButtonConfig?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(iconStyle.color(colorScheme).opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: iconSystemName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(iconStyle.color(colorScheme).opacity(0.8))
            }
            .padding(.top, 16)
            .padding(.bottom, 16)

            Text(title)
                .zFont(.semiBold, size: 22, style: Design.Text.primary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text(message)
                .zFont(size: 14, style: Design.Text.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                if let secondary {
                    button(secondary)
                }
                button(primary)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func button(_ config: ButtonConfig) -> some View {
        switch config.style {
        case .primary:
            ZashiButton(config.title, action: config.action)
        case .secondary:
            ZashiButton(config.title, type: .secondary, action: config.action)
        }
    }
}

extension View {
    /// Present a voting-flow bottom sheet (error or confirmation) with an
    /// icon, title, body, and one or two stacked buttons.
    func votingSheet(
        isPresented: Binding<Bool>,
        iconSystemName: String = "exclamationmark.circle",
        iconStyle: Colorable = Design.Utility.ErrorRed._500,
        title: String,
        message: String,
        primary: VotingSheetContent.ButtonConfig,
        secondary: VotingSheetContent.ButtonConfig? = nil
    ) -> some View {
        zashiSheet(isPresented: isPresented) {
            VotingSheetContent(
                iconSystemName: iconSystemName,
                iconStyle: iconStyle,
                title: title,
                message: message,
                primary: primary,
                secondary: secondary
            )
        }
    }
}
