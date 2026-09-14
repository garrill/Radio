import SwiftUI

/// Bounds of whichever mixtape tile is both hovered and currently playing — reported
/// by `MixtapeTile` via `anchorPreference` so the tooltip bubble can be rendered by
/// `MixtapeGridView` itself, outside any individual tile's small clipped bounds.
private struct HoveredPlayingTileKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The tooltip capsule's actual rendered width, reported by `TooltipBubble` so its
/// arrow can be clamped against the capsule it's really attached to (which is often
/// narrower than `TooltipBubble.maxWidth`) rather than a worst-case assumption.
private struct CapsuleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = TooltipBubble.maxWidth
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The row(s) of square mixtape artworks shown in the panel below Stream 2 when
/// "Show infinite mixtapes" is on. Receives the already-filtered list in NTS order.
struct MixtapeGridView: View {
    let mixtapes: [Mixtape]

    @EnvironmentObject var player: RadioPlayer

    private var columns: Int { MixtapeGrid.columns(for: mixtapes.count) }
    private var tileEdge: CGFloat { MixtapeGrid.tileEdge(columns: columns) }

    private var rows: [[Mixtape]] {
        stride(from: 0, to: mixtapes.count, by: columns).map { start in
            Array(mixtapes[start ..< min(start + columns, mixtapes.count)])
        }
    }

    /// The currently-shown tooltip's actual capsule width, kept in sync via
    /// `CapsuleWidthKey` — starts at the worst-case `TooltipBubble.maxWidth` so the
    /// very first frame still clamps safely before a real measurement lands.
    @State private var capsuleWidth: CGFloat = TooltipBubble.maxWidth

