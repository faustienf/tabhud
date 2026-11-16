import SwiftUI

/// Only appears before the user makes a selection: the preview is the quick-switch target.
struct QuickSwitchBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text("Switch to previous app")
        } icon: {
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(WheelPalette(isDark: colorScheme == .dark).accent)
        }
            .modifier(WheelBadgeStyle())
            .accessibilityLabel("Release Command to switch to the previous application")
    }
}
