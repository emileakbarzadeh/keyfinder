import AppKit
import IOKit.hid
import KeyfinderCore

struct ConnectedKeyboard: Equatable {
    let name: String
    let serial: String
    let productID: Int
    var model: KeyboardModel? { KeyboardModel.detect(productID: productID, productName: name) }
    var displayName: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? model?.displayName ?? "Keyboard" : name
    }
}

enum KeyboardEvent {
    case connected(ConnectedKeyboard)
    case identity(LayoutIdentity)
    case layer(Int)
    case protocolVersion(Int)
    case disconnected
    case problem(String, blocking: Bool)
}

@MainActor protocol KeyboardMonitoring: AnyObject {
    var onEvent: ((KeyboardEvent) -> Void)? { get set }
    func start()
    func stop()
    func reconnect()
}

/// IOKit callbacks are scheduled exclusively on the main run loop. No polling thread.
@MainActor final class HIDMonitor: KeyboardMonitoring {
    var onEvent: ((KeyboardEvent) -> Void)?
    private var manager: IOHIDManager?
    private var session: HIDSession?
    private var devices: [IOHIDDevice] = []
    private var deadline: DispatchWorkItem?
    private var receivedLayer = false
    private var supported = true

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let match = [kIOHIDVendorIDKey: OryxProtocol.vendorID,
                     kIOHIDDeviceUsagePageKey: OryxProtocol.usagePage,
                     kIOHIDDeviceUsageKey: OryxProtocol.usage]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            MainActor.assumeIsolated { Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().attached(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated { Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().removed(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess { reportOpenError(result) }
    }

    func stop() {
        deadline?.cancel(); deadline = nil
        session?.close(); session = nil
        devices.removeAll()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        receivedLayer = false
        onEvent?(.disconnected)
    }

    func reconnect() { stop(); start() }

    private func attached(_ device: IOHIDDevice) {
        guard Self.identity(of: device).model != nil, !devices.contains(where: { CFEqual($0, device) }) else { return }
        devices.append(device)
        if session == nil { connect(device) }
    }

    private static func identity(of device: IOHIDDevice) -> ConnectedKeyboard {
        ConnectedKeyboard(name: (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "",
                          serial: (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String) ?? "",
                          productID: (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0)
    }

    private func connect(_ device: IOHIDDevice) {
        let deviceIdentity = Self.identity(of: device)
        guard let keyboard = deviceIdentity.model else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { reportOpenError(result); return }
        receivedLayer = false; supported = true
        let session = HIDSession(device: device, keyboard: keyboard, monitor: self)
        self.session = session
        let serial = deviceIdentity.serial
        onEvent?(.connected(deviceIdentity))
        IOHIDDeviceRegisterInputReportCallback(device, session.buffer, session.capacity, { context, result, _, _, _, report, length in
            // Stock Oryx also sends keydown/up reports. Drop them before allocating,
            // publishing state, resolving labels, or scheduling any work.
            guard let context, result == kIOReturnSuccess, length == OryxProtocol.reportSize,
                  report[0] != 0x06, report[0] != 0x07 else { return }
            guard let decoded = OryxProtocol.decode(UnsafeBufferPointer(start: report, count: length)) else { return }
            MainActor.assumeIsolated {
                let session = Unmanaged<HIDSession>.fromOpaque(context).takeUnretainedValue()
                session.monitor?.received(decoded, from: session)
            }
        }, Unmanaged.passUnretained(session).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // These requests do not change the layout, layer, lights, or firmware.
        _ = send(0xFE)
        if (try? LayoutIdentity(serial: serial, keyboard: keyboard)) == nil { _ = send(0x00) }
        guard send(0x01) else { return }
        let timeout = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, self.session === session, !self.receivedLayer else { return }
            self.onEvent?(.problem("The keyboard did not report its layer. Try Retry connection. If this persists, close other live-training sessions and use a current Oryx firmware build.", blocking: true))
            self.deadline = nil
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    private func send(_ command: UInt8) -> Bool {
        guard let session else { return false }
        let bytes = OryxProtocol.command(command)
        let result = bytes.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(session.device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
        }
        if result != kIOReturnSuccess, command == 0x01 {
            onEvent?(.problem("Could not subscribe to keyboard layer changes (USB error \(result)). Try Retry connection.", blocking: true))
        }
        return result == kIOReturnSuccess
    }

    fileprivate func received(_ report: OryxReport, from source: HIDSession) {
        guard session === source else { return }
        switch report {
        case .layer(let layer):
            guard supported else { return }
            receivedLayer = true
            deadline?.cancel(); deadline = nil
            onEvent?(.layer(layer))
        case .firmware(let serial):
            if let identity = try? LayoutIdentity(serial: serial, keyboard: source.keyboard) { onEvent?(.identity(identity)) }
        case .protocolVersion(let version):
            onEvent?(.protocolVersion(version))
            if !(1...5).contains(version) {
                supported = false; deadline?.cancel(); deadline = nil
                onEvent?(.problem("This keyboard uses Oryx protocol \(version), which this Keyfinder version does not support.", blocking: true))
            }
        case .pairingRequired:
            deadline?.cancel(); deadline = nil
            onEvent?(.problem("This firmware requires the older live-training pairing flow. Compile and flash a current Oryx build, then retry the connection.", blocking: true))
        case .paired: break // A current-layer event follows; wait for it.
        case .error(let code):
            // Older firmware may reject the protocol-version query while still
            // supporting ordinary layer reports. The one-shot handshake checks it.
            if code != 0xFF { onEvent?(.problem("The keyboard reported a pairing error (\(code)). Retry the connection.", blocking: true)) }
        }
    }

    private func removed(_ device: IOHIDDevice) {
        devices.removeAll { CFEqual($0, device) }
        guard let current = session, CFEqual(current.device, device) else { return }
        deadline?.cancel(); deadline = nil
        current.close(); session = nil; receivedLayer = false
        onEvent?(.disconnected)
        if let next = devices.first { connect(next) }
    }

    private func reportOpenError(_ result: IOReturn) {
        let detail = result == kIOReturnNotPermitted
            ? "macOS denied USB access. Enable Keyfinder in System Settings → Privacy & Security → Input Monitoring if it is listed, then retry."
            : "Could not open the keyboard’s USB interface (\(result)). Check its connection and try Retry connection."
        onEvent?(.problem(detail, blocking: true))
    }
}

@MainActor private final class HIDSession {
    let device: IOHIDDevice
    let keyboard: KeyboardModel
    weak var monitor: HIDMonitor?
    let capacity = 64
    let buffer: UnsafeMutablePointer<UInt8>
    private var closed = false
    init(device: IOHIDDevice, keyboard: KeyboardModel, monitor: HIDMonitor) {
        self.device = device; self.keyboard = keyboard; self.monitor = monitor
        buffer = .allocate(capacity: capacity); buffer.initialize(repeating: 0, count: capacity)
    }
    func close() {
        guard !closed else { return }; closed = true
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        monitor = nil
    }
    deinit { buffer.deinitialize(count: capacity); buffer.deallocate() }
}
