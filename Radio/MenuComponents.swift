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

// MARK: - Volume Menu Row

/// Top row of the bottom menu when "Show volume control" is enabled. Matches
/// `MenuRowButton`'s metrics. At rest it shows a speaker glyph + a label that
/// carries the level when it isn't 100% ("Volume (55%)", "Volume (muted)"); on
/// hover the label cross-fades to an inline `Slider`. The glyph and label stay
/// put (fixed row height, stable view tree) so nothing jumps on rollover — the
/// glyph only animates when it actually changes, never on hover. Tapping the
/// glyph toggles mute, like Music.app.
struct VolumeMenuRow: View {
    @EnvironmentObject var player: RadioPlayer
    @State private var isHovered = false

    /// "Volume" at full, "Volume (muted)" at zero, "Volume (N%)" (nearest 5%) between.
    private var label: String {
        let pct = Int((player.volume * 20).rounded()) * 5
        if pct >= 100 { return "Volume" }
        if pct <= 0 { return "Volume (muted)" }
        return "Volume (\(pct)%)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: player.volumeSymbol)
                .font(.system(size: 11))
                .frame(width: 14)
                .id(player.volumeSymbol)
                .transition(.opacity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { player.toggleMute() }
                }
                .animation(.easeInOut(duration: 0.15), value: player.volumeSymbol)

            ZStack(alignment: .leading) {
                Text(label)
                    .font(.system(size: 12))
                    .opacity(isHovered ? 0 : 1)
                Slider(value: $player.volume, in: 0...1)
                    .controlSize(.mini)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
            }
        }
        .frame(height: 16)
        .foregroundStyle(isHovered ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 5)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
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
