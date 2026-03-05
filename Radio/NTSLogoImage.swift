#if os(macOS)
import AppKit

extension NSImage {
    /// NTS logo rendered from inline SVG data, sized for the menu bar.
    static let ntsMenuBarIcon: NSImage = {
        let svg = """
        <svg viewBox="0 0 32 32" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
            <circle cx="28" cy="23" r="2"></circle>
            <circle cx="4" cy="9" r="2"></circle>
            <circle cx="16" cy="30" r="2"></circle>
            <circle cx="16" cy="2" r="2"></circle>
            <circle cx="4" cy="23" r="2"></circle>
            <circle cx="28" cy="9" r="2"></circle>
            <circle cx="23" cy="28" r="2"></circle>
            <circle cx="9" cy="4" r="2"></circle>
            <circle cx="9" cy="28" r="2"></circle>
            <circle cx="23" cy="4" r="2"></circle>
            <circle cx="2" cy="16" r="2"></circle>
            <circle cx="30" cy="16" r="2"></circle>
            <circle cx="16" cy="16" r="2"></circle>
            <circle cx="22" cy="19.5" r="2"></circle>
            <circle cx="10" cy="12.5" r="2"></circle>
            <circle cx="16" cy="23" r="2"></circle>
            <circle cx="16" cy="9" r="2"></circle>
            <circle cx="10" cy="19.5" r="2"></circle>
            <circle cx="22" cy="12.5" r="2"></circle>
        </svg>
        """

        // Try to create NSImage from SVG data (macOS 12+ supports SVG natively)
        if let data = svg.data(using: .utf8),
           let svgImage = NSImage(data: data) {
            // Draw into a crisp 18×18pt template image
            let size = NSSize(width: 16, height: 16)
            let result = NSImage(size: size, flipped: false) { rect in
                svgImage.draw(in: rect)
                return true
            }
            result.isTemplate = true
            return result
        }

        // Fallback — should never be reached on macOS 26
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "NTS Radio") ?? NSImage()
    }()
}
#endif
