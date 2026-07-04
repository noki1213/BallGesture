//
//  GestureEngine.swift
//  BallGesture
//
//  Owns the CGEventTap and turns mouse movement, while a trigger key is held,
//  into scroll events (Scroll Mode) or pinch/zoom events (Zoom Mode).
//

import AppKit
import Combine
import CoreGraphics
import os

/// Reflects whether the CGEventTap is actually alive, for the menu bar UI.
/// Accessibility permission can be granted *after* launch (or after the app
/// bundle was reinstalled, which invalidates the previous grant), so this is
/// not the same thing as `AccessibilityPermission.isTrusted` — it's whether
/// our own tap creation has actually succeeded.
enum TapStatus: Equatable {
    case notStarted
    /// Tap creation failed (almost always: Accessibility permission not
    /// granted yet, or granted to a now-replaced app bundle after
    /// install.sh's rm -rf + cp reinstall). Retrying on a timer.
    case retrying
    case running
}

@MainActor
final class GestureEngine: ObservableObject {
    static let shared = GestureEngine()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.noki.BallGesture",
        category: "GestureEngine"
    )

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    private var scrollActive = false
    private var zoomActive = false
    /// Keycode whose keyUp must be swallowed after a key-capture keyDown,
    /// so the captured key doesn't leak a stray keyUp to other apps.
    private var pendingCaptureSwallowKeyCode: Int64?

    /// Cursor position captured the instant a mode starts. `CGAssociateMouseAndMouseCursorPosition(0)`
    /// is supposed to stop the OS from moving the cursor while it's disassociated, but on real
    /// hardware (trackball + driver utility) the cursor still visibly drifts even though
    /// `CGEvent(source: nil)?.location` keeps reporting the *locked* position — i.e. the "logical"
    /// location we read back is not reliable evidence that the on-screen cursor hasn't moved. So the
    /// warp fallback below no longer conditions on comparing current vs. locked position: it
    /// unconditionally re-warps on every mouseMoved, plus on a ~60Hz timer as a second safety net
    /// (in case something outside our tap, e.g. a trackball driver, injects its own cursor moves).
    /// `CGWarpMouseCursorPosition` posts no events of its own, so this cannot create a feedback loop
    /// through the tap.
    private var lockedCursorPosition: CGPoint?
    private var cursorPinTimer: Timer?

    /// Last cursor position observed while computing a mouseMoved delta.
    /// Mac Mouse Fix (a third-party mouse utility the user runs) intercepts
    /// raw HID mouse input with its own event tap and re-synthesizes the
    /// mouseMoved events our tap receives. Two consequences: (1) it may keep
    /// moving the on-screen cursor via its own synthetic events regardless of
    /// `CGAssociateMouseAndMouseCursorPosition`/our warp, and (2) its
    /// synthetic events are not guaranteed to carry non-zero
    /// mouseEventDeltaX/Y the way raw HID movement does. When the delta
    /// fields are both zero, this is used to derive a delta from the
    /// position change instead, so scrolling/zooming keeps working even if
    /// Mac Mouse Fix's events don't carry deltas.
    private var lastDeltaTrackingPosition: CGPoint?

    private let settings = AppSettings.shared

    @Published private(set) var tapStatus: TapStatus = .notStarted

    private init() {}

    var isRunning: Bool { eventTap != nil }

    /// Attempts to create the event tap. If it fails (almost always because
    /// the Accessibility permission has not been granted yet, or was granted
    /// to a previous build of the app bundle before install.sh replaced it),
    /// this schedules a retry every 2 seconds so the app starts working as
    /// soon as permission is granted, with no relaunch required.
    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let trusted = AccessibilityPermission.isTrusted
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            Self.logger.error(
                "Event tap creation FAILED (AXIsProcessTrusted=\(trusted, privacy: .public)). Will retry in 2s."
            )
            tapStatus = .retrying
            scheduleRetry()
            return
        }

        Self.logger.notice("Event tap created successfully (AXIsProcessTrusted=\(trusted, privacy: .public)).")

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapStatus = .running
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }

    func stop() {
        endActiveModesIfNeeded()
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        tapStatus = .notStarted
    }

    /// Safety net so the cursor is never left detached from the mouse and so
    /// an in-progress pinch gesture is always closed out. Call this from the
    /// app's termination handling.
    func endActiveModesIfNeeded() {
        if scrollActive {
            reassociateCursor()
            scrollActive = false
        }
        if zoomActive {
            postZoomEvent(phase: .ended, magnification: 0)
            reassociateCursor()
            zoomActive = false
        }
        lockedCursorPosition = nil
        lastDeltaTrackingPosition = nil
    }

    /// Current global cursor position, used to pin the cursor while a mode is active.
    private func currentCursorPosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func disassociateCursor() {
        let result = CGAssociateMouseAndMouseCursorPosition(0)
        let position = currentCursorPosition()
        lockedCursorPosition = position
        lastDeltaTrackingPosition = position
        Self.logger.notice(
            "Cursor disassociated (result=\(result.rawValue, privacy: .public)), locked at \(String(describing: self.lockedCursorPosition), privacy: .public)."
        )
        startCursorPinTimer()
    }

    private func reassociateCursor() {
        stopCursorPinTimer()
        let result = CGAssociateMouseAndMouseCursorPosition(1)
        Self.logger.notice("Cursor reassociated (result=\(result.rawValue, privacy: .public)).")
        lockedCursorPosition = nil
        lastDeltaTrackingPosition = nil
    }

    /// Second safety net alongside the per-mouseMoved warp in `pinCursorIfNeeded`:
    /// re-warps on a timer too, in case the cursor is being moved by something
    /// that doesn't go through our tap's mouseMoved handling at all (e.g. a
    /// trackball driver utility injecting its own cursor position updates).
    private func startCursorPinTimer() {
        stopCursorPinTimer()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.pinCursorIfNeeded(source: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorPinTimer = timer
    }

    private func stopCursorPinTimer() {
        cursorPinTimer?.invalidate()
        cursorPinTimer = nil
    }

    fileprivate func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.notice("Event tap was disabled (timeout or user input); re-enabling.")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown, .keyUp:
            return handleKeyEvent(type: type, event: event)
        case .mouseMoved:
            return handleMouseMoved(event: event)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Diagnostic: log every keyDown/keyUp the tap sees, so it's possible
        // to tell from `log show --predicate 'process == "BallGesture"'`
        // (no extra flags needed — this is logged at .notice, which is
        // persisted and shown by default, unlike .debug/.info) whether a
        // given physical key press (e.g. a ZMK/cornix combo sending F15)
        // reaches the tap at all, and whether it arrives as a real hold
        // (keyDown ... time passes ... keyUp) or as an instant tap (keyDown
        // immediately followed by keyUp).
        Self.logger.notice(
            "\(type == .keyDown ? "keyDown" : "keyUp", privacy: .public) keyCode=\(keyCode, privacy: .public) repeat=\(isRepeat, privacy: .public)"
        )

        // Key-capture UI ("Set Key" in the menu) takes priority over normal handling.
        if settings.captureTarget != nil {
            if type == .keyDown {
                if settings.handleCapturedKeyCode(keyCode) {
                    Self.logger.notice("Captured keyCode=\(keyCode, privacy: .public) for trigger key assignment.")
                    pendingCaptureSwallowKeyCode = keyCode
                    return nil
                }
            } else if type == .keyUp, pendingCaptureSwallowKeyCode == keyCode {
                pendingCaptureSwallowKeyCode = nil
                return nil
            }
            return Unmanaged.passRetained(event)
        }

        guard settings.isEnabled else {
            return Unmanaged.passRetained(event)
        }

        if keyCode == settings.scrollTriggerKeyCode {
            if type == .keyDown, !scrollActive {
                scrollActive = true
                disassociateCursor()
                Self.logger.notice("Scroll Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, scrollActive {
                scrollActive = false
                reassociateCursor()
                Self.logger.notice("Scroll Mode ENDED (keyCode=\(keyCode, privacy: .public)).")
            }
            return nil
        }

        if keyCode == settings.zoomTriggerKeyCode {
            if type == .keyDown, !zoomActive {
                zoomActive = true
                disassociateCursor()
                postZoomEvent(phase: .began, magnification: 0)
                Self.logger.notice("Zoom Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, zoomActive {
                postZoomEvent(phase: .ended, magnification: 0)
                zoomActive = false
                reassociateCursor()
                Self.logger.notice("Zoom Mode ENDED (keyCode=\(keyCode, privacy: .public)).")
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func handleMouseMoved(event: CGEvent) -> Unmanaged<CGEvent>? {
        if scrollActive {
            let delta = effectiveDelta(from: event)
            postScroll(deltaX: delta.dx, deltaY: delta.dy)
            pinCursorIfNeeded(source: "mouseMoved")
            return nil
        }
        if zoomActive {
            let delta = effectiveDelta(from: event)
            postZoomDelta(deltaY: delta.dy)
            pinCursorIfNeeded(source: "mouseMoved")
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    /// Reads mouseEventDeltaX/Y off the event; if a third-party mouse
    /// utility (Mac Mouse Fix) is intercepting input and re-synthesizing the
    /// mouseMoved events we see, those synthetic events are not guaranteed
    /// to carry non-zero delta fields the way raw HID movement does. When
    /// both deltas are zero, this falls back to the position change since
    /// the last event as the delta instead, so Scroll/Zoom Mode keeps
    /// working either way. Logged every time so a real device can confirm
    /// whether raw deltas are actually arriving as zero.
    private func effectiveDelta(from event: CGEvent) -> (dx: Double, dy: Double) {
        let rawDX = event.getIntegerValueField(.mouseEventDeltaX)
        let rawDY = event.getIntegerValueField(.mouseEventDeltaY)
        let current = currentCursorPosition()

        var dx = Double(rawDX)
        var dy = Double(rawDY)
        var usedFallback = false
        if rawDX == 0, rawDY == 0, let last = lastDeltaTrackingPosition {
            dx = Double(current.x - last.x)
            dy = Double(current.y - last.y)
            usedFallback = true
        }

        let message = "delta: raw=(\(rawDX),\(rawDY)) current=\(current) last=" +
            "\(String(describing: lastDeltaTrackingPosition)) fallback=\(usedFallback) effective=(\(dx),\(dy))"
        Self.logger.notice("\(message, privacy: .public)")

        lastDeltaTrackingPosition = current
        return (dx, dy)
    }

    /// Re-pins the cursor to the position captured when the mode started.
    /// `CGWarpMouseCursorPosition` posts no events, so this cannot re-trigger
    /// this same tap and cannot create a feedback loop.
    ///
    /// This warps UNCONDITIONALLY on every call rather than first comparing
    /// `currentCursorPosition()` to `lockedCursorPosition` — on real hardware,
    /// `CGEvent(source: nil)?.location` kept reporting the locked position
    /// even while the on-screen cursor was visibly drifting, so that
    /// "logical position" comparison is not trustworthy evidence of whether
    /// a warp is needed. Called both from every mouseMoved (in case a
    /// trackball's own driver moves the cursor without going through our
    /// tap) via `startCursorPinTimer`'s ~60Hz timer.
    private func pinCursorIfNeeded(source: String) {
        guard let locked = lockedCursorPosition else { return }
        let before = currentCursorPosition()
        let warpResult = CGWarpMouseCursorPosition(locked)
        let after = currentCursorPosition()
        // Logging both before AND after the warp is the point here: if
        // `after` still doesn't match `locked`, something (e.g. Mac Mouse
        // Fix's own event tap re-synthesizing cursor moves right behind our
        // warp) is fighting us for the cursor position and this needs a
        // different approach (e.g. warping repeatedly within the same
        // event, or coordinating with Mac Mouse Fix instead of overriding it).
        Self.logger.notice(
            "pinCursor[\(source, privacy: .public)]: before=\(String(describing: before), privacy: .public) locked=\(String(describing: locked), privacy: .public) warpResult=\(warpResult.rawValue, privacy: .public) after=\(String(describing: after), privacy: .public)"
        )
    }

    private func postScroll(deltaX: Double, deltaY: Double) {
        guard deltaX != 0 || deltaY != 0 else { return }

        // Natural direction: moving the pointer down scrolls down (content
        // follows the movement), matching macOS's "natural scrolling" feel.
        let sign: Double = settings.naturalScrollDirection ? 1 : -1
        let sensitivity = settings.scrollSensitivity

        let scrollY = Int32((deltaY * sensitivity * sign).rounded())
        let scrollX = Int32((deltaX * sensitivity * sign).rounded())
        guard scrollY != 0 || scrollX != 0 else { return }

        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: scrollY,
            wheel2: scrollX,
            wheel3: 0
        ) else { return }

        scrollEvent.post(tap: .cghidEventTap)
    }

    private func postZoomDelta(deltaY: Double) {
        guard deltaY != 0 else { return }

        // Moving the pointer up magnifies (zoom in); down shrinks (zoom out).
        let magnification = -deltaY * settings.zoomSensitivity * 0.01

        switch settings.zoomMethod {
        case .pinch:
            postZoomEvent(phase: .changed, magnification: magnification)
        case .ctrlScroll, .cmdScroll:
            postModifierScrollZoom(deltaY: deltaY)
        }
    }

    private func postZoomEvent(phase: CGSGesturePhase, magnification: Double) {
        PinchGestureEvent.post(phase: phase, magnification: magnification, tap: .cgSessionEventTap)
    }

    private func postModifierScrollZoom(deltaY: Double) {
        let scrollAmount = Int32((-deltaY * settings.zoomSensitivity).rounded())
        guard scrollAmount != 0 else { return }

        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: scrollAmount,
            wheel2: 0,
            wheel3: 0
        ) else { return }

        scrollEvent.flags = settings.zoomMethod == .cmdScroll ? .maskCommand : .maskControl
        scrollEvent.post(tap: .cghidEventTap)
    }
}

/// Free, non-capturing C callback required by CGEvent.tapCreate. It hops back
/// onto the main actor with `MainActor.assumeIsolated`, which is safe here
/// because the tap's run loop source is only ever added to the main run loop,
/// so this callback always executes on the main thread.
nonisolated private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let engine = Unmanaged<GestureEngine>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        engine.handle(proxy: proxy, type: type, event: event)
    }
}
