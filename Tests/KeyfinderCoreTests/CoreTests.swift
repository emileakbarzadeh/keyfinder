import Foundation
@testable import KeyfinderCore

final class CoreTests {
    func testBundledLayoutAndNullTransparencyMatchGeneratedFirmware() throws {
        let layout = try LayoutSnapshot.bundled()
        expectEqual(layout.identity, try LayoutIdentity(serial: "exampleLayout/exampleRevision"))
        expectEqual(layout.layers.map(\.keys.count), [72, 72, 72])
        expectEqual(layout.layers.map { $0.keys.filter(\.isTransparent).count }, [0, 13, 52])
        expectEqual(layout.layers.map(\.displayName), ["Layer 0", "Layer 1", "Layer 2"])
    }
    func testAllCurrentActionsHaveKnownLabels() throws {
        let layers = LabelResolver.prepare(try .bundled())
        for layer in layers.values {
            expectEqual(layer.keys.count, 72)
            for key in layer.keys { expectNotEqual(key.appearance, .unknown, key.detail) }
        }
        expectEqual(layers[0]?.keys[55].label, ";")
        expectEqual(layers[0]?.keys[55].secondary, "Hold: Layer 2")
        expectEqual(layers[0]?.keys[29].label, "Desktop")
        expectEqual(layers[0]?.keys[29].secondary, "Hold: ⌃↑")
    }
    func testInheritanceDoesNotAssumeOnlyBaseIsActive() throws {
        let layers = LabelResolver.prepare(try .bundled())
        expectEqual(layers[1]?.keys[6].appearance, .inherited)
        expectEqual(layers[1]?.keys[6].label, "←")
        expectEqual(layers[2]?.keys[1].appearance, .ambiguous)
        expectEqual(layers[2]?.keys[1].label, "1 / F1")
        expectTrue(layers[2]?.keys[1].detail.contains("Layer 1: Tap: F1") == true)
    }
    func testDisabledUnknownAndTransparentStayDistinct() {
        let disabled = KeyDefinition(.object(["tap": .object(["code": .string("KC_NO")])]))
        let empty = KeyDefinition(.object(["tap": .null, "hold": .null]))
        let unknown = KeyDefinition(.object(["newAction": .string("future")]))
        expectEqual(LabelResolver.direct(disabled).appearance, .disabled)
        expectFalse(disabled.isTransparent)
        expectTrue(empty.isTransparent)
        expectFalse(unknown.isTransparent)
        expectEqual(LabelResolver.direct(unknown).appearance, .unknown)
        expectFalse(KeyDefinition(.null).isTransparent)
    }
    func testUnknownFieldsSurviveSnapshotRoundTrip() throws {
        let value: JSONValue = .object(["tap": .object(["code": .string("NEW_CODE"), "newField": .array([.bool(true), .number(1)])])])
        let key = KeyDefinition(value)
        expectEqual(try JSONDecoder().decode(KeyDefinition.self, from: JSONEncoder().encode(key)), key)
        expectTrue(LabelResolver.direct(key).detail.contains("newField"))
    }
    func testMacroAndGestureDetailsArePreserved() {
        let key = KeyDefinition(.object([
            "customLabel": .string("Build"),
            "tap": .object(["code": .string("MACRO"), "macro": .array([.string("KC_B")])]),
            "doubleTap": .object(["code": .string("KC_F5")]),
            "tapHold": .object(["code": .string("KC_F6")])
        ]))
        let result = LabelResolver.direct(key)
        expectEqual(result.label, "Build")
        expectTrue(result.secondary.contains("Double tap: F5"))
        expectTrue(result.detail.contains("KC_B"))
    }
    func testURLParsingAndCacheIdentitySafety() throws {
        let root = "https://configure.zsa.io/moonlander/layouts/exampleLayout"
        for suffix in ["", "/latest", "/latest/0", "/latest/0/"] {
            expectEqual(try OryxLocation(url: root + suffix).layoutID, "exampleLayout")
            expectNil(try OryxLocation(url: root + suffix).revisionID)
        }
        expectEqual(try OryxLocation(url: root + "/exampleRevision/2").revisionID, "exampleRevision")
        for url in ["http://configure.zsa.io/moonlander/layouts/x", "https://evil.test/moonlander/layouts/x", "https://configure.zsa.io/voyager/layouts/x", "https://user@configure.zsa.io/moonlander/layouts/x"] {
            expectThrows(try OryxLocation(url: url), url)
        }
        for serial in ["abc", "abc/", "a/../b", "../bad", "abc/latest", "a/b/c"] { expectThrows(try LayoutIdentity(serial: serial), serial) }
    }
    func testProtocolRejectsTruncatedInvalidAndKeystrokeReports() {
        var report = OryxProtocol.command(5); report[1] = 2; report[2] = 0xFE
        expectEqual(OryxProtocol.decode(report), .layer(2))
        expectNil(OryxProtocol.decode(Array(report.prefix(3))))
        report[1] = 32; expectNil(OryxProtocol.decode(report))
        report[1] = 1; report[2] = 0; expectNil(OryxProtocol.decode(report))
        for code: UInt8 in [6, 7, 8, 42] { expectNil(OryxProtocol.decode(OryxProtocol.command(code))) }
        var firmware = OryxProtocol.command(0)
        let serial = Array("exampleLayout/exampleRevision".utf8); firmware.replaceSubrange(1..<(serial.count + 1), with: serial); firmware[serial.count + 1] = 0xFE
        expectEqual(OryxProtocol.decode(firmware), .firmware("exampleLayout/exampleRevision"))
        var version = OryxProtocol.command(0xFE); version[1] = 5; version[2] = 0xFE
        expectEqual(OryxProtocol.decode(version), .protocolVersion(5))
    }
    func testDisconnectAndRevisionChangeRejectStaleFetches() throws {
        let snapshot = try LayoutSnapshot.bundled()
        var session = LiveSession()
        session.connect(identity: snapshot.identity)
        let oldLease = try require(session.lease)
        expectTrue(session.setLayer(1)); expectTrue(session.shouldShowOverlay)
        session.disconnect()
        expectFalse(session.shouldShowOverlay)
        expectFalse(session.accept(snapshot, for: oldLease))
        session.connect(identity: snapshot.identity)
        expectFalse(session.accept(snapshot, for: oldLease))
        let newLease = try require(session.lease)
        expectTrue(session.accept(snapshot, for: newLease))
        session.identify(try LayoutIdentity(serial: "exampleLayout/newRevision"))
        expectNil(session.snapshot)
        expectFalse(session.accept(snapshot, for: newLease))
    }
    func testVisibilityAndDuplicateLayers() throws {
        var session = LiveSession()
        expectFalse(session.setLayer(1))
        session.connect(identity: try LayoutIdentity(serial: "exampleLayout/exampleRevision"))
        expectFalse(session.shouldShowOverlay)
        expectTrue(session.setLayer(0)); expectFalse(session.shouldShowOverlay)
        expectFalse(session.setLayer(0))
        expectTrue(session.setLayer(2)); expectTrue(session.shouldShowOverlay)
        expectFalse(session.setLayer(2))
        expectFalse(session.setLayer(32)); expectFalse(session.setLayer(-1))
        session.setLayer(0); expectFalse(session.shouldShowOverlay)
    }
    func testGeometryCovers72UniquePositionsAndThumbsFit() throws {
        let keys = try MoonlanderGeometry.load()
        expectEqual(Set(keys.map { "\($0.row),\($0.column)" }).count, 72)
        expectEqual(keys[32].row, 5); expectEqual(keys[32].column, 3)
        expectEqual(keys[68].row, 11); expectEqual(keys[68].column, 3)
        expectEqual(keys[32].rotation, 30); expectEqual(keys[68].rotation, -30)
        for key in keys {
            for (x, y) in [(key.x, key.y), (key.x + key.width, key.y), (key.x, key.y + key.height), (key.x + key.width, key.y + key.height)] {
                let point = key.transformed(x: x, y: y)
                expectGreaterThanOrEqual(point.x, 0); expectLessThanOrEqual(point.x, MoonlanderGeometry.width)
                expectGreaterThanOrEqual(point.y, 0); expectLessThanOrEqual(point.y, MoonlanderGeometry.height)
            }
        }
    }
    func testRemoteRevisionMismatchAndMalformedGeometryAreRejected() throws {
        let snapshot = try LayoutSnapshot.bundled()
        let response: JSONValue = .object(["data": .object(["layout": .object(["title": .string(snapshot.title), "revision": snapshot.source])])])
        let data = try JSONEncoder().encode(response)
        expectThrows(try OryxClient.decodeResponse(data, layoutID: "exampleLayout", revisionID: "different"))
        expectEqual(try OryxClient.decodeResponse(data, layoutID: "exampleLayout", revisionID: "latest"), snapshot)
        let invalid = LayoutSnapshot(layoutID: "exampleLayout", title: "Bad", revisionID: "exampleRevision", source: .object(["hashId": .string("exampleRevision"), "layers": .array([])]))
        expectThrows(try invalid.validated())
    }
}

