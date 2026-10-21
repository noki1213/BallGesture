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

/// A view operation in 3D apps (CAD, slicers, WebGL viewers), each held on its own trigger key.
enum ThreeDAction: String, CaseIterable, Identifiable, Codable {
    case pan
    case zoom
    case rotate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pan: return "Pan"
        case .zoom: return "Zoom"
        case .rotate: return "Rotate"
        }
    }
}

/// What a 3D trigger key turns pointer movement into.
enum ThreeDOutput: String, CaseIterable, Identifiable, Codable {
    case leftDrag
    case rightDrag
    case middleDrag
    case shiftMiddleDrag
    case scroll
    case shiftScroll
    case pinch
    case wheel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftDrag: return "Left Drag"
        case .rightDrag: return "Right Drag"
        case .middleDrag: return "Middle Drag"
        case .shiftMiddleDrag: return "Shift + Middle Drag"
        case .scroll: return "Scroll"
        case .shiftScroll: return "Shift + Scroll"
        case .pinch: return "Pinch"
        case .wheel: return "Wheel"
        }
    }
}

struct ThreeDBinding: Codable, Equatable {
    var output: ThreeDOutput
    /// Flips both axes of the movement.
    var reversed = false
}

/// The output for each 3D action, either the default set or one app's override.
struct ThreeDProfile: Codable, Equatable {
    var pan: ThreeDBinding
    var zoom: ThreeDBinding
    var rotate: ThreeDBinding

    /// Right drag pans, the wheel zooms and left drag orbits: the mouse
    /// layout shared by most slicers, OpenSCAD and three.js OrbitControls.
    static let standard = ThreeDProfile(
        pan: ThreeDBinding(output: .rightDrag),
        zoom: ThreeDBinding(output: .wheel),
        rotate: ThreeDBinding(output: .leftDrag)
    )

    subscript(action: ThreeDAction) -> ThreeDBinding {
        get {
            switch action {
            case .pan: return pan
            case .zoom: return zoom
            case .rotate: return rotate
            }
        }
        set {
            switch action {
            case .pan: pan = newValue
            case .zoom: zoom = newValue
            case .rotate: rotate = newValue
            }
        }
    }
}

struct ThreeDAppProfile: Codable, Equatable, Identifiable {
    var bundleID: String
    var profile: ThreeDProfile

    var id: String { bundleID }
}

/// A mouse button that a key turns into while the auto mouse layer is on.
enum AutoMouseButton: String, CaseIterable, Identifiable {
    case left
    case right
    case middle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        }
    }
}

