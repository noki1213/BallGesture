//
//  MenuPanel.swift
//  BallGesture
//
//  The menu bar icon's panel: the settings on a dark Liquid Glass sheet
//  under the status item.
//

import AppKit
import Combine
import SwiftUI

/// State the controller drives and the sheet animates from.
final class MenuPanelState: ObservableObject {
    /// 0 = before appearing, 1 = fully materialized.
    @Published var materializeProgress: CGFloat = 0
    /// Where the status item sits along the panel's width (0 = left edge, 1 = right edge), so the
    /// open animation grows from the clicked icon even when the panel had to shift to stay on-screen.
    @Published var materializeAnchorX: CGFloat = 0.5
}

private struct PanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct MenuPanelView: View {
    @ObservedObject var state: MenuPanelState
    let onSizeChange: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    /// Transparent room around the sheet for its shadow and the materialize blur.
    static let margin: CGFloat = 24

    var body: some View {
        MenuBarContentView()
            .fixedSize(horizontal: false, vertical: true)
            .background(GlassBackground(shape: shape))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            .offset(y: reduceMotion ? 0 : (1 - state.materializeProgress) * -8)
            .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * state.materializeProgress,
                         anchor: UnitPoint(x: state.materializeAnchorX, y: 0))
            .blur(radius: reduceMotion ? 0 : (1 - state.materializeProgress) * 12)
            .opacity(Double(state.materializeProgress))
            .padding(Self.margin)
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
            })
            .onPreferenceChange(PanelSizeKey.self) { onSizeChange($0) }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows the panel under the status item without activating the app, and closes it on Esc, on a
/// click back on the icon, or on a click anywhere else.
final class MenuPanelController {
    let state = MenuPanelState()
    var onVisibilityChanged: ((Bool) -> Void)?

    private let panel: NSPanel
    private var hostingView: NSHostingView<MenuPanelView>!
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    /// The status item's screen rect while shown, so a click back on the icon is left for its own
    /// action to toggle instead of being closed here and immediately reopened.
    private var statusItemFrame: NSRect = .zero
    private var contentSize: CGSize = .zero

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = KeyablePanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // The sheet is always dark, so system text and controls take their dark-ground colours
        // whatever the system appearance is.
        panel.appearance = NSAppearance(named: .darkAqua)

        // One hosting view for the panel's lifetime keeps the chosen tab between openings.
        hostingView = NSHostingView(rootView: MenuPanelView(state: state, onSizeChange: { [weak self] size in
            self?.contentSizeChanged(size)
        }))
        // The hosting view doesn't resize the window itself, which would keep the bottom edge
        // fixed; the controller resizes it with the top edge pinned under the status item.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    /// Opens the panel with its top edge just under `anchor` (the status item, in screen coordinates).
    func show(below anchor: NSRect) {
        statusItemFrame = anchor
        // Not animated: the reveal must start from zero, not from wherever a previous one stopped.
        state.materializeProgress = 0
        layout()
        panel.makeKeyAndOrderFront(nil)

        installMonitors()
        onVisibilityChanged?(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.30, dampingFraction: 1)) {
                self.state.materializeProgress = 1
            }
        }
    }

    /// Disappears at once, so whatever the click outside was meant for isn't kept waiting.
    func hide() {
        guard panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        onVisibilityChanged?(false)
    }

    /// Follows the content's height as tabs and sections change.
    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        guard panel.isVisible else { return }
        layout()
    }

    private func layout() {
        var measured = contentSize
        if measured.width <= 0 || measured.height <= 0 {
            // The hosting view reports no fitting size (its sizing options are off), and the content
            // only reports its own size once it is laid out in a window of real size. Until then,
            // measure a copy of the view so the panel opens at a real size; the content's own report
            // then corrects the height for the tab actually shown.
            let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            measured = NSHostingController(rootView: MenuPanelView(state: state, onSizeChange: { _ in }))
                .sizeThatFits(in: unbounded)
        }
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        guard size.width > 0, size.height > 0 else { return }
        let anchor = statusItemFrame
        let margin = MenuPanelView.margin
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8 - margin), visible.maxX - 8 + margin - size.width)
        // The status item's button is shorter than a notched display's menu bar, so its bottom edge
        // sits inside the bar; the menu bar's own bottom edge keeps the sheet clear of it.
        let top = min(anchor.minY, visible.maxY) - 6
        let y = top + margin - size.height
        let anchorX = min(max((anchor.midX - x) / size.width, 0), 1)
        if state.materializeAnchorX != anchorX { state.materializeAnchorX = anchorX }
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        // Settle the layout at the new size first; otherwise a size change since the last opening
        // gets swept into the reveal and the sheet appears to grow out of its top-left corner.
        hostingView.layoutSubtreeIfNeeded()
    }

    // MARK: - Input

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            // While a trigger key is being recorded, every key belongs to the recorder.
            guard AppSettings.shared.captureTarget == nil else { return event }
            if event.keyCode == 53 { // Esc
                self.hide()
                return nil
            }
            return event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.statusItemFrame.contains(NSEvent.mouseLocation) { return }
            // A modal dialog opened from the panel (the app chooser) is still using it.
            if NSApp.modalWindow != nil { return }
            Task { @MainActor in self.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }
}

// MARK: - Material

private enum PanelPalette {
    static let black = Color(.sRGB, red: 0x26 / 255, green: 0x24 / 255, blue: 0x27 / 255, opacity: 1)
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Liquid Glass tinted dark where the system has it, frosted blur under the same tint before that.
/// The tint fixes how bright the ground is, so light text stays readable over any window behind.
private struct GlassBackground<S: Shape>: View {
    let shape: S

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(PanelPalette.black.opacity(0.60)), in: shape)
            }
        } else {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                PanelPalette.black.opacity(0.60)
            }
        }
    }
}
