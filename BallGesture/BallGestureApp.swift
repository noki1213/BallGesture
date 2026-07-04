//
//  BallGestureApp.swift
//  BallGesture
//
//  Created by noki1213 on 2026/07/04.
//

import AppKit
import SwiftUI
import os

/// Owns the menu bar status item and ensures the mouse cursor is never left
/// detached (see CGAssociateMouseAndMouseCursorPosition in GestureEngine)
/// even if the app is quit while Scroll Mode or Zoom Mode is active.
///
/// NOTE: This intentionally uses a plain AppKit NSStatusItem instead of
/// SwiftUI's `MenuBarExtra`. `MenuBarExtra`'s status item did not report a
/// stable bounds rectangle to the third-party menu bar manager Ice
/// (jordanbaird/Ice), which showed "Missing bounds rectangle for ... Menu Bar
/// Item" when trying to place it. Ice's own issue tracker shows the same
/// "missing/timed-out bounds rectangle" symptom for other menu bar items with
/// non-standard/lazily-laid-out button content (e.g. jordanbaird/Ice#885,
/// #656), which matches SwiftUI MenuBarExtra's dynamically-sized button.
/// Axis, which uses a plain NSStatusItem with an NSImage set
/// directly on the button, has no such problem in Ice.
///
/// `NSStatusItem.variableLength` (matching Axis) is used rather than
/// `squareLength`, since Axis is the proven-working reference for coexisting
/// with Ice.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.noki.BallGesture",
        category: "AppDelegate"
    )

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside INFOPLIST_KEY_LSUIElement: keep the
        // app out of the Dock/App Switcher and make sure it never becomes
        // the active (regular) app just from launching.
        NSApp.setActivationPolicy(.accessory)

        terminateOtherRunningInstances()
        setupStatusItem()
        GestureEngine.shared.start()
    }

    /// If another instance of this same app is already running (same bundle
    /// identifier, different PID), ask it to quit gracefully before this
    /// instance starts its own event tap. Two instances tapping keys/mouse
    /// at once is bad on its own, but the specific failure that motivated
    /// this: if the older instance's Scroll/Zoom Mode ends *after* this new
    /// instance's mode begins, the old instance's `reassociateCursor()` can
    /// re-enable cursor tracking out from under the new instance's mode.
    /// `terminate()` (not `forceTerminate()`) is used so the old instance's
    /// own `applicationWillTerminate` runs and cleans up its own cursor
    /// state first.
    private func terminateOtherRunningInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier

        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != myPID
        }
        guard !others.isEmpty else { return }

        Self.logger.notice("Found \(others.count, privacy: .public) other running instance(s); terminating them.")
        for app in others {
            Self.logger.notice("Terminating duplicate instance pid=\(app.processIdentifier, privacy: .public).")
            app.terminate()
        }

        // Give the old instance(s) a brief window to actually exit (and run
        // their own applicationWillTerminate cleanup) before this instance
        // creates its own event tap, to minimize any overlap.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            let stillRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == bundleID && $0.processIdentifier != myPID
            }
            if !stillRunning { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GestureEngine.shared.endActiveModesIfNeeded()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "BallGesture")
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarContentView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@main
struct BallGestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible scene: the UI is entirely the status item + popover set
        // up by AppDelegate. `Settings` is the standard trick for an
        // otherwise scene-less SwiftUI App lifecycle app.
        Settings {
            EmptyView()
        }
    }
}