    var body: some View {
        VStack(spacing: MixtapeGrid.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: MixtapeGrid.interitemSpacing) {
                    ForEach(row) { mixtape in
                        MixtapeTile(mixtape: mixtape, edge: tileEdge)
                    }
                    // Keep a short final row left-aligned.
                    if row.count < columns {
                        ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                            Color.clear.frame(width: tileEdge, height: tileEdge)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MixtapeGrid.horizontalPadding)
        .padding(.top, MixtapeGrid.sectionTopPadding)
        .padding(.bottom, MixtapeGrid.sectionBottomPadding)
        // Rendered here, not inside `MixtapeTile`, so the bubble isn't constrained by
        // any one tile's small `.clipShape`'d frame — it floats freely above the grid.
        .overlayPreferenceValue(HoveredPlayingTileKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let title = player.currentMixtapeNowPlaying?.title {
                    let rect = proxy[anchor]
                    // Clamp using `TooltipBubble.maxWidth` (the capsule's own upper bound),
                    // not the measured `capsuleWidth` — that keeps the capsule fully inside
                    // the panel even before a real measurement has landed.
                    let halfMaxWidth = TooltipBubble.maxWidth / 2
                    let capsuleX = min(max(rect.midX, halfMaxWidth), proxy.size.width - halfMaxWidth)
                    // The arrow, though, is clamped against the capsule's actual width — if
                    // that stayed clamped to the worst case, a short capsule's arrow could
                    // slide out past its own (narrower) rounded end.
                    let maxArrowOffset = max(0, capsuleWidth / 2 - TooltipBubble.arrowWidth / 2 - 6)
                    let arrowOffsetX = min(max(rect.midX - capsuleX, -maxArrowOffset), maxArrowOffset)
                    TooltipBubble(text: title, arrowOffsetX: arrowOffsetX)
                        .position(
                            x: capsuleX,
                            y: max(rect.minY - TooltipBubble.totalHeight / 2 - 4, TooltipBubble.totalHeight / 2)
                        )
                        .onPreferenceChange(CapsuleWidthKey.self) { capsuleWidth = $0 }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct MixtapeTile: View {
    @EnvironmentObject var player: RadioPlayer
    let mixtape: Mixtape
    let edge: CGFloat

    @State private var isHovered = false

    private var isPlaying: Bool { player.playing == .mixtape(mixtape) }
    private var isBuffering: Bool { isPlaying && player.isBuffering }

    /// Which of the three crossfading centre glyphs should be visible. All three are kept
    /// mounted (see `body`) so a state change fades one out while the next fades in, rather
    /// than the old glyph vanishing before the new one appears.
    private enum CenterGlyph { case icon, waveform, playButton }
    private var centerGlyph: CenterGlyph {
        if isPlaying && player.isPanelVisible && !isHovered { return .waveform }
        if isHovered { return .playButton }
        return .icon
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.secondary.opacity(0.12))

            if let url = mixtape.artworkURL {
                ArtworkImage(url: url, dimension: edge)
            }

            // A soft dark veil so the white icon reads on any artwork.
            LinearGradient(
                colors: [.black.opacity(0.1), .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
            if isBuffering || isPlaying || isHovered {
                Rectangle().fill(.black.opacity(0.35))
            }

            if isBuffering {
                // 2 stacked spinners to make them translucent, effectively having an opacity value of 2.
                // This is the only way i have found to make the spinners less translucent
                // only change this if you are 100% sure your method works
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                }
            } else {
                // The three centre glyphs are all mounted at once and shown/hidden via
                // opacity so switching between them crossfades (driven by the `.animation`
                // modifiers below) instead of one popping out before the next fades in.
                ZStack {
                    if let iconURL = mixtape.iconWhiteURL {
                        ArtworkImage(url: iconURL, dimension: edge * 0.55)
                            .frame(width: edge * 0.55, height: edge * 0.55)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .opacity(centerGlyph == .icon ? 1 : 0)
                    }

                    if isPlaying && player.isPanelVisible {
                        WaveformView()
                            .frame(width: 22, height: 18)
                            .foregroundStyle(.white)
                            .opacity(centerGlyph == .waveform ? 1 : 0)
                    }

                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(centerGlyph == .playButton ? 1 : 0)
                }
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { player.toggle(mixtape: mixtape) }
        .anchorPreference(key: HoveredPlayingTileKey.self, value: .bounds) { anchor in
            (isHovered && isPlaying) ? anchor : nil
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isPlaying)
        .animation(.easeInOut(duration: 0.12), value: isBuffering)
    }
}

/// A native-style Dock label floated above a playing mixtape's tile while hovered,
/// showing the show currently airing on it — a frosted, capsule-shaped pill with a
/// downward-pointing arrow, matching how macOS labels Dock icons on hover: translucent
/// system material (adapts light/dark automatically), width hugging short text and
/// truncating long text rather than wrapping (so the capsule never distorts).
private struct TooltipBubble: View {
    let text: String
    /// Horizontal distance from the capsule's own centre to where the arrow should sit —
    /// lets the arrow track the tile underneath even when the capsule itself has been
    /// shifted to stay inside the panel. See the call site in `MixtapeGridView`.
    var arrowOffsetX: CGFloat = 0

    /// Single line at a fixed font/padding, so the bubble's height never varies with
    /// content — only its width does. Kept in sync with the metrics below by eye;
    /// verified by rendering the view offscreen (see git history for the check).
    static let capsuleHeight: CGFloat = 26
    static let arrowHeight: CGFloat = 6
    static let totalHeight: CGFloat = capsuleHeight + arrowHeight
    static let maxWidth: CGFloat = 200
    static let arrowWidth: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .frame(height: Self.capsuleHeight)
                .frame(maxWidth: Self.maxWidth)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                )
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: CapsuleWidthKey.self, value: g.size.width)
                    }
                )

            TooltipArrow()
                .fill(.thinMaterial)
                .frame(width: Self.arrowWidth, height: Self.arrowHeight)
                .offset(x: arrowOffsetX, y: -0.5) // y hides the seam between arrow and capsule
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .fixedSize()
        .transition(.opacity)
    }
}

/// A small downward-pointing triangle, flush with the bottom of `TooltipBubble`'s
/// capsule — mirrors the Dock label's pointer down to the icon it's labelling.
private struct TooltipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
