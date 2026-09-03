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
        s = s.replacingOccurrences(of: "&#039;", with: "'")
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
    // Stored once at decode time — no repeated parsing on render
    let broadcastTitle: String
    let startDate: Date?
    let endDate: Date?
    let title: String
    let isRepeat: Bool
    let embeds: BroadcastEmbeds?

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // Pre-compiled once; avoids NSRegularExpression init cost on every title access
    private static let ntsRegex = try! NSRegularExpression(pattern: "\\bNts\\b")
    // `.capitalized` lowercases "DJ" to "Dj" — this restores it.
    private static let djRegex = try! NSRegularExpression(pattern: "\\bDj\\b")
    // `.capitalized` turns the "w/" shorthand into "W/" — this puts it back.
    private static let wSlashRegex = try! NSRegularExpression(pattern: "\\bW/")

    private enum CodingKeys: String, CodingKey {
        case broadcastTitle = "broadcast_title"
        case startTimestamp = "start_timestamp"
        case endTimestamp = "end_timestamp"
        case embeds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        broadcastTitle = try c.decode(String.self, forKey: .broadcastTitle)
        let startStr   = try c.decode(String.self, forKey: .startTimestamp)
        let endStr     = try c.decode(String.self, forKey: .endTimestamp)
        startDate      = Self.iso.date(from: startStr)
        endDate        = Self.iso.date(from: endStr)
        embeds         = try c.decodeIfPresent(BroadcastEmbeds.self, forKey: .embeds)
        isRepeat       = broadcastTitle.hasSuffix("(R)")

        let decoded = broadcastTitle.htmlEntityDecoded
        // Treat the title as all-uppercase if the only lowercase in it is the "w/"
        // shorthand NTS uses for "with" inside otherwise all-caps titles.
        let withoutWSlash = decoded.replacingOccurrences(of: "w/", with: "")
        if decoded.contains(where: { $0.isLetter }), !withoutWSlash.contains(where: { $0.isLowercase }) {
            let cap   = decoded.capitalized
            var range = NSRange(cap.startIndex..., in: cap)
            let nts   = Self.ntsRegex.stringByReplacingMatches(in: cap, range: range, withTemplate: "NTS")
            range     = NSRange(nts.startIndex..., in: nts)
            let dj    = Self.djRegex.stringByReplacingMatches(in: nts, range: range, withTemplate: "DJ")
            range     = NSRange(dj.startIndex..., in: dj)
            title     = Self.wSlashRegex.stringByReplacingMatches(in: dj, range: range, withTemplate: "w/")
        } else {
            title = decoded
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(broadcastTitle, forKey: .broadcastTitle)
        try c.encode(Self.iso.string(from: startDate ?? Date()), forKey: .startTimestamp)
        try c.encode(Self.iso.string(from: endDate ?? Date()), forKey: .endTimestamp)
        try c.encodeIfPresent(embeds, forKey: .embeds)
    }

    var location: String? { embeds?.details?.locationLong }

    var artworkURL: URL? {
        let urlString = embeds?.details?.media?.pictureMediumLarge
            ?? embeds?.details?.media?.pictureMedium
            ?? embeds?.details?.media?.pictureSmall
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    // Rebuilt whenever the effective locale changes so the "24-Hour Time" system
    // setting is honoured: the "j" skeleton resolves to 24-hour ("16:24") or
    // 12-hour ("4:24 PM") according to the user's preference.
    private static var cachedTimeFormatter: (locale: Locale, formatter: DateFormatter)?

    private static func timeFormatter() -> DateFormatter {
        // Locale.current is a fresh snapshot that reflects the live "24-Hour Time"
        // setting, so a change invalidates the cache and the format is recomputed.
        let locale = Locale.current
        if let cached = cachedTimeFormatter, cached.locale == locale {
            return cached.formatter
        }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate("jmm")
        cachedTimeFormatter = (locale, f)
        return f
    }

    func formattedTime(_ date: Date?) -> String {
        guard let date else { return "" }
        return Self.timeFormatter().string(from: date)
    }

    var progress: Double {
        guard let start = startDate, let end = endDate else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, min(1, elapsed / total))
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
