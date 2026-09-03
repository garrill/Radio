import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Menu Row Button

struct MenuRowButton: View {
    let icon: String
    let label: String
    /// Pass true for the last button in the menu so its bottom corners match the panel's radius.
    var isLast: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isLast {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 5, bottomLeadingRadius: 13,
                            bottomTrailingRadius: 13, topTrailingRadius: 5
                        )
                        .fill(isHovered ? Color.accentColor : Color.clear)
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered ? Color.accentColor : Color.clear)
                    }
                }
            )
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings Menu Button

#if os(macOS)
struct SettingsMenuButton: View {
    @State private var isHovered = false

    var body: some View {
        SettingsLink {
            HStack(spacing: 8) {
                Image(systemName: "gear")
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text("Settings")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture().onEnded {
            NSApp.activate(ignoringOtherApps: true)
            // After SettingsLink shows/creates the window, bring it to front. Match the
            // SwiftUI Settings scene by its identifier — filtering NSApp.windows by
            // exclusion can otherwise land on the private NSStatusBarWindow (which refuses
            // to become key, logging a makeKeyWindow warning).
            DispatchQueue.main.async {
                NSApp.windows
                    .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                    .makeKeyAndOrderFront(nil)
            }
        })
    }
}
#endif
