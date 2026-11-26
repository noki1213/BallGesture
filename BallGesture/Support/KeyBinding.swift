//
//  KeyBinding.swift
//  BallGesture
//
//  A key plus the modifiers that must be held with it, and its text form in
//  config.json: modifiers then the key joined by "+", e.g. "ctrl+shift+f13".
//

import Carbon.HIToolbox
import Foundation

struct KeyBinding: Hashable {
    /// Side-agnostic: the left and right keys count the same.
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        /// In the order they are written and displayed.
        private static let ordered: [(Modifiers, configName: String, symbol: String)] = [
            (.control, "ctrl", "\u{2303}"),
            (.option, "option", "\u{2325}"),
            (.shift, "shift", "\u{21E7}"),
            (.command, "cmd", "\u{2318}")
        ]

        private static let aliases: [String: Modifiers] = [
            "ctrl": .control, "control": .control,
            "option": .option, "opt": .option, "alt": .option,
            "shift": .shift,
            "cmd": .command, "command": .command
        ]

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        init(configName: String) {
            self = Self.aliases[configName] ?? []
        }

        static func isModifierName(_ name: String) -> Bool {
            aliases[name] != nil
        }

        var configNames: [String] { Self.ordered.filter { contains($0.0) }.map(\.configName) }
        var symbols: String { Self.ordered.filter { contains($0.0) }.map(\.symbol).joined() }
        var count: Int { configNames.count }
    }

    let keyCode: Int64
    var modifiers: Modifiers = []

    init(keyCode: Int64, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Why a config string is not a binding, or nil when it parses.
    enum ParseFailure: Error {
        case notAKey
        case modifierOnModifierKey
    }

    /// Parses "f15", "cmd+shift+x". Names are case-insensitive and the
    /// modifiers may be in any order. A modifier key such as `left_cmd`
    /// cannot take a modifier prefix.
    static func parse(_ text: String) -> Result<KeyBinding, ParseFailure> {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let keyName = parts.last, !parts.contains(""),
              let keyCode = KeyCodeNaming.keyCode(forConfigName: keyName) else {
            return .failure(.notAKey)
        }
        var modifiers: Modifiers = []
        for name in parts.dropLast() {
            let modifier = Modifiers(configName: name)
            guard !modifier.isEmpty, modifiers.isDisjoint(with: modifier) else { return .failure(.notAKey) }
            modifiers.formUnion(modifier)
        }
        if !modifiers.isEmpty, KeyCodeNaming.isModifierKey(keyCode) {
            return .failure(.modifierOnModifierKey)
        }
        return .success(KeyBinding(keyCode: keyCode, modifiers: modifiers))
    }

    /// The config string, or nil for a key that has no name.
    var configString: String? {
        guard let name = KeyCodeNaming.configName(for: keyCode) else { return nil }
        return (modifiers.configNames + [name]).joined(separator: "+")
    }

    /// For the settings window: modifier symbols, then the key.
    var displayName: String {
        modifiers.symbols + KeyCodeNaming.displayName(for: keyCode)
    }

    static func displayName(of bindings: [KeyBinding]) -> String {
        bindings.isEmpty ? "None" : bindings.map(\.displayName).joined(separator: ", ")
    }

    /// The value written to config.json: "" for none, a string for one
    /// binding, a list for several.
    static func configValue(of bindings: [KeyBinding]) -> Any {
        let strings = bindings.compactMap(\.configString)
        switch strings.count {
        case 0: return ""
        case 1: return strings[0]
        default: return strings
        }
    }
}
