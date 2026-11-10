//
//  SystemStatus.swift
//  BallGesture
//
//  Things the system can change behind the app's back, polled for the panel and the settings.
//

import Combine
import Foundation

@MainActor
final class SystemStatus: ObservableObject {
    static let shared = SystemStatus()

    @Published private(set) var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @Published private(set) var pointingDevices = PointingDeviceMonitor.connectedDevices()

    private var timer: AnyCancellable?

    private init() {
        // Neither permission changes nor device plugs post a notification the app can rely on.
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let trusted = AccessibilityPermission.isTrusted
        if trusted != isAccessibilityTrusted { isAccessibilityTrusted = trusted }
        let devices = PointingDeviceMonitor.connectedDevices()
        if devices != pointingDevices { pointingDevices = devices }
    }
}
