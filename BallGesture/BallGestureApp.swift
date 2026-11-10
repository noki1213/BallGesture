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
/// A plain NSStatusItem with an NSImage set directly on the button reports
/// its bounds up front and has no such problem in Ice.
///
/// `NSStatusItem.variableLength` is used rather than `squareLength`, since
/// that is the configuration known to coexist with Ice.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.noki.BallGesture",
        category: "AppDelegate"
    )

    private var statusItem: NSStatusItem?
    private let menuPanel = MenuPanelController()

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

    /// Opening the app again while it runs, from Finder or Spotlight, opens its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in SettingsWindowController.shared.show() }
        return false
    }

    /// ballgesture://settings opens the settings window; ballgesture://settings/<page> opens a page
    /// (general, scroll, zoom, gesture, cad, mouse-layer).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "ballgesture" {
            guard url.host?.lowercased() == "settings" else {
                Self.logger.notice("Ignoring unknown URL \(url.absoluteString, privacy: .public).")
                continue
            }
            let page = url.pathComponents.dropFirst().first.flatMap(SettingsPage.init(urlName:))
            Task { @MainActor in
                self.menuPanel.hide()
                SettingsWindowController.shared.show(page: page)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GestureEngine.shared.endActiveModesIfNeeded()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "BallGesture")
            button.action = #selector(togglePanel)
            button.target = self
        }
        statusItem = item

        menuPanel.onVisibilityChanged = { [weak self] visible in
            self?.statusItem?.button?.highlight(visible)
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button, let window = button.window else { return }

        if menuPanel.isVisible {
            menuPanel.hide()
        } else {
            menuPanel.show(below: window.convertToScreen(button.convert(button.bounds, to: nil)))
        }
    }
}

@main
struct BallGestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The status item, its panel and the settings window are AppKit, set
        // up by AppDelegate. An empty `Settings` scene gives the SwiftUI App
        // lifecycle a scene without opening a window of its own, and its
        // menu item is pointed at the settings window instead.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
