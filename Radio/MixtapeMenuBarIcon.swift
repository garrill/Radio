#if os(macOS)
import AppKit

/// Loads and caches a mixtape's menu-bar icon. NTS ships `media.icon_black` as a
/// 128×128 mono-on-transparent PNG; we template it and redraw it at 18×18 so it
/// matches the SF-Symbol treatment used for NTS 1 / NTS 2.
@MainActor
enum MixtapeMenuBarIcon {
    /// Shown immediately while the real icon downloads, or if it fails / is missing.
    static let fallbackSymbol = "music.note"

    private static var cache: [String: NSImage] = [:]

    static func cached(for mixtape: Mixtape) -> NSImage? { cache[mixtape.alias] }

    static func image(for mixtape: Mixtape) async -> NSImage? {
        if let hit = cache[mixtape.alias] { return hit }
        guard let url = mixtape.iconURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let raw = NSImage(data: data) else { return nil }

        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size, flipped: false) { rect in
            raw.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        icon.isTemplate = true
        cache[mixtape.alias] = icon
        return icon
    }
}
#endif
