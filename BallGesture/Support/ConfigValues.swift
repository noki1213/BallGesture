//
//  ConfigValues.swift
//  BallGesture
//
//  Every persisted setting in one value, with its mapping to and from
//  config.json and the one-time import of settings saved in UserDefaults.
//

import Carbon.HIToolbox
import Foundation

struct ConfigValues: Equatable {
    static let defaultScrollTriggerKeyCode = Int64(kVK_F15)
    static let defaultZoomTriggerKeyCode = Int64(kVK_F16)
    static let defaultGestureTriggerKeyCode = Int64(kVK_F17)
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

    var isEnabled = true

    var scrollTriggerKeyCode = defaultScrollTriggerKeyCode
    var naturalScrollDirection = true
    var scrollSensitivity = 1.0
    var momentumScrollingEnabled = true
    var momentumStrength = 0.5

    var zoomTriggerKeyCode = defaultZoomTriggerKeyCode
    var zoomMethod = ZoomMethod.pinch
    var zoomSensitivity = 1.0

    var gestureTriggerKeyCode = defaultGestureTriggerKeyCode
    var gestureDistance = 50.0

    var threeDTriggerKeyCodes = Dictionary(
        uniqueKeysWithValues: ThreeDAction.allCases.map { ($0, defaultThreeDTriggerKeyCode($0)) }
    )
    var threeDSensitivity = 1.0
    var threeDDefaultProfile = ThreeDProfile.standard
    var threeDAppProfiles: [ThreeDAppProfile] = []

    var autoMouseEnabled = false
    var autoMouseDevice: PointingDeviceID?
    var autoMouseTimeout = 0.7
    var autoMouseKeyCodes = Dictionary(
        uniqueKeysWithValues: AutoMouseButton.allCases.map { ($0, defaultAutoMouseKeyCode($0)) }
    )
    var autoMouseHoldKeyCodes: [AutoMouseButton: Int64] = [:]

    init() {}

    // MARK: - Writing

    /// The file's contents for these values. `NSNull` marks a key to remove,
    /// so an unset device disappears from the file instead of lingering.
    func json() -> [String: Any] {
        func keyName(_ keyCode: Int64?) -> String {
            keyCode.flatMap(KeyCodeNaming.configName(for:)) ?? ""
        }
        func binding(_ binding: ThreeDBinding) -> [String: Any] {
            ["output": binding.output.rawValue, "reversed": binding.reversed]
        }
        func profile(_ profile: ThreeDProfile) -> [String: Any] {
            ["pan": binding(profile.pan), "zoom": binding(profile.zoom), "rotate": binding(profile.rotate)]
        }
        // Written through Swift's shortest round-trip text so 0.7 appears
        // as 0.7 rather than 0.69999999999999996.
        func number(_ value: Double) -> NSDecimalNumber {
            NSDecimalNumber(string: String(value))
        }

        var device: Any = NSNull()
        if let autoMouseDevice,
           let data = try? JSONEncoder().encode(autoMouseDevice),
           let object = try? JSONSerialization.jsonObject(with: data) {
            device = object
        }

        return [
            "enabled": isEnabled,
            "scroll": [
                "trigger": keyName(scrollTriggerKeyCode),
                "naturalDirection": naturalScrollDirection,
                "sensitivity": number(scrollSensitivity),
                "momentum": momentumScrollingEnabled,
                "momentumStrength": number(momentumStrength)
            ] as [String: Any],
            "zoom": [
                "trigger": keyName(zoomTriggerKeyCode),
                "method": zoomMethod.rawValue,
                "sensitivity": number(zoomSensitivity)
            ] as [String: Any],
            "gesture": [
                "trigger": keyName(gestureTriggerKeyCode),
                "distance": number(gestureDistance)
            ] as [String: Any],
            "cad": [
                "keys": Dictionary(uniqueKeysWithValues: ThreeDAction.allCases.map {
                    ($0.rawValue, keyName(threeDTriggerKeyCodes[$0]))
                }),
                "sensitivity": number(threeDSensitivity),
                "default": profile(threeDDefaultProfile),
                "apps": threeDAppProfiles.map { app -> [String: Any] in
                    var entry = profile(app.profile)
                    entry["bundleID"] = app.bundleID
                    entry["reverseShiftTrackpadScroll"] = app.reversesShiftTrackpadScroll
                    return entry
                }
            ] as [String: Any],
            "mouseLayer": [
                "enabled": autoMouseEnabled,
                "device": device,
                "stayOnSeconds": number(autoMouseTimeout),
                "keys": Dictionary(uniqueKeysWithValues: AutoMouseButton.allCases.map {
                    ($0.rawValue, keyName(autoMouseKeyCodes[$0]))
                }),
                "holdKeys": Dictionary(uniqueKeysWithValues: AutoMouseButton.allCases.map {
                    ($0.rawValue, keyName(autoMouseHoldKeyCodes[$0]))
                })
            ] as [String: Any]
        ]
    }

