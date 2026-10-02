import Foundation
import KeyfinderCore

final class CoreTests {
    func testDemoLayoutHasCompleteGeometryAndTransparentKeys() throws {
        let layout = try LayoutSnapshot.bundled()
        expectEqual(layout.identity, try LayoutIdentity(serial: "keyfinder-demo/v1"))
        expectEqual(layout.layers.map(\.keys.count), [72, 72, 72])
        expectTrue(layout.isDemo)
        expectEqual(layout.layers.map { $0.keys.filter(\.isTransparent).count }, [0, 29, 50])
        expectEqual(layout.layers.map(\.displayName), ["Typing · 0", "Symbols · 1", "Navigation · 2"])
    }
    func testAllCurrentActionsHaveKnownLabels() throws {
        let layers = LabelResolver.prepare(try .bundled())
        for layer in layers.values {
            expectEqual(layer.keys.count, 72)
            for key in layer.keys { expectNotEqual(key.appearance, .unknown, key.detail) }
        }
        expectEqual(layers[0]?.keys[55].label, ";")
        expectEqual(layers[0]?.keys[55].secondary, "Hold: Layer 2")
        expectEqual(layers[0]?.keys[29].label, "Copy")
        expectEqual(layers[0]?.keys[29].secondary, "Hold: ⌘V")
    }
    func testInheritanceDoesNotAssumeOnlyBaseIsActive() throws {
        let layers = LabelResolver.prepare(try .bundled())
        expectEqual(layers[1]?.keys[6].appearance, .inherited)
        expectEqual(layers[1]?.keys[6].label, "[")
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
        let root = "https://configure.zsa.io/moonlander/layouts/keyfinder-demo"
        for suffix in ["", "/latest", "/latest/0", "/latest/0/"] {
            expectEqual(try OryxLocation(url: root + suffix).layoutID, "keyfinder-demo")
            expectNil(try OryxLocation(url: root + suffix).revisionID)
        }
        expectEqual(try OryxLocation(url: root + "/v1/2").revisionID, "v1")
        for url in ["http://configure.zsa.io/moonlander/layouts/x", "https://evil.test/moonlander/layouts/x", "https://configure.zsa.io/unknown/layouts/x", "https://user@configure.zsa.io/moonlander/layouts/x"] {
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
        let serial = Array("keyfinder-demo/v1".utf8); firmware.replaceSubrange(1..<(serial.count + 1), with: serial); firmware[serial.count + 1] = 0xFE
        expectEqual(OryxProtocol.decode(firmware), .firmware("keyfinder-demo/v1"))
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
        session.identify(try LayoutIdentity(serial: "keyfinder-demo/newRevision"))
        expectNil(session.snapshot)
        expectFalse(session.accept(snapshot, for: newLease))
    }
    func testVisibilityAndDuplicateLayers() throws {
        var session = LiveSession()
        expectFalse(session.setLayer(1))
        session.connect(identity: try LayoutIdentity(serial: "keyfinder-demo/v1"))
        expectFalse(session.shouldShowOverlay)
        expectTrue(session.setLayer(0)); expectFalse(session.shouldShowOverlay)
        expectFalse(session.setLayer(0))
        expectTrue(session.setLayer(2)); expectTrue(session.shouldShowOverlay)
        expectFalse(session.setLayer(2))
        expectFalse(session.setLayer(32)); expectFalse(session.setLayer(-1))
        session.setLayer(0); expectFalse(session.shouldShowOverlay)
    }
    func testGeometryCovers72UniquePositionsAndThumbsFit() throws {
        let geometry = try KeyboardGeometry.load()
        let keys = geometry.keys
        expectEqual(Set(keys.map { "\($0.row ?? -1),\($0.column ?? -1)" }).count, 72)
        expectEqual(keys[32].row, 5); expectEqual(keys[32].column, 3)
        expectEqual(keys[68].row, 11); expectEqual(keys[68].column, 3)
        expectEqual(keys[32].rotation, 30); expectEqual(keys[68].rotation, -30)
        for key in keys {
            for (x, y) in [(key.x, key.y), (key.x + key.width, key.y), (key.x, key.y + key.height), (key.x + key.width, key.y + key.height)] {
                let point = key.transformed(x: x, y: y)
                expectGreaterThanOrEqual(point.x, 0); expectLessThanOrEqual(point.x, geometry.width)
                expectGreaterThanOrEqual(point.y, 0); expectLessThanOrEqual(point.y, geometry.height)
            }
        }
    }
    func testKeyboardModelsKeepNamesURLsAndIdentitiesDistinct() throws {
        let expected: [(KeyboardModel, String, Int, Int)] = [
            (.moonlander, "Moonlander", 72, 0x1969), (.voyager, "Voyager", 52, 0x1977), (.ergodoxEZ, "ErgoDox EZ", 76, 0x4974)
        ]
        var identities: Set<LayoutIdentity> = []
        for (keyboard, name, count, product) in expected {
            expectEqual(keyboard.displayName, name)
            expectEqual(keyboard.keyCount, count)
            expectEqual(KeyboardModel.detect(productID: product), keyboard)
            expectEqual(KeyboardModel.detect(productID: 0, productName: name), keyboard)
            let identity = try LayoutIdentity(layoutID: "shared-layout", revisionID: "shared-revision", keyboard: keyboard)
            identities.insert(identity)
            let location = try OryxLocation(url: identity.url.absoluteString)
            expectEqual(location.keyboard, keyboard)
            expectEqual(location.revisionID, identity.revisionID)
            expectTrue(identity.cacheKey.hasPrefix(keyboard.rawValue + "-"))
            let snapshot = try keyboardFixture(keyboard)
            expectEqual(snapshot.keyboardName, name)
            expectEqual(LabelResolver.prepare(snapshot)[0]?.keyboard, keyboard)
            let roundTrip = try JSONDecoder().decode(LayoutSnapshot.self, from: JSONEncoder().encode(snapshot)).validated()
            expectEqual(roundTrip, snapshot)
            let response = try JSONEncoder().encode(JSONValue.object(["data": .object(["layout": .object(["revision": snapshot.source])])]))
            expectEqual(try OryxClient.decodeResponse(response, keyboard: keyboard, layoutID: snapshot.layoutID, revisionID: snapshot.revisionID).keyboard, keyboard)
        }
        expectEqual(identities.count, 3)
        expectNil(KeyboardModel.detect(productID: 0x4975)) // Planck EZ is not a supported geometry.
        expectNil(KeyboardModel.detect(productID: 0, productName: "Unknown keyboard"))
        let legacy = Data(#"{"layoutID":"old-layout","revisionID":"old-revision"}"#.utf8)
        let identity = try JSONDecoder().decode(LayoutIdentity.self, from: legacy)
        expectEqual(identity.keyboard, .moonlander)
        expectEqual(identity.cacheKey, "moonlander-old-layout-old-revision-v1")
        let voyager = try keyboardFixture(.voyager)
        let ergodox = try keyboardFixture(.ergodoxEZ)
        var session = LiveSession(); session.connect(identity: voyager.identity)
        expectFalse(session.accept(ergodox, for: try require(session.lease)))
        expectThrows(try voyager.validated(expected: ergodox.identity))
        var invalid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(voyager)) as! [String: Any]
        invalid["geometry"] = "unsupported-keyboard"
        expectThrows(try JSONDecoder().decode(LayoutSnapshot.self, from: JSONSerialization.data(withJSONObject: invalid)))
    }

    func testEveryKeyboardGeometryFitsItsCanvas() throws {
        for model in KeyboardModel.allCases {
            let geometry = try KeyboardGeometry.load(for: model)
            expectEqual(geometry.keyboard, model)
            expectEqual(geometry.keys.count, model.keyCount)
            expectEqual(geometry.keys.map(\.index), Array(0..<model.keyCount))
            for key in geometry.keys {
                for (x, y) in [(key.x, key.y), (key.x + key.width, key.y), (key.x, key.y + key.height), (key.x + key.width, key.y + key.height)] {
                    let point = key.transformed(x: x, y: y)
                    expectGreaterThanOrEqual(point.x, 0); expectLessThanOrEqual(point.x, geometry.width)
                    expectGreaterThanOrEqual(point.y, 0); expectLessThanOrEqual(point.y, geometry.height)
                }
            }
        }
    }

    func testRemoteRevisionMismatchAndMalformedGeometryAreRejected() throws {
        let snapshot = try LayoutSnapshot.bundled()
        let response: JSONValue = .object(["data": .object(["layout": .object(["title": .string(snapshot.title), "revision": snapshot.source])])])
        let data = try JSONEncoder().encode(response)
        expectThrows(try OryxClient.decodeResponse(data, layoutID: "keyfinder-demo", revisionID: "different"))
        expectEqual(try OryxClient.decodeResponse(data, layoutID: "keyfinder-demo", revisionID: "latest"), snapshot)
        let invalid = LayoutSnapshot(layoutID: "keyfinder-demo", title: "Bad", revisionID: "v1", source: .object(["hashId": .string("v1"), "layers": .array([])]))
        expectThrows(try invalid.validated())
    }
}

private actor CountingClient: LayoutFetching {
    var count = 0
    let snapshot: LayoutSnapshot
    init(_ snapshot: LayoutSnapshot) { self.snapshot = snapshot }
    func fetch(keyboard: KeyboardModel, layoutID: String, revisionID: String) async throws -> LayoutSnapshot { count += 1; return snapshot }
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

private func keyboardFixture(_ keyboard: KeyboardModel) throws -> LayoutSnapshot {
    let keys: [JSONValue] = (0..<keyboard.keyCount).map { index in
        .object(["tap": .object(["code": .string("KC_A")]), "customLabel": .string("\(index)")])
    }
    return try LayoutSnapshot(layoutID: "shared-layout", title: keyboard.displayName, revisionID: "shared-revision",
                              source: .object(["hashId": .string("shared-revision"), "layers": .array([
                                .object(["position": .number(0), "title": .string("Typing"), "keys": .array(keys)]),
                                .object(["position": .number(1), "title": .string("Test layer"), "keys": .array(keys)])
                              ])]), keyboard: keyboard).validated()
}

private actor ModelClient: LayoutFetching {
    let snapshots: [KeyboardModel: LayoutSnapshot]
    private(set) var requested: [KeyboardModel] = []
    init(snapshots: [KeyboardModel: LayoutSnapshot]) { self.snapshots = snapshots }
    func fetch(keyboard: KeyboardModel, layoutID: String, revisionID: String) async throws -> LayoutSnapshot {
        requested.append(keyboard)
        guard let snapshot = snapshots[keyboard] else { throw KeyfinderError.service("Missing test fixture") }
        return snapshot
    }
}

extension RepositoryTests {
    func testCachesAndRefreshesAreScopedToKeyboardModels() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshots = try Dictionary(uniqueKeysWithValues: KeyboardModel.allCases.map { ($0, try keyboardFixture($0)) })
        let client = ModelClient(snapshots: snapshots)
        let repository = LayoutRepository(directory: directory, client: client, bundled: nil)
        for model in KeyboardModel.allCases {
            let snapshot = snapshots[model]!
            expectEqual(try await repository.installed(snapshot.identity), snapshot)
            expectEqual(try await repository.refresh(OryxLocation(url: snapshot.identity.url.absoluteString)), snapshot)
        }
        for model in KeyboardModel.allCases {
            expectEqual(await repository.cached(snapshots[model]!.identity), snapshots[model])
        }
        let requests = await client.requested
        expectEqual(requests, [.moonlander, .moonlander, .voyager, .voyager, .ergodoxEZ, .ergodoxEZ])
        let wrongClient = ModelClient(snapshots: [.voyager: snapshots[.ergodoxEZ]!])
        let other = LayoutRepository(directory: directory.appendingPathComponent("invalid"), client: wrongClient, bundled: nil)
        do {
            _ = try await other.refresh(OryxLocation(url: snapshots[.voyager]!.identity.url.absoluteString))
            expectTrue(false, "A response for another model must be rejected.")
        } catch { expectNil(await other.cached(snapshots[.ergodoxEZ]!.identity)) }
    }
}
