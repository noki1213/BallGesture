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
    private static func bare(_ keyCode: Int) -> [KeyBinding] {
        [KeyBinding(keyCode: Int64(keyCode))]
    }
    static let defaultScrollTriggers = bare(kVK_F15)
    static let defaultZoomTriggers = bare(kVK_F16)
    static let defaultGestureTriggers = bare(kVK_F17)
    static func defaultThreeDTriggers(_ action: ThreeDAction) -> [KeyBinding] {
        switch action {
        case .pan: return bare(kVK_F18)
        case .zoom: return bare(kVK_F19)
        case .rotate: return bare(kVK_F20)
        }
    }
    static func defaultAutoMouseKeys(_ button: AutoMouseButton) -> [KeyBinding] {
        switch button {
        case .left: return bare(kVK_ANSI_J)
        case .right: return bare(kVK_ANSI_K)
        case .middle: return bare(kVK_ANSI_L)
        }
    }

    var isEnabled = true

    var scrollTriggers = defaultScrollTriggers
    var naturalScrollDirection = true
    var scrollSensitivity = 1.0
    var momentumScrollingEnabled = true
    var momentumStrength = 0.5

    var zoomTriggers = defaultZoomTriggers
    var zoomMethod = ZoomMethod.pinch
    var zoomSensitivity = 1.0

    var gestureTriggers = defaultGestureTriggers
    var gestureDistance = 50.0

    var threeDTriggers = Dictionary(
        uniqueKeysWithValues: ThreeDAction.allCases.map { ($0, defaultThreeDTriggers($0)) }
    )
    var threeDSensitivity = 1.0
    var threeDDefaultProfile = ThreeDProfile.standard
    var threeDAppProfiles: [ThreeDAppProfile] = []

    var autoMouseEnabled = false
    var autoMouseDevice: PointingDeviceID?
    var autoMouseTimeout = 0.7
    var autoMouseKeys = Dictionary(
        uniqueKeysWithValues: AutoMouseButton.allCases.map { ($0, defaultAutoMouseKeys($0)) }
    )
    var autoMouseHoldKeys: [AutoMouseButton: [KeyBinding]] = [:]

    init() {}

    // MARK: - Writing

    /// The file's contents for these values. `NSNull` marks a key to remove,
    /// so an unset device disappears from the file instead of lingering.
    func json() -> [String: Any] {
        func keyValue(_ bindings: [KeyBinding]?) -> Any {
            KeyBinding.configValue(of: bindings ?? [])
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
                "trigger": keyValue(scrollTriggers),
                "naturalDirection": naturalScrollDirection,
                "sensitivity": number(scrollSensitivity),
                "momentum": momentumScrollingEnabled,
                "momentumStrength": number(momentumStrength)
            ] as [String: Any],
            "zoom": [
                "trigger": keyValue(zoomTriggers),
                "method": zoomMethod.rawValue,
                "sensitivity": number(zoomSensitivity)
            ] as [String: Any],
            "gesture": [
                "trigger": keyValue(gestureTriggers),
                "distance": number(gestureDistance)
            ] as [String: Any],
            "cad": [
                "keys": Dictionary(uniqueKeysWithValues: ThreeDAction.allCases.map { action -> (String, Any) in
                    (action.rawValue, keyValue(threeDTriggers[action]))
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
                    ($0.rawValue, keyValue(autoMouseKeys[$0]))
                }),
                "holdKeys": Dictionary(uniqueKeysWithValues: AutoMouseButton.allCases.map {
                    ($0.rawValue, keyValue(autoMouseHoldKeys[$0]))
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
        scrollTriggers = reader.bindings(
            scroll, "trigger", path: "scroll.trigger", default: scrollTriggers, allowModifiers: true, allowEmpty: true
        )
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
        zoomTriggers = reader.bindings(
            zoom, "trigger", path: "zoom.trigger", default: zoomTriggers, allowModifiers: true, allowEmpty: true
        )
        zoomMethod = reader.choice(zoom, "method", path: "zoom.method", default: zoomMethod)
        zoomSensitivity = reader.positive(zoom, "sensitivity", path: "zoom.sensitivity", default: zoomSensitivity)

        let gesture = reader.object(raw, "gesture", path: "gesture")
        gestureTriggers = reader.bindings(
            gesture, "trigger", path: "gesture.trigger", default: gestureTriggers, allowModifiers: true, allowEmpty: true
        )
        gestureDistance = reader.positive(gesture, "distance", path: "gesture.distance", default: gestureDistance)

        let cad = reader.object(raw, "cad", path: "cad")
        let cadKeys = reader.object(cad, "keys", path: "cad.keys")
        for action in ThreeDAction.allCases {
            threeDTriggers[action] = reader.bindings(
                cadKeys, action.rawValue, path: "cad.keys.\(action.rawValue)",
                default: Self.defaultThreeDTriggers(action), allowModifiers: true, allowEmpty: true
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
            requirement: "a number from 0 to 60"
        ) { (0...60).contains($0) }
        let mouseKeys = reader.object(mouseLayer, "keys", path: "mouseLayer.keys")
        let holdKeys = reader.object(mouseLayer, "holdKeys", path: "mouseLayer.holdKeys")
        for button in AutoMouseButton.allCases {
            autoMouseKeys[button] = reader.bindings(
                mouseKeys, button.rawValue, path: "mouseLayer.keys.\(button.rawValue)",
                default: Self.defaultAutoMouseKeys(button), allowModifiers: false, allowEmpty: true
            )
            autoMouseHoldKeys[button] = reader.bindings(
                holdKeys, button.rawValue, path: "mouseLayer.holdKeys.\(button.rawValue)",
                default: [], allowModifiers: false, allowEmpty: true
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
        func key(_ legacyKey: String) -> [KeyBinding]? {
            guard let keyCode = value(legacyKey, Int64.self),
                  KeyCodeNaming.configName(for: keyCode) != nil else { return nil }
            return [KeyBinding(keyCode: keyCode)]
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
        scrollTriggers = key(LegacyKeys.scrollTriggerKeyCode) ?? scrollTriggers
        zoomTriggers = key(LegacyKeys.zoomTriggerKeyCode) ?? zoomTriggers
        gestureTriggers = key(LegacyKeys.gestureTriggerKeyCode) ?? gestureTriggers
        for action in ThreeDAction.allCases {
            if let keys = key(LegacyKeys.threeDTriggerKeyCode(action)) {
                threeDTriggers[action] = keys
            }
        }
        autoMouseEnabled = value(LegacyKeys.autoMouseEnabled, Bool.self) ?? autoMouseEnabled
        autoMouseDevice = decoded(PointingDeviceID.self, LegacyKeys.autoMouseDevice)
        autoMouseTimeout = value(LegacyKeys.autoMouseTimeout, Double.self) ?? autoMouseTimeout
        for button in AutoMouseButton.allCases {
            if let keys = key(LegacyKeys.autoMouseKeyCode(button)) {
                autoMouseKeys[button] = keys
            }
            autoMouseHoldKeys[button] = key(LegacyKeys.autoMouseHoldKeyCode(button)) ?? []
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
        // The upper bound keeps hand-edited values within what Int32 conversions
        // and JSON number encoding can represent.
        number(object, key, path: path, default: fallback, requirement: "a number above 0 and at most 1000") {
            $0 > 0 && $0 <= 1000
        }
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

    /// A key setting: "" for none, one binding as a string, or several as a
    /// list. A bad list entry is skipped; a bad single value, or a list left
    /// with nothing usable, takes the default.
    mutating func bindings(
        _ object: [String: Any]?, _ key: String, path: String, default fallback: [KeyBinding],
        allowModifiers: Bool, allowEmpty: Bool
    ) -> [KeyBinding] {
        guard let value = field(object, key) else { return fallback }
        let fallbackName = fallback.isEmpty ? "none" : KeyBinding.displayName(of: fallback)

        func parse(_ item: Any, itemPath: String, outcome: String) -> KeyBinding? {
            guard let text = item as? String else {
                report("\(itemPath) \(Self.describe(item)) is not a key name; \(outcome).")
                return nil
            }
            switch KeyBinding.parse(text) {
            case .failure(.notAKey):
                let hint = allowModifiers ? " or a key with modifiers like \"cmd+shift+x\"" : ""
                report("\(itemPath) \(Self.describe(item)) is not a key name\(hint); \(outcome).")
                return nil
            case .failure(.modifierOnModifierKey):
                report("\(itemPath) \(Self.describe(item)) puts a modifier on a modifier key; \(outcome).")
                return nil
            case .success(let binding):
                if !allowModifiers, !binding.modifiers.isEmpty {
                    report("\(itemPath) \(Self.describe(item)) must be a single key without modifiers; \(outcome).")
                    return nil
                }
                return binding
            }
        }

        if let text = value as? String {
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                guard allowEmpty else {
                    report("\(path) \"\" is not a key name; using \(fallbackName).")
                    return fallback
                }
                return []
            }
            guard let binding = parse(value, itemPath: path, outcome: "using \(fallbackName)") else {
                return fallback
            }
            return [binding]
        }

        guard let items = value as? [Any] else {
            report("\(path) must be a key name or a list of key names; using \(fallbackName).")
            return fallback
        }
        var result: [KeyBinding] = []
        for (index, item) in items.enumerated() {
            if let binding = parse(item, itemPath: "\(path)[\(index)]", outcome: "skipping it"), !result.contains(binding) {
                result.append(binding)
            }
        }
        if result.isEmpty, !(items.isEmpty && allowEmpty) {
            report("\(path) has no usable key; using \(fallbackName).")
            return fallback
        }
        return result
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
