import WidgetKit
import AppKit
import OSLog

private let widgetLogCategory = "provider"

/// Everything needed to render one channel's pane in the widget.
struct ChannelDisplay {
    let location: String
    let title: String
    let image: NSImage
    let start: Date
    let end: Date
    let nextTitle: String
    let nextEnd: Date
}

extension ChannelDisplay {
    static func placeholder(title: String, date: Date) -> ChannelDisplay {
        ChannelDisplay(location: "", title: title, image: WidgetImages.placeholder, start: date, end: date, nextTitle: "", nextEnd: date)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let channel1: ChannelDisplay
    let channel2: ChannelDisplay
    let selectedChannel: WidgetChannelChoice
}

extension SimpleEntry {
    /// Same placeholder title/times on both channels, used for loading/error/unavailable states.
    static func placeholder(title: String, selectedChannel: WidgetChannelChoice, date: Date = Date()) -> SimpleEntry {
        SimpleEntry(date: date, channel1: .placeholder(title: title, date: date), channel2: .placeholder(title: title, date: date), selectedChannel: selectedChannel)
    }
}

enum WidgetImages {
    static let placeholder: NSImage = {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        return image
    }()
}

/// NTS's on-air schedule turns over on the hour. Refresh a few times right after each
/// turnover (to give the API time to publish the new broadcast), then stay quiet until
/// the next hour rather than polling every few minutes for data that isn't changing.
private let reloadCheckpointMinutes = [0, 2, 4, 6]

private func nextReloadDate(after date: Date = Date()) -> Date {
    let calendar = Calendar.current
    let currentMinute = calendar.component(.minute, from: date)
    let targetMinute = reloadCheckpointMinutes.first(where: { $0 > currentMinute }) ?? 0
    return calendar.nextDate(after: date, matching: DateComponents(minute: targetMinute, second: 0), matchingPolicy: .nextTime)
        ?? date.addingTimeInterval(120)
}

private extension Timeline where EntryType == SimpleEntry {
    /// Every timeline this widget produces is a single entry, reloaded at the next checkpoint.
    static func single(_ entry: SimpleEntry) -> Timeline<SimpleEntry> {
        Timeline(entries: [entry], policy: .after(nextReloadDate()))
    }

    /// Used when a fetch fails (network error, bad response, timeout). Retries soon rather than
    /// waiting for the next hourly checkpoint, so a transient hiccup doesn't strand the widget on
    /// a blank/error state for up to an hour.
    static func retrySoon(_ entry: SimpleEntry) -> Timeline<SimpleEntry> {
        Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(120)))
    }
}

/// Requests are given a short timeout so a stalled connection fails fast instead of eating the
/// widget extension's whole execution budget — a request that runs out the clock is killed by the
/// system and looks identical to a crash, leaving the widget stuck on its last (often blank) state.
private let requestTimeout: TimeInterval = 10

private func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = requestTimeout
    let (data, _) = try await URLSession.shared.data(for: request)
    return data
}

struct RadioWidgetProvider: AppIntentTimelineProvider {
    private static let apiURL = URL(string: "https://www.nts.live/api/v2/live")!

    func placeholder(in context: Context) -> SimpleEntry {
        SharedLog.log(Log.widget, "placeholder() requested, family=\(context.family)", category: widgetLogCategory)
        return .placeholder(title: "Loading...", selectedChannel: .channel1)
    }

    func snapshot(for configuration: RadioWidgetConfigurationIntent, in context: Context) async -> SimpleEntry {
        SharedLog.log(Log.widget, "snapshot() requested, family=\(context.family), isPreview=\(context.isPreview)", category: widgetLogCategory)
        return .placeholder(title: "Loading...", selectedChannel: configuration.channel)
    }

    func timeline(for configuration: RadioWidgetConfigurationIntent, in context: Context) async -> Timeline<SimpleEntry> {
        SharedLog.log(Log.widget, "timeline() requested, family=\(context.family), selectedChannel=\(configuration.channel)", category: widgetLogCategory)
        do {
            let data = try await fetch(Self.apiURL)
            SharedLog.log(Log.widget, "Fetched live API response, \(data.count) bytes", category: widgetLogCategory)
            let response = try JSONDecoder().decode(NTSLiveResponse.self, from: data)
            guard let channel1 = response.results.first(where: { $0.channelName == "1" }),
                  let channel2 = response.results.first(where: { $0.channelName == "2" }) else {
                SharedLog.error(Log.widget, "Response decoded but missing channel 1 or 2 (got \(response.results.map(\.channelName)))", category: widgetLogCategory)
                return .retrySoon(.placeholder(title: "Unavailable", selectedChannel: configuration.channel))
            }

            async let display1 = loadChannelDisplay(from: channel1)
            async let display2 = loadChannelDisplay(from: channel2)
            let entry = SimpleEntry(date: Date(), channel1: await display1, channel2: await display2, selectedChannel: configuration.channel)
            SharedLog.log(Log.widget, "Timeline entry built OK, next reload at \(nextReloadDate())", category: widgetLogCategory)
            return .single(entry)
        } catch {
            SharedLog.error(Log.widget, "timeline() failed: \(error)", category: widgetLogCategory)
            return .retrySoon(.placeholder(title: "Error", selectedChannel: configuration.channel))
        }
    }

    private func loadChannelDisplay(from channel: ChannelData) async -> ChannelDisplay {
        let now = channel.effectiveNow
        let next = channel.effectiveNext
        guard let start = now.startDate, let end = now.endDate else {
            SharedLog.error(Log.widget, "Channel \(channel.channelName) 'now' broadcast has no start/end date (title: \(now.title))", category: widgetLogCategory)
            return .placeholder(title: now.title, date: Date())
        }
        let image = await loadImage(from: now.artworkURL, channel: channel.channelName)
        return ChannelDisplay(
            location: now.location ?? "",
            title: now.title,
            image: image,
            start: start,
            end: end,
            nextTitle: next?.title ?? "",
            nextEnd: next?.endDate ?? end
        )
    }

    private func loadImage(from url: URL?, channel: String) async -> NSImage {
        guard let url else {
            SharedLog.log(Log.widget, "Channel \(channel) has no artwork URL, using placeholder", category: widgetLogCategory)
            return WidgetImages.placeholder
        }
        do {
            let data = try await fetch(url)
            guard let image = NSImage(data: data) else {
                SharedLog.error(Log.widget, "Channel \(channel) artwork data (\(data.count) bytes) from \(url.absoluteString) failed to decode as an image", category: widgetLogCategory)
                return WidgetImages.placeholder
            }
            return image
        } catch {
            SharedLog.error(Log.widget, "Channel \(channel) artwork fetch from \(url.absoluteString) failed: \(error)", category: widgetLogCategory)
            return WidgetImages.placeholder
        }
    }
}
