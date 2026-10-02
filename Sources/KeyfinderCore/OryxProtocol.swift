import Foundation

public enum OryxReport: Equatable, Sendable {
    case layer(Int), firmware(String), protocolVersion(Int), paired, pairingRequired, error(UInt8)
}

/// Decodes only control reports. Physical key reports never leave the HID callback.
public enum OryxProtocol {
    public static let reportSize = 32
    public static let vendorID = 0x3297
    public static let usagePage = 0xFF60
    public static let usage = 0x61

    public static func command(_ code: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportSize); report[0] = code; return report
    }
    public static func decode(_ bytes: UnsafeBufferPointer<UInt8>) -> OryxReport? {
        guard bytes.count == reportSize else { return nil }
        switch bytes[0] {
        case 0x05:
            guard bytes[2] == 0xFE, bytes[1] < 32 else { return nil }
            return .layer(Int(bytes[1]))
        case 0x00:
            guard let end = (1..<bytes.count).first(where: { bytes[$0] == 0xFE }), end > 1,
                  let value = String(bytes: bytes[1..<end], encoding: .utf8) else { return nil }
            return .firmware(value)
        case 0xFE:
            guard bytes[2] == 0xFE else { return nil }; return .protocolVersion(Int(bytes[1]))
        case 0x04:
            guard bytes[1] == 0xFE else { return nil }; return .paired
        case 0x01, 0x02, 0x03: return .pairingRequired
        case 0xFF: return .error(bytes[1])
        default: return nil
        }
    }
    public static func decode(_ bytes: [UInt8]) -> OryxReport? { bytes.withUnsafeBufferPointer(decode) }
}

public struct LayoutLease: Equatable, Sendable {
    public let generation: UInt64
    public let identity: LayoutIdentity
}

/// A fetch belongs to one device connection and one installed revision.
public struct LiveSession: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var connected = false
    public private(set) var identity: LayoutIdentity?
    public private(set) var layer: Int?
    public private(set) var snapshot: LayoutSnapshot?
    public init() {}
    public mutating func connect(identity: LayoutIdentity?) {
        generation &+= 1; connected = true; self.identity = identity; layer = nil; snapshot = nil
    }
    public mutating func identify(_ identity: LayoutIdentity) {
        guard connected, self.identity != identity else { return }
        generation &+= 1; self.identity = identity; snapshot = nil
    }
    public mutating func disconnect() {
        generation &+= 1; connected = false; identity = nil; layer = nil; snapshot = nil
    }
    @discardableResult public mutating func setLayer(_ layer: Int) -> Bool {
        guard connected, (0..<32).contains(layer), self.layer != layer else { return false }
        self.layer = layer; return true
    }
    public var lease: LayoutLease? { identity.map { LayoutLease(generation: generation, identity: $0) } }
    @discardableResult public mutating func accept(_ snapshot: LayoutSnapshot, for lease: LayoutLease) -> Bool {
        guard connected, self.lease == lease, (try? snapshot.validated(expected: lease.identity)) != nil else { return false }
        self.snapshot = snapshot; return true
    }
    public var shouldShowOverlay: Bool { connected && (layer ?? 0) > 0 }
}
