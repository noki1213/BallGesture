//
//  KeyCodeNaming.swift
//  BallGesture
//
//  Maps a hardware virtual keycode (as seen in CGEvent's kCGKeyboardEventKeycode
//  field) to a human-readable name for display in the menu bar UI.
//

import Carbon.HIToolbox
import Foundation

enum KeyCodeNaming {
    /// Uses the real Carbon HIToolbox `kVK_*` constants (not hand-typed numbers)
    /// so the mapping is guaranteed correct.
    private static let names: [Int64: String] = [
        Int64(kVK_F1): "F1", Int64(kVK_F2): "F2", Int64(kVK_F3): "F3", Int64(kVK_F4): "F4",
        Int64(kVK_F5): "F5", Int64(kVK_F6): "F6", Int64(kVK_F7): "F7", Int64(kVK_F8): "F8",
        Int64(kVK_F9): "F9", Int64(kVK_F10): "F10", Int64(kVK_F11): "F11", Int64(kVK_F12): "F12",
        Int64(kVK_F13): "F13", Int64(kVK_F14): "F14", Int64(kVK_F15): "F15", Int64(kVK_F16): "F16",
        Int64(kVK_F17): "F17", Int64(kVK_F18): "F18", Int64(kVK_F19): "F19", Int64(kVK_F20): "F20",
        Int64(kVK_ANSI_A): "A", Int64(kVK_ANSI_B): "B", Int64(kVK_ANSI_C): "C", Int64(kVK_ANSI_D): "D",
        Int64(kVK_ANSI_E): "E", Int64(kVK_ANSI_F): "F", Int64(kVK_ANSI_G): "G", Int64(kVK_ANSI_H): "H",
        Int64(kVK_ANSI_I): "I", Int64(kVK_ANSI_J): "J", Int64(kVK_ANSI_K): "K", Int64(kVK_ANSI_L): "L",
        Int64(kVK_ANSI_M): "M", Int64(kVK_ANSI_N): "N", Int64(kVK_ANSI_O): "O", Int64(kVK_ANSI_P): "P",
        Int64(kVK_ANSI_Q): "Q", Int64(kVK_ANSI_R): "R", Int64(kVK_ANSI_S): "S", Int64(kVK_ANSI_T): "T",
        Int64(kVK_ANSI_U): "U", Int64(kVK_ANSI_V): "V", Int64(kVK_ANSI_W): "W", Int64(kVK_ANSI_X): "X",
        Int64(kVK_ANSI_Y): "Y", Int64(kVK_ANSI_Z): "Z",
        Int64(kVK_ANSI_0): "0", Int64(kVK_ANSI_1): "1", Int64(kVK_ANSI_2): "2", Int64(kVK_ANSI_3): "3",
        Int64(kVK_ANSI_4): "4", Int64(kVK_ANSI_5): "5", Int64(kVK_ANSI_6): "6", Int64(kVK_ANSI_7): "7",
        Int64(kVK_ANSI_8): "8", Int64(kVK_ANSI_9): "9",
        Int64(kVK_Space): "Space", Int64(kVK_Tab): "Tab", Int64(kVK_Return): "Return",
        Int64(kVK_Escape): "Escape", Int64(kVK_Delete): "Delete", Int64(kVK_ForwardDelete): "Forward Delete",
        Int64(kVK_LeftArrow): "Left Arrow", Int64(kVK_RightArrow): "Right Arrow",
        Int64(kVK_UpArrow): "Up Arrow", Int64(kVK_DownArrow): "Down Arrow",
        Int64(kVK_Home): "Home", Int64(kVK_End): "End", Int64(kVK_PageUp): "Page Up", Int64(kVK_PageDown): "Page Down"
    ]

    static func displayName(for keyCode: Int64) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