    // MARK: - Reading

    /// Values from the file, field by field: a missing field takes its default
    /// silently, an invalid one takes its default and adds a problem, and
    /// every other field still applies.
    init(json raw: [String: Any], problems: inout [String]) {
        var reader = FieldReader()
        defer { problems = reader.problems }

        isEnabled = reader.bool(raw, "enabled", path: "enabled", default: isEnabled)

        let scroll = reader.object(raw, "scroll", path: "scroll")
        scrollTriggerKeyCode = reader.key(scroll, "trigger", path: "scroll.trigger", default: scrollTriggerKeyCode)
        naturalScrollDirection = reader.bool(
            scroll, "naturalDirection", path: "scroll.naturalDirection", default: naturalScrollDirection
        )
        scrollSensitivity = reader.positive(scroll, "sensitivity", path: "scroll.sensitivity", default: scrollSensitivity)
        momentumScrollingEnabled = reader.bool(
            scroll, "momentum", path: "scroll.momentum", default: momentumScrollingEnabled
        )
        momentumStrength = reader.number(
            scroll, "momentumStrength", path: "scroll.momentumStrength", default: momentumStrength,
            requirement: "a number from 0 to 1"
        ) { (0...1).contains($0) }

        let zoom = reader.object(raw, "zoom", path: "zoom")
        zoomTriggerKeyCode = reader.key(zoom, "trigger", path: "zoom.trigger", default: zoomTriggerKeyCode)
        zoomMethod = reader.choice(zoom, "method", path: "zoom.method", default: zoomMethod)
        zoomSensitivity = reader.positive(zoom, "sensitivity", path: "zoom.sensitivity", default: zoomSensitivity)

        let gesture = reader.object(raw, "gesture", path: "gesture")
        gestureTriggerKeyCode = reader.key(gesture, "trigger", path: "gesture.trigger", default: gestureTriggerKeyCode)
        gestureDistance = reader.positive(gesture, "distance", path: "gesture.distance", default: gestureDistance)

        let cad = reader.object(raw, "cad", path: "cad")
        let cadKeys = reader.object(cad, "keys", path: "cad.keys")
        for action in ThreeDAction.allCases {
            threeDTriggerKeyCodes[action] = reader.key(
                cadKeys, action.rawValue, path: "cad.keys.\(action.rawValue)",
                default: Self.defaultThreeDTriggerKeyCode(action)
            )
        }
        threeDSensitivity = reader.positive(cad, "sensitivity", path: "cad.sensitivity", default: threeDSensitivity)
        threeDDefaultProfile = reader.profile(
            reader.object(cad, "default", path: "cad.default"), path: "cad.default", default: threeDDefaultProfile
        )
        threeDAppProfiles = reader.apps(cad, path: "cad.apps", baseProfile: threeDDefaultProfile)

        let mouseLayer = reader.object(raw, "mouseLayer", path: "mouseLayer")
        autoMouseEnabled = reader.bool(mouseLayer, "enabled", path: "mouseLayer.enabled", default: autoMouseEnabled)
        autoMouseDevice = reader.device(mouseLayer, "device", path: "mouseLayer.device")
        autoMouseTimeout = reader.number(
            mouseLayer, "stayOnSeconds", path: "mouseLayer.stayOnSeconds", default: autoMouseTimeout,
            requirement: "a number of 0 or more"
        ) { $0 >= 0 }
        let mouseKeys = reader.object(mouseLayer, "keys", path: "mouseLayer.keys")
        let holdKeys = reader.object(mouseLayer, "holdKeys", path: "mouseLayer.holdKeys")
        for button in AutoMouseButton.allCases {
            autoMouseKeyCodes[button] = reader.key(
                mouseKeys, button.rawValue, path: "mouseLayer.keys.\(button.rawValue)",
                default: Self.defaultAutoMouseKeyCode(button)
            )
            autoMouseHoldKeyCodes[button] = reader.optionalKey(
                holdKeys, button.rawValue, path: "mouseLayer.holdKeys.\(button.rawValue)"
            )
        }
    }

    // MARK: - Import from UserDefaults

    private enum LegacyKeys {
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

