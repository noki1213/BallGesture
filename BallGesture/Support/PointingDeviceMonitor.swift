//
//  PointingDeviceMonitor.swift
//  BallGesture
//
//  Watches the movement of one specific pointing device through IOHIDManager.
//  Pointer events reaching an event tap carry nothing that says which device
//  produced them, so telling a trackball apart from a trackpad needs the HID
//  layer.
//

import AppKit
import IOKit.hid

/// A pointing device as it describes itself. The product name is part of the
/// identity because devices running the same open-source keyboard firmware
/// often share one vendor and product ID.
struct PointingDeviceID: Codable, Hashable, Identifiable {
    var vendorID: Int
    var productID: Int
    var product: String

    var id: String { "\(vendorID):\(productID):\(product)" }

    fileprivate init?(device: IOHIDDevice) {
        guard let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String else {
            return nil
        }
        self.product = product
        vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    }

    fileprivate var matchingDictionary: NSDictionary {
        [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID, kIOHIDProductKey: product]
    }
}

final class PointingDeviceMonitor {
    /// Called on the main thread with each movement report, in device counts.
    var onMove: ((Int, Int) -> Void)?

    private var manager: IOHIDManager?

    /// Mice and other pointers, including keyboards that also carry a pointing device.
    private static let pointingMatching: [NSDictionary] = [
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer]
    ]

    /// Reading a device's input reports needs Input Monitoring permission,
    /// separate from the Accessibility permission the event tap uses.
    static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoringAccess() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openInputMonitoringSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pointing devices connected right now. Enumerating needs no permission.
    static func connectedDevices() -> [PointingDeviceID] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, pointingMatching as CFArray)
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        var values = [UnsafeRawPointer?](repeating: nil, count: CFSetGetCount(set))
        CFSetGetValues(set, &values)
        // A device often shows up once per HID interface.
        var seen = Set<PointingDeviceID>()
        return values
            .compactMap { $0.flatMap { PointingDeviceID(device: unsafeBitCast($0, to: IOHIDDevice.self)) } }
            .filter { seen.insert($0).inserted }
            .sorted { $0.product.localizedStandardCompare($1.product) == .orderedAscending }
    }

    var isRunning: Bool { manager != nil }

    /// Starts reporting the movement of `device`. Returns false if the
    /// device cannot be opened, almost always because Input Monitoring
    /// permission has not been granted.
    @discardableResult
    func start(device: PointingDeviceID) -> Bool {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, device.matchingDictionary)
        IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: kHIDPage_GenericDesktop] as NSDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, inputValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }
        self.manager = manager
        return true
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    fileprivate func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let amount = IOHIDValueGetIntegerValue(value)
        guard amount != 0, IOHIDElementIsRelative(element) else { return }
        switch Int(IOHIDElementGetUsage(element)) {
        case kHIDUsage_GD_X: onMove?(amount, 0)
        case kHIDUsage_GD_Y: onMove?(0, amount)
        default: break
        }
    }
}

/// Runs on the main run loop, where the manager is scheduled.
nonisolated private func inputValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let monitor = Unmanaged<PointingDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handle(value)
    }
}
