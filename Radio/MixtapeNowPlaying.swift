import Foundation

/// The show currently airing on an Infinite Mixtape — the hour-covering title NTS's
/// own web player shows (e.g. "Ton Lebbink - For You (Heavy House Aerobic Mix), 22 Jul
/// 2022"), not the per-track tracklist. NTS doesn't publish this via `api/v2/mixtapes`;
/// their own site reads it from a public Firestore collection, `mixtape_titles`
/// (project `nts-ios-app`), queried below.
struct MixtapeNowPlaying: Equatable {
    let title: String
    let showAlias: String?
    let episodeAlias: String?

    /// `/shows/<alias>[/episodes/<episode>]` — mirrors nts.live's own link target for
    /// this field, for a future "open episode" affordance.
    var articlePath: String? {
        guard let showAlias else { return nil }
        guard let episodeAlias else { return "/shows/\(showAlias)" }
        return "/shows/\(showAlias)/episodes/\(episodeAlias)"
    }
}

/// Minimal decoding for a Firestore `runQuery` REST response — an array of entries,
/// each optionally wrapping a document of typed `{stringValue|timestampValue: ...}` fields.
struct FirestoreRunQueryEntry: Decodable {
    let document: FirestoreDocument?
}

struct FirestoreDocument: Decodable {
    let fields: [String: FirestoreValue]
}

struct FirestoreValue: Decodable {
    let stringValue: String?
    let timestampValue: String?
}

extension MixtapeNowPlaying {
    /// Builds the `runQuery` request body for the latest `mixtape_titles` row for `alias`:
    /// the query NTS's own site runs, translated to Firestore's REST JSON shape.
    static func requestBody(mixtapeAlias: String) -> [String: Any] {
        [
            "structuredQuery": [
                "from": [["collectionId": "mixtape_titles"]],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": "mixtape_alias"],
                        "op": "EQUAL",
                        "value": ["stringValue": mixtapeAlias],
                    ],
                ],
                "orderBy": [["field": ["fieldPath": "started_at"], "direction": "DESCENDING"]],
                "limit": 1,
            ],
        ]
    }

    /// Decodes a `runQuery` response body into the current show, if any row matched.
    static func decode(_ data: Data) throws -> MixtapeNowPlaying? {
        let entries = try JSONDecoder().decode([FirestoreRunQueryEntry].self, from: data)
        guard let fields = entries.first(where: { $0.document != nil })?.document?.fields,
              let title = fields["title"]?.stringValue else { return nil }
        return MixtapeNowPlaying(
            title: title,
            showAlias: fields["show_alias"]?.stringValue,
            episodeAlias: fields["episode_alias"]?.stringValue
        )
    }
}
