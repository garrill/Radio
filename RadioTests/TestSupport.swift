//
//  TestSupport.swift
//  RadioTests
//
//  Shared helpers: JSON fixtures for the NTS API shape, a URLProtocol stub,
//  and a polling wait for async state changes.
//

import Foundation
import Testing
@testable import Radio

// MARK: - Fixtures

/// Builds JSON in the exact shape `NTSModels` decodes (`api/v2/live`).
enum Fixture {

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// A single `now`/`next` broadcast object.
    static func broadcastDict(
        title: String = "Test Show",
        start: String = "2026-09-02T12:00:00Z",
        end: String = "2026-09-02T14:00:00Z",
        locationLong: String? = "London",
        pictureMediumLarge: String? = nil,
        pictureMedium: String? = nil,
        pictureSmall: String? = nil,
        includeEmbeds: Bool = true
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "broadcast_title": title,
            "start_timestamp": start,
            "end_timestamp": end,
        ]
        if includeEmbeds {
            var media: [String: Any] = [:]
            if let pictureMediumLarge { media["picture_medium_large"] = pictureMediumLarge }
            if let pictureMedium { media["picture_medium"] = pictureMedium }
            if let pictureSmall { media["picture_small"] = pictureSmall }
            var details: [String: Any] = [:]
            if let locationLong { details["location_long"] = locationLong }
            if !media.isEmpty { details["media"] = media }
            dict["embeds"] = ["details": details]
        }
        return dict
    }

    static func channelDict(
        name: String = "1",
        now: [String: Any],
        next: [String: Any]? = nil
    ) -> [String: Any] {
        var d: [String: Any] = ["channel_name": name, "now": now]
        if let next { d["next"] = next }
        return d
    }

    static func liveResponseDict(channels: [[String: Any]]) -> [String: Any] {
        ["results": channels]
    }

    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    static func decodeBroadcast(_ dict: [String: Any]) throws -> Broadcast {
        try JSONDecoder().decode(Broadcast.self, from: data(dict))
    }

    static func decodeChannel(_ dict: [String: Any]) throws -> ChannelData {
        try JSONDecoder().decode(ChannelData.self, from: data(dict))
    }
}

// MARK: - URLProtocol stub

/// Intercepts requests made through a `URLSession` configured with this protocol class.
/// Configure the response via the static `stub` before each test; use `.serialized`
/// on suites that touch it.
final class StubURLProtocol: URLProtocol {

    struct Stub {
        var statusCode = 200
        var data = Data()
        var error: Error?
    }

    nonisolated(unsafe) static var stub = Stub()

    static func reset() { stub = Stub() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client else { return }

        if let error = Self.stub.error {
            client.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://test.invalid")!,
            statusCode: Self.stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Self.stub.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLSession {
    /// A session whose traffic is served entirely by `StubURLProtocol`.
    static var stubbed: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Async wait

/// Polls `condition` until it is true or `timeout` elapses, then records a failure.
func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(condition(), "condition still false after \(timeout)")
}
