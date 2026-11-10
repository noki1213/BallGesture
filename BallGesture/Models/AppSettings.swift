//
//  AppSettings.swift
//  BallGesture
//
//  Settings stored in ~/.config/ballgesture/config.json, shared between the
//  settings window and GestureEngine.
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
    /// Flips Shift + trackpad scrolling in this app, for apps that pan on
    /// that gesture with a fixed sign and so ignore natural scrolling.
    var reversesShiftTrackpadScroll = false

    var id: String { bundleID }
}

extension ThreeDAppProfile {
    /// A saved entry without the switch still decodes; one failed entry
    /// would otherwise discard the whole saved list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        profile = try container.decode(ThreeDProfile.self, forKey: .profile)
        reversesShiftTrackpadScroll = try container.decodeIfPresent(Bool.self, forKey: .reversesShiftTrackpadScroll) ?? false
    }
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

/// Which trigger key is currently being recorded from the settings window.
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

    /// Hand-editable; read at launch, watched while running, and written as
    /// settings change in the app.
    static let configFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ballgesture/config.json")

    static let defaultScrollTriggerKeyCode = ConfigValues.defaultScrollTriggerKeyCode
    static let defaultZoomTriggerKeyCode = ConfigValues.defaultZoomTriggerKeyCode
    static let defaultGestureTriggerKeyCode = ConfigValues.defaultGestureTriggerKeyCode
    static func defaultThreeDTriggerKeyCode(_ action: ThreeDAction) -> Int64 {
        ConfigValues.defaultThreeDTriggerKeyCode(action)
    }
    static func defaultAutoMouseKeyCode(_ button: AutoMouseButton) -> Int64 {
        ConfigValues.defaultAutoMouseKeyCode(button)
    }

    private static let unparseableMessage =
        "config.json is not valid JSON; keeping the current settings and not saving changes until it is fixed."

    private let configFile: ConfigFile
    /// Set while values from the file are being applied, so they are not
    /// written straight back.
    private var isApplyingConfig = false
    private var isSaveScheduled = false

    @Published var isEnabled: Bool {
        didSet { scheduleSave() }
    }

    @Published var scrollSensitivity: Double {
        didSet { scheduleSave() }
    }

    @Published var zoomSensitivity: Double {
        didSet { scheduleSave() }
    }

    @Published var naturalScrollDirection: Bool {
        didSet { scheduleSave() }
    }

    @Published var momentumScrollingEnabled: Bool {
        didSet { scheduleSave() }
    }

    /// 0...1. Higher = looser/longer momentum (a longer decay half-life).
    @Published var momentumStrength: Double {
        didSet { scheduleSave() }
    }

    @Published var gestureDistance: Double {
        didSet { scheduleSave() }
    }

    @Published var threeDSensitivity: Double {
        didSet { scheduleSave() }
    }

    /// Used in every app without its own entry in `threeDAppProfiles`.
    @Published var threeDDefaultProfile: ThreeDProfile {
        didSet { scheduleSave() }
    }

    @Published var threeDAppProfiles: [ThreeDAppProfile] {
        didSet { scheduleSave() }
    }

    @Published var zoomMethod: ZoomMethod {
        didSet { scheduleSave() }
    }

    @Published private(set) var scrollTriggerKeyCode: Int64 {
        didSet { scheduleSave() }
    }

    @Published private(set) var zoomTriggerKeyCode: Int64 {
        didSet { scheduleSave() }
    }

    @Published private(set) var gestureTriggerKeyCode: Int64 {
        didSet { scheduleSave() }
    }

    @Published private(set) var threeDTriggerKeyCodes: [ThreeDAction: Int64] {
        didSet { scheduleSave() }
    }

    @Published var autoMouseEnabled: Bool {
        didSet { scheduleSave() }
    }

    /// The device whose movement turns the layer on; nil for any pointer.
    @Published var autoMouseDevice: PointingDeviceID? {
        didSet { scheduleSave() }
    }

    /// Seconds the layer stays on after the pointer stops.
    @Published var autoMouseTimeout: Double {
        didSet { scheduleSave() }
    }

    @Published private(set) var autoMouseKeyCodes: [AutoMouseButton: Int64] {
        didSet { scheduleSave() }
    }

    /// A second key per button, usually a modifier, for keyboards whose
    /// layer key sends a modifier when held (home row mods): the key itself
    /// arrives only when tapped, so holding it to drag needs the modifier.
    @Published private(set) var autoMouseHoldKeyCodes: [AutoMouseButton: Int64] {
        didSet { scheduleSave() }
    }

    /// Problems found in config.json by the last read or write, one per
    /// line; nil when the file is fine.
    @Published private(set) var configErrorMessage: String?

    /// Non-persisted UI state: which trigger key is currently being captured.
    @Published var captureTarget: KeyCaptureTarget?
    /// Non-persisted UI state: message shown when a capture attempt is rejected.
    @Published var captureErrorMessage: String?

    /// `defaults` is only read, to carry settings from earlier versions into
    /// a config file that does not exist yet.
    init(defaults: UserDefaults = .standard) {
        configFile = ConfigFile(url: Self.configFileURL)

        let values: ConfigValues
        var problems: [String] = []
        var needsWrite = false
        switch configFile.read() {
        case .missing:
            values = ConfigValues(migratingFrom: defaults)
            needsWrite = true
        case .unparseable:
            // Nothing in memory yet; the last settings saved by an earlier
            // version are the closest thing to "current".
            values = ConfigValues(migratingFrom: defaults)
            problems = [Self.unparseableMessage]
        case .parsed(let raw):
            values = ConfigValues(json: raw, problems: &problems)
        }

        isEnabled = values.isEnabled
        scrollSensitivity = values.scrollSensitivity
        zoomSensitivity = values.zoomSensitivity
        naturalScrollDirection = values.naturalScrollDirection
        momentumScrollingEnabled = values.momentumScrollingEnabled
        momentumStrength = values.momentumStrength
        gestureDistance = values.gestureDistance
        threeDSensitivity = values.threeDSensitivity
        threeDDefaultProfile = values.threeDDefaultProfile
        threeDAppProfiles = values.threeDAppProfiles
        zoomMethod = values.zoomMethod
        scrollTriggerKeyCode = values.scrollTriggerKeyCode
        zoomTriggerKeyCode = values.zoomTriggerKeyCode
        gestureTriggerKeyCode = values.gestureTriggerKeyCode
        threeDTriggerKeyCodes = values.threeDTriggerKeyCodes
        autoMouseEnabled = values.autoMouseEnabled
        autoMouseDevice = values.autoMouseDevice
        autoMouseTimeout = values.autoMouseTimeout
        autoMouseKeyCodes = values.autoMouseKeyCodes
        autoMouseHoldKeyCodes = values.autoMouseHoldKeyCodes

        setConfigProblems(problems)
        if needsWrite { saveNow() }
        configFile.startWatching { [weak self] in self?.reloadConfig() }
    }

    // MARK: - Config file

    private var currentValues: ConfigValues {
        var values = ConfigValues()
        values.isEnabled = isEnabled
        values.scrollSensitivity = scrollSensitivity
        values.zoomSensitivity = zoomSensitivity
        values.naturalScrollDirection = naturalScrollDirection
        values.momentumScrollingEnabled = momentumScrollingEnabled
        values.momentumStrength = momentumStrength
        values.gestureDistance = gestureDistance
        values.threeDSensitivity = threeDSensitivity
        values.threeDDefaultProfile = threeDDefaultProfile
        values.threeDAppProfiles = threeDAppProfiles
        values.zoomMethod = zoomMethod
        values.scrollTriggerKeyCode = scrollTriggerKeyCode
        values.zoomTriggerKeyCode = zoomTriggerKeyCode
        values.gestureTriggerKeyCode = gestureTriggerKeyCode
        values.threeDTriggerKeyCodes = threeDTriggerKeyCodes
        values.autoMouseEnabled = autoMouseEnabled
        values.autoMouseDevice = autoMouseDevice
        values.autoMouseTimeout = autoMouseTimeout
        values.autoMouseKeyCodes = autoMouseKeyCodes
        values.autoMouseHoldKeyCodes = autoMouseHoldKeyCodes
        return values
    }

    /// Assigns only what changed, so subscribers to one setting are not woken
    /// by an edit to another.
    private func apply(_ values: ConfigValues) {
        isApplyingConfig = true
        defer { isApplyingConfig = false }
        if isEnabled != values.isEnabled { isEnabled = values.isEnabled }
        if scrollSensitivity != values.scrollSensitivity { scrollSensitivity = values.scrollSensitivity }
        if zoomSensitivity != values.zoomSensitivity { zoomSensitivity = values.zoomSensitivity }
        if naturalScrollDirection != values.naturalScrollDirection {
            naturalScrollDirection = values.naturalScrollDirection
        }
        if momentumScrollingEnabled != values.momentumScrollingEnabled {
            momentumScrollingEnabled = values.momentumScrollingEnabled
        }
        if momentumStrength != values.momentumStrength { momentumStrength = values.momentumStrength }
        if gestureDistance != values.gestureDistance { gestureDistance = values.gestureDistance }
        if threeDSensitivity != values.threeDSensitivity { threeDSensitivity = values.threeDSensitivity }
        if threeDDefaultProfile != values.threeDDefaultProfile { threeDDefaultProfile = values.threeDDefaultProfile }
        if threeDAppProfiles != values.threeDAppProfiles { threeDAppProfiles = values.threeDAppProfiles }
        if zoomMethod != values.zoomMethod { zoomMethod = values.zoomMethod }
        if scrollTriggerKeyCode != values.scrollTriggerKeyCode { scrollTriggerKeyCode = values.scrollTriggerKeyCode }
        if zoomTriggerKeyCode != values.zoomTriggerKeyCode { zoomTriggerKeyCode = values.zoomTriggerKeyCode }
        if gestureTriggerKeyCode != values.gestureTriggerKeyCode { gestureTriggerKeyCode = values.gestureTriggerKeyCode }
        if threeDTriggerKeyCodes != values.threeDTriggerKeyCodes { threeDTriggerKeyCodes = values.threeDTriggerKeyCodes }
        if autoMouseEnabled != values.autoMouseEnabled { autoMouseEnabled = values.autoMouseEnabled }
        if autoMouseDevice != values.autoMouseDevice { autoMouseDevice = values.autoMouseDevice }
        if autoMouseTimeout != values.autoMouseTimeout { autoMouseTimeout = values.autoMouseTimeout }
        if autoMouseKeyCodes != values.autoMouseKeyCodes { autoMouseKeyCodes = values.autoMouseKeyCodes }
        if autoMouseHoldKeyCodes != values.autoMouseHoldKeyCodes { autoMouseHoldKeyCodes = values.autoMouseHoldKeyCodes }
    }

    /// Called when the file changed on disk. A file that stops parsing
    /// mid-edit leaves the current settings alone, and a deleted file is
    /// recreated by the next change made in the app.
    private func reloadConfig() {
        switch configFile.read() {
        case .missing:
            return
        case .unparseable:
            setConfigProblems([Self.unparseableMessage])
        case .parsed(let raw):
            var problems: [String] = []
            apply(ConfigValues(json: raw, problems: &problems))
            setConfigProblems(problems)
        }
    }

    /// Writes once after a burst of changes (a dragged slider sets its value
    /// many times a second) rather than on every change.
    private func scheduleSave() {
        guard !isApplyingConfig, !isSaveScheduled else { return }
        isSaveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self?.saveNow()
        }
    }

    private func saveNow() {
        isSaveScheduled = false
        // A successful write replaces every field the app owns with a valid
        // value, so problems from the last read no longer apply.
        setConfigProblems(configFile.write(currentValues.json()).map { [$0] } ?? [])
    }

    private func setConfigProblems(_ problems: [String]) {
        let message = problems.isEmpty ? nil : problems.joined(separator: "\n")
        guard message != configErrorMessage else { return }
        configErrorMessage = message
        for problem in problems { NSLog("BallGesture: %@ (%@)", problem, Self.configFileURL.path) }
    }

    // MARK: - Lookups

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

        // The config file stores keys by name, so a key without one could not be saved.
        guard KeyCodeNaming.configName(for: keyCode) != nil else {
            captureErrorMessage = "That key can't be assigned. Choose a different key."
            captureTarget = nil
            return true
        }

        let assignedKeys: [(KeyCaptureTarget, Int64, String)] = [
            (.scrollTrigger, scrollTriggerKeyCode, "Scroll Mode"),
            (.zoomTrigger, zoomTriggerKeyCode, "Zoom Mode"),
            (.gestureTrigger, gestureTriggerKeyCode, "Gesture Mode")
        ] + ThreeDAction.allCases.map {
            (.threeDTrigger($0), threeDTriggerKeyCode(for: $0), "CAD \($0.displayName)")
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
