//
//  AccessibilityPermission.swift
//  BallGesture
//
//  CGEventTap requires the Accessibility permission. This wraps the check and
//  the "open System Settings" action.
//

import AppKit
import ApplicationServices

enum AccessibilityPermission {
    /// Checks current status without prompting the system dialog.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks status; if not trusted, also triggers the system's own
    /// "Accessibility access" prompt (which links to System Settings).
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The Accessibility toggle in System Settings can appear ON while the
    /// underlying TCC grant is actually stale — this happens when
    /// install.sh's `rm -rf` + `cp` reinstall replaces the app bundle at the
    /// same path: macOS sometimes keeps showing the old switch state without
    /// the grant actually applying to the new binary on disk. Removing the
    /// entry and re-adding it from System Settings doesn't always clear this
    /// either; `tccutil reset Accessibility <bundle id>` fully resets the TCC
    /// decision for this app so the system prompts fresh. This must be run
    /// by the user in Terminal (there is no API to do it from inside the app).
    static let resetCommand = "tccutil reset Accessibility \(Bundle.main.bundleIdentifier ?? "com.noki.BallGesture")"

    /// Copies `resetCommand` to the clipboard so the user can paste it into
    /// Terminal.
    static func copyResetCommandToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resetCommand, forType: .string)
    }
}
