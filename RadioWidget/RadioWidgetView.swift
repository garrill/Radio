import SwiftUI
import WidgetKit
import CoreText

/// Univers.ttf is a variable font whose only registered PostScript name is
/// "UniversNextVariable"; weight/width instances like "Bold Condensed" are only
/// reachable via the `wght`/`wdth` variation axes, not as separate font names.
enum WidgetFont {
    static let registerOnce: Void = {
        guard let url = Bundle.main.url(forResource: "Univers", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func universNext(weight: CGFloat, width: CGFloat, size: CGFloat) -> Font {
        _ = registerOnce
        let variationAxes: [Int: CGFloat] = [
            0x77676874: weight, // 'wght'
            0x77647468: width   // 'wdth'
        ]
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: "UniversNextVariable",
            kCTFontVariationAttribute as NSFontDescriptor.AttributeName: variationAxes
        ])
        guard let font = NSFont(descriptor: descriptor, size: size) else {
            return .system(size: size, weight: .semibold)
        }
        return Font(font)
    }

    static func boldCondensed(size: CGFloat) -> Font {
        universNext(weight: 600, width: 75, size: size)
    }

    /// Used for secondary text (location, time ranges) — visually lighter than titles.
    static func lightCondensed(size: CGFloat) -> Font {
        universNext(weight: 300, width: 75, size: size)
    }
}

/// A single channel filling its full allotted rect: artwork on top, now-playing info
/// bottom-left, and (when there's room) the next show below that. Used for the small
/// widget (one channel, full size) and the medium widget (two channels side by side).
private struct ChannelPaneView: View {
    let channel: ChannelDisplay
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(nsImage: channel.image)
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .scaledToFill()
                    .frame(width: width, height: channel.nextTitle.isEmpty ? height : height * 0.72)
                    .clipped()
                    .widgetAccentable()
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0.9), Color.black.opacity(0.9), Color.black.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                    )

                VStack(alignment: .leading) {
                    Spacer()
                    if !channel.location.isEmpty {
                        Text(channel.location.uppercased())
                            .font(WidgetFont.lightCondensed(size: 9))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Text(channel.title.uppercased())
                        .font(WidgetFont.boldCondensed(size: 16))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text("\(channel.start, style: .time) – \(channel.end, style: .time)")
                        .font(WidgetFont.lightCondensed(size: 12))
                        .foregroundColor(.white)
                }
                .padding([.leading, .bottom, .trailing], 10)
                .frame(width: width, alignment: .leading)
            }
            .scaledToFill()

            if !channel.nextTitle.isEmpty {
                VStack(alignment: .leading) {
                    Text(channel.nextTitle.uppercased())
                        .font(WidgetFont.boldCondensed(size: 12))
                        .lineLimit(1)
                        .foregroundColor(.white)
                    Text("\(channel.end, style: .time) – \(channel.nextEnd, style: .time)")
                        .font(WidgetFont.lightCondensed(size: 10))
                        .foregroundColor(.white)
                }
                .padding(10)
                .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

/// A full-width horizontal band for one channel: artwork behind, now-playing info on
/// the left and the next show on the right of the same row. Used for the large widget,
/// stacked two-high, so each channel gets its own band rather than a narrow column.
private struct ChannelBandView: View {
    let channel: ChannelDisplay
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Image(nsImage: channel.image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .widgetAccentable()
                .mask(
                    LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.85), Color.black]), startPoint: .leading, endPoint: .trailing)
                )

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if !channel.location.isEmpty {
                        Text(channel.location.uppercased())
                            .font(WidgetFont.lightCondensed(size: 9))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Text(channel.title.uppercased())
                        .font(WidgetFont.boldCondensed(size: 16))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text("\(channel.start, style: .time) – \(channel.end, style: .time)")
                        .font(WidgetFont.lightCondensed(size: 12))
                        .foregroundColor(.white)
                }

                Spacer(minLength: 12)

                if !channel.nextTitle.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Up Next")
                            .font(WidgetFont.lightCondensed(size: 9))
                            .foregroundColor(.white.opacity(0.7))
                        Text(channel.nextTitle.uppercased())
                            .font(WidgetFont.boldCondensed(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                        Text("\(channel.end, style: .time) – \(channel.nextEnd, style: .time)")
                            .font(WidgetFont.lightCondensed(size: 10))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(12)
            .frame(width: width, height: height, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

struct RadioWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SimpleEntry

    var body: some View {
        GeometryReader { geometry in
            Link(destination: URL(string: "radio://show")!) {
                content(in: geometry.size)
            }
            .buttonStyle(.plain)
        }
        .containerBackground(Color.black, for: .widget)
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch family {
        case .systemSmall:
            let channel = entry.selectedChannel == .channel2 ? entry.channel2 : entry.channel1
            ChannelPaneView(channel: channel, width: size.width, height: size.height)
        case .systemLarge:
            VStack(spacing: 0) {
                ChannelBandView(channel: entry.channel1, width: size.width, height: size.height / 2)
                ChannelBandView(channel: entry.channel2, width: size.width, height: size.height / 2)
            }
        default:
            HStack(spacing: 0) {
                ChannelPaneView(channel: entry.channel1, width: size.width / 2, height: size.height)
                ChannelPaneView(channel: entry.channel2, width: size.width / 2, height: size.height)
            }
        }
    }
}