    /// Settings saved in UserDefaults by earlier versions, used once to fill
    /// a config file that does not exist yet. A saved key with no name in the
    /// file format falls back to its default, since it could not be written.
    init(migratingFrom defaults: UserDefaults) {
        func value<T>(_ key: String, _ type: T.Type) -> T? {
            defaults.object(forKey: key) as? T
        }
        func key(_ legacyKey: String) -> Int64? {
            guard let keyCode = value(legacyKey, Int64.self),
                  KeyCodeNaming.configName(for: keyCode) != nil else { return nil }
            return keyCode
        }
        func decoded<T: Decodable>(_ type: T.Type, _ legacyKey: String) -> T? {
            guard let data = defaults.data(forKey: legacyKey) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }

        isEnabled = value(LegacyKeys.isEnabled, Bool.self) ?? isEnabled
        scrollSensitivity = value(LegacyKeys.scrollSensitivity, Double.self) ?? scrollSensitivity
        zoomSensitivity = value(LegacyKeys.zoomSensitivity, Double.self) ?? zoomSensitivity
        naturalScrollDirection = value(LegacyKeys.naturalScrollDirection, Bool.self) ?? naturalScrollDirection
        momentumScrollingEnabled = value(LegacyKeys.momentumScrollingEnabled, Bool.self) ?? momentumScrollingEnabled
        momentumStrength = value(LegacyKeys.momentumStrength, Double.self) ?? momentumStrength
        gestureDistance = value(LegacyKeys.gestureDistance, Double.self) ?? gestureDistance
        threeDSensitivity = value(LegacyKeys.threeDSensitivity, Double.self) ?? threeDSensitivity
        threeDDefaultProfile = decoded(ThreeDProfile.self, LegacyKeys.threeDDefaultProfile) ?? threeDDefaultProfile
        threeDAppProfiles = decoded([ThreeDAppProfile].self, LegacyKeys.threeDAppProfiles) ?? threeDAppProfiles
        zoomMethod = value(LegacyKeys.zoomMethod, String.self).flatMap(ZoomMethod.init(rawValue:)) ?? zoomMethod
        scrollTriggerKeyCode = key(LegacyKeys.scrollTriggerKeyCode) ?? scrollTriggerKeyCode
        zoomTriggerKeyCode = key(LegacyKeys.zoomTriggerKeyCode) ?? zoomTriggerKeyCode
        gestureTriggerKeyCode = key(LegacyKeys.gestureTriggerKeyCode) ?? gestureTriggerKeyCode
        for action in ThreeDAction.allCases {
            if let keyCode = key(LegacyKeys.threeDTriggerKeyCode(action)) {
                threeDTriggerKeyCodes[action] = keyCode
            }
        }
        autoMouseEnabled = value(LegacyKeys.autoMouseEnabled, Bool.self) ?? autoMouseEnabled
        autoMouseDevice = decoded(PointingDeviceID.self, LegacyKeys.autoMouseDevice)
        autoMouseTimeout = value(LegacyKeys.autoMouseTimeout, Double.self) ?? autoMouseTimeout
        for button in AutoMouseButton.allCases {
            if let keyCode = key(LegacyKeys.autoMouseKeyCode(button)) {
                autoMouseKeyCodes[button] = keyCode
            }
            autoMouseHoldKeyCodes[button] = key(LegacyKeys.autoMouseHoldKeyCode(button))
        }
    }
}

/// Typed access to the parsed JSON that records a short message for every
/// value it has to replace with a default.
private struct FieldReader {
    var problems: [String] = []

    private mutating func report(_ message: String) {
        problems.append("config.json: \(message)")
    }

