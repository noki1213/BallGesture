//
//  SteadyWindow.swift
//  BallGesture
//
//  Liquid Glass draws dark in the key window and pale in any other, so glass inside a titled window
//  would change with focus. This window always reports the key and main appearance, which keeps the
//  glass dark. The close, minimize and zoom buttons ask separately and are answered from the real
//  state, so they still dim when the window is in the background.
//

import AppKit

final class SteadyWindow: NSWindow {
    private static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private var observers: [NSObjectProtocol] = []

    @objc func hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }

    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func hasActiveAppearance(forStandardWindowButton button: Int) -> Bool {
        NSApp.isActive && (isKeyWindow || isMainWindow)
    }

    /// Starts redrawing the buttons whenever the focus state changes; call once after creating the window.
    func observeFocus() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let redraw: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshButtons() }
        }
        let windowNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
        ]
        for name in windowNames {
            observers.append(center.addObserver(forName: name, object: self, queue: .main, using: redraw))
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: redraw))
        }
        DispatchQueue.main.async { [weak self] in self?.refreshButtons() }
    }

    // The buttons keep the look they last asked for, so they are told to ask again.
    private func refreshButtons() {
        let update = NSSelectorFromString("update")
        for type in Self.buttonTypes {
            guard let button = standardWindowButton(type) else { continue }
            if button.responds(to: update) { button.perform(update) }
            button.needsDisplay = true
        }
    }
}