/// Which trigger key is currently being (re)captured from the "Set Key" UI.
enum KeyCaptureTarget: Equatable {
    case scrollTrigger
    case zoomTrigger
    case gestureTrigger
    case threeDTrigger(ThreeDAction)
    case autoMouseButton(AutoMouseButton)
    case autoMouseHoldKey(AutoMouseButton)
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
        static let gestureTriggerKeyCode = "BallGesture.gestureTriggerKeyCode"
        static let gestureDistance = "BallGesture.gestureDistance"
        static let threeDSensitivity = "BallGesture.threeDSensitivity"
        static let threeDDefaultProfile = "BallGesture.threeDDefaultProfile"
        static let threeDAppProfiles = "BallGesture.threeDAppProfiles"
        static func threeDTriggerKeyCode(_ action: ThreeDAction) -> String {
            "BallGesture.threeDTriggerKeyCode.\(action.rawValue)"
        }
        static let autoMouseEnabled = "BallGesture.autoMouseEnabled"
        static let autoMouseDevice = "BallGesture.autoMouseDevice"
        static let autoMouseTimeout = "BallGesture.autoMouseTimeout"
        static func autoMouseKeyCode(_ button: AutoMouseButton) -> String {
            "BallGesture.autoMouseKeyCode.\(button.rawValue)"
        }
        static func autoMouseHoldKeyCode(_ button: AutoMouseButton) -> String {
            "BallGesture.autoMouseHoldKeyCode.\(button.rawValue)"
        }
    }

    static let defaultScrollTriggerKeyCode = Int64(kVK_F15) // 113
    static let defaultZoomTriggerKeyCode = Int64(kVK_F16)   // 106
    static let defaultGestureTriggerKeyCode = Int64(64)     // F17
    static func defaultThreeDTriggerKeyCode(_ action: ThreeDAction) -> Int64 {
        switch action {
        case .pan: return Int64(kVK_F18)
        case .zoom: return Int64(kVK_F19)
        case .rotate: return Int64(kVK_F20)
        }
    }
    static func defaultAutoMouseKeyCode(_ button: AutoMouseButton) -> Int64 {
        switch button {
        case .left: return Int64(kVK_ANSI_J)
        case .right: return Int64(kVK_ANSI_K)
        case .middle: return Int64(kVK_ANSI_L)
        }
    }

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

    @Published var gestureDistance: Double {
        didSet { defaults.set(gestureDistance, forKey: Keys.gestureDistance) }
    }

    @Published var threeDSensitivity: Double {
        didSet { defaults.set(threeDSensitivity, forKey: Keys.threeDSensitivity) }
    }

    /// Used in every app without its own entry in `threeDAppProfiles`.
    @Published var threeDDefaultProfile: ThreeDProfile {
        didSet { Self.store(threeDDefaultProfile, in: defaults, forKey: Keys.threeDDefaultProfile) }
    }

    @Published var threeDAppProfiles: [ThreeDAppProfile] {
        didSet { Self.store(threeDAppProfiles, in: defaults, forKey: Keys.threeDAppProfiles) }
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

    @Published private(set) var gestureTriggerKeyCode: Int64 {
        didSet { defaults.set(gestureTriggerKeyCode, forKey: Keys.gestureTriggerKeyCode) }
    }

    @Published private(set) var threeDTriggerKeyCodes: [ThreeDAction: Int64] {
        didSet {
            for (action, keyCode) in threeDTriggerKeyCodes {
                defaults.set(keyCode, forKey: Keys.threeDTriggerKeyCode(action))
            }
        }
    }

    @Published var autoMouseEnabled: Bool {
        didSet { defaults.set(autoMouseEnabled, forKey: Keys.autoMouseEnabled) }
    }

    /// The device whose movement turns the layer on; nil for any pointer.
    @Published var autoMouseDevice: PointingDeviceID? {
        didSet {
            if let autoMouseDevice {
                Self.store(autoMouseDevice, in: defaults, forKey: Keys.autoMouseDevice)
            } else {
                defaults.removeObject(forKey: Keys.autoMouseDevice)
            }
        }
    }

    /// Seconds the layer stays on after the pointer stops.
    @Published var autoMouseTimeout: Double {
        didSet { defaults.set(autoMouseTimeout, forKey: Keys.autoMouseTimeout) }
    }

    @Published private(set) var autoMouseKeyCodes: [AutoMouseButton: Int64] {
        didSet {
            for (button, keyCode) in autoMouseKeyCodes {
                defaults.set(keyCode, forKey: Keys.autoMouseKeyCode(button))
            }
        }
    }

    /// A second key per button, usually a modifier, for keyboards whose
    /// layer key sends a modifier when held (home row mods): the key itself
    /// arrives only when tapped, so holding it to drag needs the modifier.
    @Published private(set) var autoMouseHoldKeyCodes: [AutoMouseButton: Int64] {
        didSet {
            for button in AutoMouseButton.allCases {
                if let keyCode = autoMouseHoldKeyCodes[button] {
                    defaults.set(keyCode, forKey: Keys.autoMouseHoldKeyCode(button))
                } else {
                    defaults.removeObject(forKey: Keys.autoMouseHoldKeyCode(button))
                }
            }
        }
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
        gestureDistance = defaults.object(forKey: Keys.gestureDistance) as? Double ?? 50.0
        threeDSensitivity = defaults.object(forKey: Keys.threeDSensitivity) as? Double ?? 1.0
        threeDDefaultProfile = Self.load(ThreeDProfile.self, from: defaults, forKey: Keys.threeDDefaultProfile)
            ?? .standard
        threeDAppProfiles = Self.load([ThreeDAppProfile].self, from: defaults, forKey: Keys.threeDAppProfiles)
            ?? []
        zoomMethod = ZoomMethod(rawValue: defaults.string(forKey: Keys.zoomMethod) ?? "") ?? .pinch
        scrollTriggerKeyCode = defaults.object(forKey: Keys.scrollTriggerKeyCode) as? Int64
            ?? Self.defaultScrollTriggerKeyCode
        zoomTriggerKeyCode = defaults.object(forKey: Keys.zoomTriggerKeyCode) as? Int64
            ?? Self.defaultZoomTriggerKeyCode
        gestureTriggerKeyCode = defaults.object(forKey: Keys.gestureTriggerKeyCode) as? Int64
            ?? Self.defaultGestureTriggerKeyCode
        var threeDKeys: [ThreeDAction: Int64] = [:]
        for action in ThreeDAction.allCases {
            threeDKeys[action] = defaults.object(forKey: Keys.threeDTriggerKeyCode(action)) as? Int64
                ?? Self.defaultThreeDTriggerKeyCode(action)
        }
        threeDTriggerKeyCodes = threeDKeys
        autoMouseEnabled = defaults.object(forKey: Keys.autoMouseEnabled) as? Bool ?? false
        autoMouseDevice = Self.load(PointingDeviceID.self, from: defaults, forKey: Keys.autoMouseDevice)
        autoMouseTimeout = defaults.object(forKey: Keys.autoMouseTimeout) as? Double ?? 0.7
        var autoMouseKeys: [AutoMouseButton: Int64] = [:]
        for button in AutoMouseButton.allCases {
            autoMouseKeys[button] = defaults.object(forKey: Keys.autoMouseKeyCode(button)) as? Int64
                ?? Self.defaultAutoMouseKeyCode(button)
        }
        autoMouseKeyCodes = autoMouseKeys
        var autoMouseHoldKeys: [AutoMouseButton: Int64] = [:]
        for button in AutoMouseButton.allCases {
            autoMouseHoldKeys[button] = defaults.object(forKey: Keys.autoMouseHoldKeyCode(button)) as? Int64
        }
        autoMouseHoldKeyCodes = autoMouseHoldKeys
    }

    func autoMouseKeyCode(for button: AutoMouseButton) -> Int64 {
        autoMouseKeyCodes[button] ?? Self.defaultAutoMouseKeyCode(button)
    }

    /// The mouse button `keyCode` turns into while the auto mouse layer is on, if any.
    func autoMouseButton(forKeyCode keyCode: Int64) -> AutoMouseButton? {
        AutoMouseButton.allCases.first { autoMouseKeyCode(for: $0) == keyCode }
    }

    /// The mouse button holding `keyCode` presses while the auto mouse layer is on, if any.
    func autoMouseButton(forHoldKeyCode keyCode: Int64) -> AutoMouseButton? {
        AutoMouseButton.allCases.first { autoMouseHoldKeyCodes[$0] == keyCode }
    }

    func clearAutoMouseHoldKey(for button: AutoMouseButton) {
        autoMouseHoldKeyCodes[button] = nil
    }

    func threeDTriggerKeyCode(for action: ThreeDAction) -> Int64 {
        threeDTriggerKeyCodes[action] ?? Self.defaultThreeDTriggerKeyCode(action)
    }

    /// The 3D action bound to `keyCode`, if any.
    func threeDAction(forKeyCode keyCode: Int64) -> ThreeDAction? {
        ThreeDAction.allCases.first { threeDTriggerKeyCode(for: $0) == keyCode }
    }

    /// The profile for `bundleID`, falling back to the default profile.
    func threeDProfile(forBundleID bundleID: String?) -> ThreeDProfile {
        threeDAppProfiles.first { $0.bundleID == bundleID }?.profile ?? threeDDefaultProfile
    }

    /// Adds an app override, starting from a copy of the default profile.
    func addThreeDAppProfile(bundleID: String) {
        guard !threeDAppProfiles.contains(where: { $0.bundleID == bundleID }) else { return }
        threeDAppProfiles.append(ThreeDAppProfile(bundleID: bundleID, profile: threeDDefaultProfile))
    }

    private static func store<T: Encodable>(_ value: T, in defaults: UserDefaults, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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

        let assignedKeys: [(KeyCaptureTarget, Int64, String)] = [
            (.scrollTrigger, scrollTriggerKeyCode, "Scroll Mode"),
            (.zoomTrigger, zoomTriggerKeyCode, "Zoom Mode"),
            (.gestureTrigger, gestureTriggerKeyCode, "Gesture Mode")
        ] + ThreeDAction.allCases.map {
            (.threeDTrigger($0), threeDTriggerKeyCode(for: $0), "3D \($0.displayName)")
        } + AutoMouseButton.allCases.map {
            (.autoMouseButton($0), autoMouseKeyCode(for: $0), $0.displayName)
        } + AutoMouseButton.allCases.compactMap { button in
            autoMouseHoldKeyCodes[button].map { (.autoMouseHoldKey(button), $0, "\(button.displayName) (Held)") }
        }
        let otherKeys = assignedKeys.filter { $0.0 != target }

        for (_, otherKeyCode, otherName) in otherKeys {
            if keyCode == otherKeyCode {
                captureErrorMessage = "That key is already assigned to \(otherName). Choose a different key."
                captureTarget = nil
                return true
            }
        }

        switch target {
        case .scrollTrigger: scrollTriggerKeyCode = keyCode
        case .zoomTrigger: zoomTriggerKeyCode = keyCode
        case .gestureTrigger: gestureTriggerKeyCode = keyCode
        case .threeDTrigger(let action): threeDTriggerKeyCodes[action] = keyCode
        case .autoMouseButton(let button): autoMouseKeyCodes[button] = keyCode
        case .autoMouseHoldKey(let button): autoMouseHoldKeyCodes[button] = keyCode
        }
        captureErrorMessage = nil
        captureTarget = nil
        return true
    }
}