private actor CountingClient: LayoutFetching {
    var count = 0
    let snapshot: LayoutSnapshot
    init(_ snapshot: LayoutSnapshot) { self.snapshot = snapshot }
    func fetch(layoutID: String, revisionID: String) async throws -> LayoutSnapshot { count += 1; return snapshot }
}

final class RepositoryTests {
    func testBundledAndCachedLayoutAvoidNetworkAndRefreshDoesNotReplaceIdentity() async throws {
        let snapshot = try LayoutSnapshot.bundled()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = CountingClient(snapshot)
        let repository = LayoutRepository(directory: directory, client: client, bundled: snapshot)
        let first = try await repository.installed(snapshot.identity)
        expectEqual(first, snapshot)
        let countBefore = await client.count; expectEqual(countBefore, 0)
        let refreshed = try await repository.refresh(OryxLocation(url: snapshot.identity.url.absoluteString))
        expectEqual(refreshed, snapshot)
        let countAfter = await client.count; expectEqual(countAfter, 1)
        let next = LayoutRepository(directory: directory, client: client, bundled: nil)
        _ = try await next.installed(snapshot.identity)
        let finalCount = await client.count; expectEqual(finalCount, 1)
        let export = directory.appendingPathComponent("export.json")
        try LayoutRepository.export(snapshot, to: export)
        let imported = try await next.importSnapshot(from: export)
        expectEqual(imported, snapshot)
    }
}
