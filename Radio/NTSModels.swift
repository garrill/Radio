import Foundation

private extension String {
    var htmlEntityDecoded: String {
        guard contains("&") else { return self }
        var s = self
        // Decode in order so &amp;amp; chains resolve correctly
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        s = s.replacingOccurrences(of: "&apos;", with: "'")
        return s
    }
}

struct NTSLiveResponse: Codable {
    let results: [ChannelData]
}

struct ChannelData: Codable {
    let channelName: String
    let now: Broadcast
    let next: Broadcast?

    enum CodingKeys: String, CodingKey {
        case channelName = "channel_name"
        case now
        case next
    }

    /// If the API hasn't updated yet and `now` has already ended, promote `next` to current.
    var effectiveNow: Broadcast {
        if let end = now.endDate, end < Date(), let next {
            return next
        }
        return now
    }

    /// Returns nil when we've promoted `next` to current (we don't know what follows it).
    var effectiveNext: Broadcast? {
        guard let end = now.endDate, end >= Date() else { return nil }
        return next
    }
}

struct Broadcast: Codable {
    let broadcastTitle: String
    let startTimestamp: String
    let endTimestamp: String
    let embeds: BroadcastEmbeds?

    enum CodingKeys: String, CodingKey {
        case broadcastTitle = "broadcast_title"
        case startTimestamp = "start_timestamp"
        case endTimestamp = "end_timestamp"
        case embeds
    }

    /// HTML-entity-decoded show title for display
    var title: String { broadcastTitle.htmlEntityDecoded }

    var artworkURL: URL? {
        let urlString = embeds?.details?.media?.pictureMediumLarge
            ?? embeds?.details?.media?.pictureMedium
            ?? embeds?.details?.media?.pictureSmall
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var startDate: Date? { Self.iso.date(from: startTimestamp) }
    var endDate: Date? { Self.iso.date(from: endTimestamp) }

    var timeRange: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current
        guard let start = startDate, let end = endDate else { return "" }
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    var progress: Double {
        guard let start = startDate, let end = endDate else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, min(1, elapsed / total))
    }

    func formattedTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current
        return fmt.string(from: date)
    }
}

struct BroadcastEmbeds: Codable {
    let details: ShowDetails?
}

struct ShowDetails: Codable {
    let name: String?
    let description: String?
    let media: ShowMedia?
}

struct ShowMedia: Codable {
    let pictureLarge: String?
    let pictureMediumLarge: String?
    let pictureMedium: String?
    let pictureSmall: String?
    let pictureThumb: String?

    enum CodingKeys: String, CodingKey {
        case pictureLarge = "picture_large"
        case pictureMediumLarge = "picture_medium_large"
        case pictureMedium = "picture_medium"
        case pictureSmall = "picture_small"
        case pictureThumb = "picture_thumb"
    }
}
