import Foundation

/// One NTS "Infinite Mixtape" — an always-on, genre-curated stream with no schedule
/// and no track metadata. Decoded from `https://www.nts.live/api/v2/mixtapes`.
struct MixtapesResponse: Codable {
    let results: [Mixtape]
}

struct Mixtape: Codable, Identifiable, Hashable {
    /// `mixtape_alias` — the only stable identifier the API exposes (e.g. `poolside`).
    /// Values are `[a-z0-9-]`, so they are safe to store comma-joined.
    let alias: String
    let title: String
    let subtitle: String
    let mixtapeDescription: String
    let streamURL: URL
    /// Square artwork — `media.picture_medium_large`, falling back to `picture_medium`.
    let artworkURL: URL?
    /// 128×128 mono-on-transparent PNG (`media.icon_black`) used as the menu-bar template.
    let iconURL: URL?
    /// White-on-transparent variant (`media.icon_white`), shown over the panel artwork.
    let iconWhiteURL: URL?

    var id: String { alias }

    private enum CodingKeys: String, CodingKey {
        case alias = "mixtape_alias"
        case title
        case subtitle
        case description
        case audioStreamEndpoint = "audio_stream_endpoint"
        case media
    }

    private enum MediaKeys: String, CodingKey {
        case pictureMediumLarge = "picture_medium_large"
        case pictureMedium = "picture_medium"
        case iconBlack = "icon_black"
        case iconWhite = "icon_white"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alias = try c.decode(String.self, forKey: .alias)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        mixtapeDescription = try c.decodeIfPresent(String.self, forKey: .description) ?? ""

        let stream = try c.decode(String.self, forKey: .audioStreamEndpoint)
        guard let streamURL = URL(string: stream) else {
            throw DecodingError.dataCorruptedError(
                forKey: .audioStreamEndpoint, in: c,
                debugDescription: "audio_stream_endpoint is not a valid URL: \(stream)"
            )
        }
        self.streamURL = streamURL

        let media = try? c.nestedContainer(keyedBy: MediaKeys.self, forKey: .media)
        func mediaString(_ key: MediaKeys) -> String? {
            guard let media else { return nil }
            return (try? media.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        let artwork = mediaString(.pictureMediumLarge) ?? mediaString(.pictureMedium)
        artworkURL = artwork.flatMap { URL(string: $0) }
        iconURL = mediaString(.iconBlack).flatMap { URL(string: $0) }
        iconWhiteURL = mediaString(.iconWhite).flatMap { URL(string: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(alias, forKey: .alias)
        try c.encode(title, forKey: .title)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encode(mixtapeDescription, forKey: .description)
        try c.encode(streamURL.absoluteString, forKey: .audioStreamEndpoint)
        var media = c.nestedContainer(keyedBy: MediaKeys.self, forKey: .media)
        try media.encodeIfPresent(artworkURL?.absoluteString, forKey: .pictureMediumLarge)
        try media.encodeIfPresent(iconURL?.absoluteString, forKey: .iconBlack)
        try media.encodeIfPresent(iconWhiteURL?.absoluteString, forKey: .iconWhite)
    }
}

/// The set of mixtapes the user has enabled, persisted as a comma-joined list of
/// aliases in the `enabledMixtapes` `@AppStorage` string. Order in that string is
/// not meaningful — the panel renders enabled mixtapes in NTS list order.
enum MixtapeSelection {
    static func aliases(from raw: String) -> [String] {
        raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    static func raw(from aliases: [String]) -> String {
        aliases.joined(separator: ",")
    }

    static func isEnabled(_ alias: String, in raw: String) -> Bool {
        aliases(from: raw).contains(alias)
    }

    /// Returns `raw` with `alias` added if absent, or removed if present.
    static func toggling(_ alias: String, in raw: String) -> String {
        var list = aliases(from: raw)
        if let idx = list.firstIndex(of: alias) {
            list.remove(at: idx)
        } else {
            list.append(alias)
        }
        return self.raw(from: list)
    }
}
