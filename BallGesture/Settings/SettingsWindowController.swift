//
//  SettingsWindowController.swift
//  BallGesture
//
//  The app's one window: the settings, opened from the menu panel, the app menu,
//  a relaunch of the app, or the ballgesture://settings URL.
//

import AppKit
import Combine
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, scroll, zoom, gesture, cad, mouseLayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .scroll: return "Scroll"
        case .zoom: return "Zoom"
        case .gesture: return "Gesture"
        case .cad: return "CAD"
        case .mouseLayer: return "Mouse Layer"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .scroll: return "arrow.up.and.down"
        case .zoom: return "plus.magnifyingglass"
        case .gesture: return "hand.draw"
        case .cad: return "cube"
        case .mouseLayer: return "cursorarrow.click"
        }
    }

    /// The name used in ballgesture://settings/<name>.
    init?(urlName: String) {
        let name = urlName.lowercased().replacingOccurrences(of: "-", with: "")
        guard let page = Self.allCases.first(where: { $0.rawValue.lowercased() == name }) else { return nil }
        self = page
    }
}

/// State of the settings window that outlives any one view: the page shown, the open dropdown, and
/// which key recorder was used last, so a rejected key's message appears under the right row.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var page: SettingsPage = .general
    @Published var dropdown: DropdownRequest?
    @Published var lastCaptureTarget: KeyCaptureTarget?
    /// A view on the page to bring into sight, by its id; cleared once scrolled to.
    @Published var scrollTarget: String?

    func select(_ page: SettingsPage, animated: Bool) {
        guard page != self.page else { return }
        AppSettings.shared.cancelCapture()
        dropdown = nil
        if animated {
            withAnimation(Motion.selection(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
                self.page = page
            }
        } else {
            self.page = page
        }
    }

    func move(by offset: Int) {
        let pages = SettingsPage.allCases
        guard let index = pages.firstIndex(of: page) else { return }
        let next = min(max(index + offset, 0), pages.count - 1)
        select(pages[next], animated: true)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    let model = SettingsModel()
    private var window: NSWindow?
    private var keyMonitor: Any?
    /// The app that was in front before the window opened, given focus back when it closes.
    private var previousApp: NSRunningApplication?

    func show(page: SettingsPage? = nil) {
        if let page { model.select(page, animated: window?.isVisible == true) }

        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        let window = self.window ?? makeWindow()
        self.window = window
        // A regular app while the window is open, so it has the app menu (⌘W, ⌘Q), shows in the
        // Dock and the app switcher, and window managers treat it like any other window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.title = "BallGesture Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        // The ground is always dark, so system controls take their dark-ground colours.
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 640, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 720, height: 560))
        if !window.setFrameUsingName("Settings") {
            window.center()
        }
        window.setFrameAutosaveName("Settings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.cancelCapture()
        model.dropdown = nil
        removeKeyMonitor()
        NSApp.setActivationPolicy(.accessory)
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        model.dropdown = nil
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if self.model.dropdown != nil {
                if event.keyCode == 53 { // Esc
                    self.model.dropdown = nil
                    return nil
                }
                return event
            }
            guard modifiers.isEmpty, AppSettings.shared.captureTarget == nil else { return event }
            switch event.keyCode {
            case 126: // Up arrow
                self.model.move(by: -1)
                return nil
            case 125: // Down arrow
                self.model.move(by: 1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
