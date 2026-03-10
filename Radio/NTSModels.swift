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
        s = s.replacingOccurrences(of: "&#039;", with: "’")
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

    /// Decoded title, converted from ALL CAPS to Title Case when needed.
    var title: String {
        let decoded = broadcastTitle.htmlEntityDecoded
        // contains(where:) short-circuits — avoids allocating a filtered array
        guard decoded.contains(where: { $0.isLetter }),
              !decoded.contains(where: { $0.isLowercase }) else { return decoded }
        var result = decoded.capitalized
        result = result.replacingOccurrences(of: "\\bNts\\b", with: "NTS", options: .regularExpression)
        return result
    }

    var location: String? { embeds?.details?.locationLong }

    var isRepeat: Bool { broadcastTitle.hasSuffix("(R)") }

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

    var progress: Double {
        guard let start = startDate, let end = endDate else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, min(1, elapsed / total))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()

    func formattedTime(_ date: Date?) -> String {
        guard let date else { return "" }
        return Self.timeFormatter.string(from: date)
    }
}

struct BroadcastEmbeds: Codable {
    let details: ShowDetails?
}

struct ShowDetails: Codable {
    let locationLong: String?
    let media: ShowMedia?

    enum CodingKeys: String, CodingKey {
        case locationLong = "location_long"
        case media
    }
}

struct ShowMedia: Codable {
    let pictureMediumLarge: String?
    let pictureMedium: String?
    let pictureSmall: String?

    enum CodingKeys: String, CodingKey {
        case pictureMediumLarge = "picture_medium_large"
        case pictureMedium = "picture_medium"
        case pictureSmall = "picture_small"
    }
}
