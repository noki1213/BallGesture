//
//  AppSettings.swift
//  BallGesture
//
//  UserDefaults-backed settings, shared between the menu bar UI and GestureEngine.
//

import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

enum ZoomMethod: String, CaseIterable, Identifiable {
    case pinch
    case ctrlScroll
    case cmdScroll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pinch: return "Pinch Gesture (native)"
        case .ctrlScroll: return "Ctrl + Scroll"
        case .cmdScroll: return "Cmd + Scroll"
        }
    }
}

/// Which trigger key is currently being (re)captured from the "Set Key" UI.
enum KeyCaptureTarget {
    case scrollTrigger
    case zoomTrigger
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let isEnabled = "BallGesture.isEnabled"
        static let scrollSensitivity = "BallGesture.scrollSensitivity"
        static let zoomSensitivity = "BallGesture.zoomSensitivity"
        static let naturalScrollDirection = "BallGesture.naturalScrollDirection"
        static let momentumScrollingEnabled = "BallGesture.momentumScrollingEnabled"
        static let momentumStrength = "BallGesture.momentumStrength"
        static let zoomMethod = "BallGesture.zoomMethod"
        static let scrollTriggerKeyCode = "BallGesture.scrollTriggerKeyCode"
        static let zoomTriggerKeyCode = "BallGesture.zoomTriggerKeyCode"
    }

    static let defaultScrollTriggerKeyCode = Int64(kVK_F15) // 113
    static let defaultZoomTriggerKeyCode = Int64(kVK_F16)   // 106

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var scrollSensitivity: Double {
        didSet { defaults.set(scrollSensitivity, forKey: Keys.scrollSensitivity) }
    }

    @Published var zoomSensitivity: Double {
        didSet { defaults.set(zoomSensitivity, forKey: Keys.zoomSensitivity) }
    }

    @Published var naturalScrollDirection: Bool {
        didSet { defaults.set(naturalScrollDirection, forKey: Keys.naturalScrollDirection) }
    }

    @Published var momentumScrollingEnabled: Bool {
        didSet { defaults.set(momentumScrollingEnabled, forKey: Keys.momentumScrollingEnabled) }
    }

    /// 0...1. Higher = looser/longer momentum (a longer decay half-life).
    @Published var momentumStrength: Double {
        didSet { defaults.set(momentumStrength, forKey: Keys.momentumStrength) }
    }

    @Published var zoomMethod: ZoomMethod {
        didSet { defaults.set(zoomMethod.rawValue, forKey: Keys.zoomMethod) }
    }

    @Published private(set) var scrollTriggerKeyCode: Int64 {
        didSet { defaults.set(scrollTriggerKeyCode, forKey: Keys.scrollTriggerKeyCode) }
    }

    @Published private(set) var zoomTriggerKeyCode: Int64 {
        didSet { defaults.set(zoomTriggerKeyCode, forKey: Keys.zoomTriggerKeyCode) }
    }

    /// Non-persisted UI state: which trigger key is currently being captured.
    @Published var captureTarget: KeyCaptureTarget?
    /// Non-persisted UI state: message shown when a capture attempt is rejected.
    @Published var captureErrorMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        scrollSensitivity = defaults.object(forKey: Keys.scrollSensitivity) as? Double ?? 1.0
        zoomSensitivity = defaults.object(forKey: Keys.zoomSensitivity) as? Double ?? 1.0
        naturalScrollDirection = defaults.object(forKey: Keys.naturalScrollDirection) as? Bool ?? true
        momentumScrollingEnabled = defaults.object(forKey: Keys.momentumScrollingEnabled) as? Bool ?? true
        momentumStrength = defaults.object(forKey: Keys.momentumStrength) as? Double ?? 0.5
        zoomMethod = ZoomMethod(rawValue: defaults.string(forKey: Keys.zoomMethod) ?? "") ?? .pinch
        scrollTriggerKeyCode = defaults.object(forKey: Keys.scrollTriggerKeyCode) as? Int64
            ?? Self.defaultScrollTriggerKeyCode
        zoomTriggerKeyCode = defaults.object(forKey: Keys.zoomTriggerKeyCode) as? Int64
            ?? Self.defaultZoomTriggerKeyCode
    }

    /// Starts capturing the next pressed key for the given target.
    func beginCapture(for target: KeyCaptureTarget) {
        captureErrorMessage = nil
        captureTarget = target
    }

    func cancelCapture() {
        captureTarget = nil
        captureErrorMessage = nil
    }

    /// Called by GestureEngine when a key was pressed while capturing.
    /// Returns true if the key was consumed (i.e. we were capturing).
    @discardableResult
    func handleCapturedKeyCode(_ keyCode: Int64) -> Bool {
        guard let target = captureTarget else { return false }

        let otherKeyCode = (target == .scrollTrigger) ? zoomTriggerKeyCode : scrollTriggerKeyCode
        if keyCode == otherKeyCode {
            let otherName = (target == .scrollTrigger) ? "Zoom Mode" : "Scroll Mode"
            captureErrorMessage = "That key is already assigned to \(otherName). Choose a different key."
            captureTarget = nil
            return true
        }

        switch target {
        case .scrollTrigger: scrollTriggerKeyCode = keyCode
        case .zoomTrigger: zoomTriggerKeyCode = keyCode
        }
        captureErrorMessage = nil
        captureTarget = nil
        return true
    }
}
