//
//  KeyCodeNaming.swift
//  BallGesture
//
//  Maps a hardware virtual keycode (as seen in CGEvent's kCGKeyboardEventKeycode
//  field) to a human-readable name for the settings window, and to the lowercase
//  name used for it in config.json.
//

import Carbon.HIToolbox
import Foundation

enum KeyCodeNaming {
    private struct Entry {
        let keyCode: Int64
        let configName: String
        let displayName: String

        init(_ keyCode: Int, _ configName: String, _ displayName: String) {
            self.keyCode = Int64(keyCode)
            self.configName = configName
            self.displayName = displayName
        }
    }

    /// Uses the real Carbon HIToolbox `kVK_*` constants (not hand-typed numbers)
    /// so the mapping is guaranteed correct. Only keys listed here can be
    /// assigned, since the config file stores keys by name.
    private static let entries: [Entry] = [
        Entry(kVK_F1, "f1", "F1"), Entry(kVK_F2, "f2", "F2"), Entry(kVK_F3, "f3", "F3"),
        Entry(kVK_F4, "f4", "F4"), Entry(kVK_F5, "f5", "F5"), Entry(kVK_F6, "f6", "F6"),
        Entry(kVK_F7, "f7", "F7"), Entry(kVK_F8, "f8", "F8"), Entry(kVK_F9, "f9", "F9"),
        Entry(kVK_F10, "f10", "F10"), Entry(kVK_F11, "f11", "F11"), Entry(kVK_F12, "f12", "F12"),
        Entry(kVK_F13, "f13", "F13"), Entry(kVK_F14, "f14", "F14"), Entry(kVK_F15, "f15", "F15"),
        Entry(kVK_F16, "f16", "F16"), Entry(kVK_F17, "f17", "F17"), Entry(kVK_F18, "f18", "F18"),
        Entry(kVK_F19, "f19", "F19"), Entry(kVK_F20, "f20", "F20"),

        Entry(kVK_ANSI_A, "a", "A"), Entry(kVK_ANSI_B, "b", "B"), Entry(kVK_ANSI_C, "c", "C"),
        Entry(kVK_ANSI_D, "d", "D"), Entry(kVK_ANSI_E, "e", "E"), Entry(kVK_ANSI_F, "f", "F"),
        Entry(kVK_ANSI_G, "g", "G"), Entry(kVK_ANSI_H, "h", "H"), Entry(kVK_ANSI_I, "i", "I"),
        Entry(kVK_ANSI_J, "j", "J"), Entry(kVK_ANSI_K, "k", "K"), Entry(kVK_ANSI_L, "l", "L"),
        Entry(kVK_ANSI_M, "m", "M"), Entry(kVK_ANSI_N, "n", "N"), Entry(kVK_ANSI_O, "o", "O"),
        Entry(kVK_ANSI_P, "p", "P"), Entry(kVK_ANSI_Q, "q", "Q"), Entry(kVK_ANSI_R, "r", "R"),
        Entry(kVK_ANSI_S, "s", "S"), Entry(kVK_ANSI_T, "t", "T"), Entry(kVK_ANSI_U, "u", "U"),
        Entry(kVK_ANSI_V, "v", "V"), Entry(kVK_ANSI_W, "w", "W"), Entry(kVK_ANSI_X, "x", "X"),
        Entry(kVK_ANSI_Y, "y", "Y"), Entry(kVK_ANSI_Z, "z", "Z"),

        Entry(kVK_ANSI_0, "0", "0"), Entry(kVK_ANSI_1, "1", "1"), Entry(kVK_ANSI_2, "2", "2"),
        Entry(kVK_ANSI_3, "3", "3"), Entry(kVK_ANSI_4, "4", "4"), Entry(kVK_ANSI_5, "5", "5"),
        Entry(kVK_ANSI_6, "6", "6"), Entry(kVK_ANSI_7, "7", "7"), Entry(kVK_ANSI_8, "8", "8"),
        Entry(kVK_ANSI_9, "9", "9"),

        Entry(kVK_ANSI_Minus, "minus", "-"), Entry(kVK_ANSI_Equal, "equal", "="),
        Entry(kVK_ANSI_LeftBracket, "left_bracket", "["), Entry(kVK_ANSI_RightBracket, "right_bracket", "]"),
        Entry(kVK_ANSI_Backslash, "backslash", "\\"), Entry(kVK_ANSI_Semicolon, "semicolon", ";"),
        Entry(kVK_ANSI_Quote, "quote", "'"), Entry(kVK_ANSI_Comma, "comma", ","),
        Entry(kVK_ANSI_Period, "period", "."), Entry(kVK_ANSI_Slash, "slash", "/"),
        Entry(kVK_ANSI_Grave, "grave", "`"),

        Entry(kVK_Space, "space", "Space"), Entry(kVK_Tab, "tab", "Tab"),
        Entry(kVK_Return, "return", "Return"), Entry(kVK_Escape, "escape", "Escape"),
        Entry(kVK_Delete, "delete", "Delete"), Entry(kVK_ForwardDelete, "forward_delete", "Forward Delete"),
        Entry(kVK_LeftArrow, "left", "Left Arrow"), Entry(kVK_RightArrow, "right", "Right Arrow"),
        Entry(kVK_UpArrow, "up", "Up Arrow"), Entry(kVK_DownArrow, "down", "Down Arrow"),
        Entry(kVK_Home, "home", "Home"), Entry(kVK_End, "end", "End"),
        Entry(kVK_PageUp, "page_up", "Page Up"), Entry(kVK_PageDown, "page_down", "Page Down"),

        Entry(kVK_Control, "left_ctrl", "Left Control"), Entry(kVK_RightControl, "right_ctrl", "Right Control"),
        Entry(kVK_Option, "left_option", "Left Option"), Entry(kVK_RightOption, "right_option", "Right Option"),
        Entry(kVK_Command, "left_cmd", "Left Command"), Entry(kVK_RightCommand, "right_cmd", "Right Command"),
        Entry(kVK_Shift, "left_shift", "Left Shift"), Entry(kVK_RightShift, "right_shift", "Right Shift"),
        Entry(kVK_CapsLock, "caps_lock", "Caps Lock"), Entry(kVK_Function, "fn", "Fn")
    ]

    private static let byKeyCode: [Int64: Entry] = Dictionary(
        entries.map { ($0.keyCode, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let byConfigName: [String: Entry] = Dictionary(
        entries.map { ($0.configName, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func displayName(for keyCode: Int64) -> String {
        byKeyCode[keyCode]?.displayName ?? "Key \(keyCode)"
    }

    /// The name config.json uses for `keyCode`, or nil for a key that has none
    /// and therefore cannot be assigned.
    static func configName(for keyCode: Int64) -> String? {
        byKeyCode[keyCode]?.configName
    }

    /// The keycode for a name from config.json. Case is ignored so "F15" and
    /// "f15" written by hand both work.
    static func keyCode(forConfigName name: String) -> Int64? {
        byConfigName[name.trimmingCharacters(in: .whitespaces).lowercased()]?.keyCode
    }
}
