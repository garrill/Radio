import SwiftUI

/// The row(s) of square mixtape artworks shown in the panel below Stream 2 when
/// "Show infinite mixtapes" is on. Receives the already-filtered list in NTS order.
struct MixtapeGridView: View {
    let mixtapes: [Mixtape]

    private var columns: Int { MixtapeGrid.columns(for: mixtapes.count) }
    private var tileEdge: CGFloat { MixtapeGrid.tileEdge(columns: columns) }

    private var rows: [[Mixtape]] {
        stride(from: 0, to: mixtapes.count, by: columns).map { start in
            Array(mixtapes[start ..< min(start + columns, mixtapes.count)])
        }
    }

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
        .help(mixtape.title)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isPlaying)
        .animation(.easeInOut(duration: 0.12), value: isBuffering)
    }
}