    /// JSON numbers and booleans both arrive as NSNumber, and NSNumber casts
    /// freely between them, so the boolean ones are told apart explicitly.
    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func describe(_ value: Any) -> String {
        if let string = value as? String { return "\"\(string)\"" }
        if isBoolean(value) { return (value as? Bool) == true ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        return "this value"
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(format: "%.1f", number) : String(number)
    }

    /// The value at `key`; JSON null counts as missing.
    private func field(_ object: [String: Any]?, _ key: String) -> Any? {
        guard let value = object?[key], !(value is NSNull) else { return nil }
        return value
    }

    mutating func object(_ parent: [String: Any]?, _ key: String, path: String) -> [String: Any]? {
        guard let value = field(parent, key) else { return nil }
        guard let object = value as? [String: Any] else {
            report("\(path) must be an object; using the defaults.")
            return nil
        }
        return object
    }

    mutating func bool(_ object: [String: Any]?, _ key: String, path: String, default fallback: Bool) -> Bool {
        guard let value = field(object, key) else { return fallback }
        guard Self.isBoolean(value), let bool = value as? Bool else {
            report("\(path) must be true or false; using \(fallback).")
            return fallback
        }
        return bool
    }

    mutating func number(
        _ object: [String: Any]?, _ key: String, path: String, default fallback: Double,
        requirement: String, isValid: (Double) -> Bool
    ) -> Double {
        guard let value = field(object, key) else { return fallback }
        guard !Self.isBoolean(value), let number = (value as? NSNumber)?.doubleValue,
              number.isFinite, isValid(number) else {
            report("\(path) must be \(requirement); using \(Self.format(fallback)).")
            return fallback
        }
        return number
    }

    mutating func positive(_ object: [String: Any]?, _ key: String, path: String, default fallback: Double) -> Double {
        number(object, key, path: path, default: fallback, requirement: "a number above 0") { $0 > 0 }
    }

    mutating func choice<T: RawRepresentable & CaseIterable>(
        _ object: [String: Any]?, _ key: String, path: String, default fallback: T
    ) -> T where T.RawValue == String {
        guard let value = field(object, key) else { return fallback }
        guard let string = value as? String, let choice = T(rawValue: string) else {
            let options = T.allCases.map(\.rawValue).joined(separator: ", ")
            report("\(path) \(Self.describe(value)) must be one of \(options); using \(fallback.rawValue).")
            return fallback
        }
        return choice
    }

    mutating func key(_ object: [String: Any]?, _ key: String, path: String, default fallback: Int64) -> Int64 {
        guard let value = field(object, key) else { return fallback }
        guard let name = value as? String, let keyCode = KeyCodeNaming.keyCode(forConfigName: name) else {
            report("\(path) \(Self.describe(value)) is not a key name; using \(KeyCodeNaming.displayName(for: fallback)).")
            return fallback
        }
        return keyCode
    }

    /// A key that may be left unassigned with "".
    mutating func optionalKey(_ object: [String: Any]?, _ key: String, path: String) -> Int64? {
        guard let value = field(object, key) else { return nil }
        if let name = value as? String, name.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        guard let name = value as? String, let keyCode = KeyCodeNaming.keyCode(forConfigName: name) else {
            report("\(path) \(Self.describe(value)) is not a key name; leaving it unassigned.")
            return nil
        }
        return keyCode
    }

    mutating func device(_ object: [String: Any]?, _ key: String, path: String) -> PointingDeviceID? {
        guard let value = field(object, key) else { return nil }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let device = try? JSONDecoder().decode(PointingDeviceID.self, from: data) else {
            report("\(path) must be an object with vendorID, productID and product; using any pointer.")
            return nil
        }
        return device
    }

    private mutating func binding(_ object: [String: Any]?, path: String, default fallback: ThreeDBinding) -> ThreeDBinding {
        guard let object else { return fallback }
        return ThreeDBinding(
            output: choice(object, "output", path: "\(path).output", default: fallback.output),
            reversed: bool(object, "reversed", path: "\(path).reversed", default: fallback.reversed)
        )
    }

    mutating func profile(_ object: [String: Any]?, path: String, default fallback: ThreeDProfile) -> ThreeDProfile {
        var profile = fallback
        for action in ThreeDAction.allCases {
            profile[action] = binding(
                self.object(object, action.rawValue, path: "\(path).\(action.rawValue)"),
                path: "\(path).\(action.rawValue)",
                default: fallback[action]
            )
        }
        return profile
    }

    /// App overrides. An action an entry leaves out follows `baseProfile`,
    /// the same starting point a newly added app gets.
    mutating func apps(_ cad: [String: Any]?, path: String, baseProfile: ThreeDProfile) -> [ThreeDAppProfile] {
        guard let value = field(cad, "apps") else { return [] }
        guard let entries = value as? [Any] else {
            report("\(path) must be a list; using no app overrides.")
            return []
        }
        var apps: [ThreeDAppProfile] = []
        for (index, entry) in entries.enumerated() {
            let entryPath = "\(path)[\(index)]"
            guard let object = entry as? [String: Any] else {
                report("\(entryPath) must be an object; skipping it.")
                continue
            }
            guard let bundleID = object["bundleID"] as? String, !bundleID.isEmpty else {
                report("\(entryPath) has no bundleID; skipping it.")
                continue
            }
            guard !apps.contains(where: { $0.bundleID == bundleID }) else {
                report("\(entryPath) repeats \(bundleID); skipping it.")
                continue
            }
            apps.append(ThreeDAppProfile(
                bundleID: bundleID,
                profile: profile(object, path: entryPath, default: baseProfile),
                reversesShiftTrackpadScroll: bool(
                    object, "reverseShiftTrackpadScroll", path: "\(entryPath).reverseShiftTrackpadScroll", default: false
                )
            ))
        }
        return apps
    }
}
