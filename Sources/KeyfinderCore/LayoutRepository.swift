import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol LayoutFetching: Sendable {
    func fetch(layoutID: String, revisionID: String) async throws -> LayoutSnapshot
}

public struct OryxClient: LayoutFetching, @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if os(macOS)
        config.waitsForConnectivity = false
        #endif
        self.session = URLSession(configuration: config)
    }
    public func fetch(layoutID: String, revisionID: String) async throws -> LayoutSnapshot {
        guard LayoutIdentity.validID(layoutID), LayoutIdentity.validID(revisionID) else { throw KeyfinderError.invalidIdentity }
        let query = "query Keyfinder($hashId: String!, $revisionId: String!, $geometry: String) { layout(hashId: $hashId, revisionId: $revisionId, geometry: $geometry) { title revision { hashId layers { title position keys } } } }"
        var request = URLRequest(url: URL(string: "https://oryx.zsa.io/graphql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Keyfinder/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["hashId": layoutID, "revisionId": revisionID, "geometry": "moonlander"]])
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw KeyfinderError.service("Oryx is unavailable. Try Refresh when your connection is restored.")
        }
        guard data.count <= 8 * 1024 * 1024 else { throw KeyfinderError.invalidLayout("the response is too large.") }
        return try Self.decodeResponse(data, layoutID: layoutID, revisionID: revisionID)
    }
    public static func decodeResponse(_ data: Data, layoutID: String, revisionID: String) throws -> LayoutSnapshot {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        if let errors = root["errors"]?.array, !errors.isEmpty {
            throw KeyfinderError.service("Oryx could not return this layout. Check the URL and its sharing settings, or import a saved snapshot.")
        }
        guard let layout = root["data"]?["layout"], let source = layout["revision"],
              let actualRevision = source["hashId"]?.string else {
            throw KeyfinderError.service("This layout is unavailable. Check its URL and sharing settings, or import a saved snapshot.")
        }
        let snapshot = LayoutSnapshot(layoutID: layoutID, title: layout["title"]?.string ?? "Moonlander", revisionID: actualRevision, source: source)
        let expected = revisionID == "latest" ? nil : try LayoutIdentity(layoutID: layoutID, revisionID: revisionID)
        return try snapshot.validated(expected: expected)
    }
}

/// All filesystem and network work happens on explicit load/import/refresh events.
/// There are no refresh tasks, retry loops, timers, or background URL sessions.
public actor LayoutRepository {
    private let directory: URL
    private let client: any LayoutFetching
    private let bundled: LayoutSnapshot?
    public init(directory: URL, client: any LayoutFetching = OryxClient(), bundled: LayoutSnapshot? = try? .bundled()) {
        self.directory = directory; self.client = client; self.bundled = bundled
    }
    public func cached(_ identity: LayoutIdentity) -> LayoutSnapshot? {
        let url = directory.appendingPathComponent(identity.cacheKey).appendingPathExtension("json")
        if let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024,
           let decoded = try? JSONDecoder().decode(LayoutSnapshot.self, from: data).validated(expected: identity) { return decoded }
        if let bundled, bundled.identity == identity { return bundled }
        return nil
    }
    public func installed(_ identity: LayoutIdentity) async throws -> LayoutSnapshot {
        if let cached = cached(identity) { return cached }
        let snapshot = try await client.fetch(layoutID: identity.layoutID, revisionID: identity.revisionID)
        try Task.checkCancellation()
        _ = try snapshot.validated(expected: identity)
        try save(snapshot)
        return snapshot
    }
    public func refresh(_ location: OryxLocation) async throws -> LayoutSnapshot {
        let snapshot = try await client.fetch(layoutID: location.layoutID, revisionID: location.revisionID ?? "latest")
        try Task.checkCancellation()
        try save(snapshot)
        return snapshot
    }
    public func save(_ snapshot: LayoutSnapshot) throws {
        _ = try snapshot.validated()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent(snapshot.identity.cacheKey).appendingPathExtension("json"), options: .atomic)
    }
    public func importSnapshot(from url: URL) throws -> LayoutSnapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 8 * 1024 * 1024 else { throw KeyfinderError.invalidLayout("the file is too large.") }
        let snapshot = try JSONDecoder().decode(LayoutSnapshot.self, from: Data(contentsOf: url)).validated()
        try save(snapshot)
        return snapshot
    }
    public static func export(_ snapshot: LayoutSnapshot, to url: URL) throws {
        _ = try snapshot.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
