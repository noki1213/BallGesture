//
//  GestureEngine.swift
//  BallGesture
//
//  Owns the CGEventTap and turns mouse movement, while a trigger key is held,
//  into scroll events (Scroll Mode), pinch/zoom events (Zoom Mode), system
//  gestures (Gesture Mode), or the drags, scrolls and pinches a 3D view uses
//  to pan, zoom and rotate (3D Mode).
//

import AppKit
import Carbon.HIToolbox
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
    private var gestureActive = false
    private var gestureAccumulatedX = 0.0
    private var gestureAccumulatedY = 0.0
    private var hasTriggeredGesture = false
    /// Keycode whose keyUp must be swallowed after a key-capture keyDown,
    /// so the captured key doesn't leak a stray keyUp to other apps.
    private var pendingCaptureSwallowKeyCode: Int64?

    /// Cursor position captured the instant a mode starts. `CGAssociateMouseAndMouseCursorPosition(0)`
    /// is supposed to stop the OS from moving the cursor while it's disassociated, but on real
    /// hardware (trackball + driver utility) the cursor still visibly drifts even though
    /// `CGEvent(source: nil)?.location` keeps reporting the *locked* position — i.e. the "logical"
    /// location we read back is not reliable evidence that the on-screen cursor hasn't moved. So the
    /// warp fallback below does not condition on comparing current vs. locked position: it
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

    /// Trigger keys the HID system reported as held when their mode started.
    /// For these, a later "not held" reading is trustworthy, so a mode whose
    /// keyUp never reached the tap (the tap is disabled by timeout while the
    /// system is under heavy load, and events in that window bypass it) can
    /// be ended instead of turning ordinary pointer movement into scrolling.
    private var verifiableTriggerKeyCodes: Set<Int64> = []

    /// One hold of a 3D trigger key. The binding is resolved from the
    /// frontmost app once, at keyDown, so the output never changes mid-drag.
    private struct ThreeDSession {
        let action: ThreeDAction
        let keyCode: Int64
        let binding: ThreeDBinding
        /// Where the pointer was at keyDown; it returns here at keyUp.
        let origin: CGPoint
        /// Where the synthesized drag currently is.
        var position: CGPoint
        var isFirstScrollEvent = true
        /// Fractional wheel notches not yet posted.
        var wheelRemainder = 0.0
    }
    private var threeDSession: ThreeDSession?
    /// Pointer movement (px, after sensitivity) per wheel notch in 3D Mode.
    private static let threeDWheelStep = 8.0

    // MARK: Momentum scrolling
    //
    // Momentum is triggered by detecting a FLICK, not by releasing the
    // trigger key: while Scroll Mode is held, we track mouseMoved velocity;
    // if it was fast and then mouseMoved events stop arriving for a short
    // idle window, that's treated as "the ball was flicked and is now
    // spinning down on its own" and momentum begins immediately — even
    // though the trigger key may still be held. This deliberately does NOT
    // trigger on key release by itself, so that releasing the key after a
    // flick (a very natural motion) doesn't cut momentum off, and so that
    // holding the key without flicking never starts momentum.

    /// Exponential moving average of scroll speed (px/s, in the same
    /// already-sensitivity/direction-adjusted units posted to scroll
    /// events), updated on every Scroll Mode mouseMoved. This is the "real"
    /// speed the trigger's own physical scrolling (e.g. a trackball's own
    /// momentum) is producing; only once mouseMoved events stop arriving
    /// do we splice in our own synthetic decay (`momentumVelocityX/Y`) to
    /// continue the motion.
    private var scrollVelocityX = 0.0
    private var scrollVelocityY = 0.0
    private var lastVelocitySampleTime: CFAbsoluteTime?
    /// Smoothing factor for the velocity EMA (0...1, higher = more reactive to the latest sample).
    private static let velocityEMAAlpha = 0.35

    private var momentumActive = false
    private var momentumVelocityX = 0.0
    private var momentumVelocityY = 0.0
    private var momentumStartTime: CFAbsoluteTime?
    private var momentumTimer: Timer?
    private var isFirstMomentumTick = true
    private var isFirstScrollEventOfDrag = true

    /// Fires once mouseMoved events stop arriving for this long during
    /// Scroll Mode; if the tracked speed at that point is still above
    /// `momentumStartThreshold`, that's treated as a flick and momentum
    /// begins. Reset (cancelled + rescheduled) on every mouseMoved, so as
    /// long as real movement keeps arriving (e.g. a trackball ball still
    /// physically spinning down on its own), we just keep scrolling at its
    /// real reported speed and never touch this. 50-100ms is the
    /// recommended tunable range.
    private var flickDetectionTimer: Timer?
    private static let flickIdleDetectionInterval = 0.07

    /// A flick only starts momentum if speed at the idle-detection moment is at least this fast (px/s).
    private static let momentumStartThreshold = 120.0
    /// Momentum stops once decayed speed drops below this (px/s).
    private static let momentumStopThreshold = 8.0
    private static let momentumTickInterval = 1.0 / 60.0

    /// Maps `AppSettings.momentumStrength` (0...1, "looseness") to a decay
    /// half-life in seconds, then to a per-tick multiplicative decay factor.
    /// This is the "decay rate as an adjustable constant" the feature asked
    /// for: the 0.15s...1.5s half-life range below is the constant to tune.
    private static func momentumDecayFactorPerTick(strength: Double) -> Double {
        let clamped = min(max(strength, 0), 1)
        let halfLifeSeconds = 0.15 + clamped * 1.35
        return pow(0.5, momentumTickInterval / halfLifeSeconds)
    }

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

        // NOTE: intentionally NOT subscribing to .otherMouseDown (middle/side
        // buttons) here. Mac Mouse Fix synthesizes its own auxiliary mouse
        // button events as part of its click-and-drag scroll emulation, and
        // those were incorrectly detected as "the user clicked" — stopping
        // momentum scrolling that hadn't actually been interrupted by a real
        // click. Left/right clicks are unambiguous real user actions.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

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
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
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
        cancelFlickDetection()
        if scrollActive {
            reassociateCursor()
            scrollActive = false
        }
        if zoomActive {
            postZoomEvent(phase: .ended, magnification: 0)
            reassociateCursor()
            zoomActive = false
        }
        if gestureActive {
            reassociateCursor()
            gestureActive = false
        }
        if threeDSession != nil {
            endThreeDMode(reason: "app terminating")
        }
        if momentumActive {
            stopMomentum(reason: "app terminating")
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
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pinCursorIfNeeded(source: "timer") }
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
            endModesWhoseTriggerWasReleased()
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown, .keyUp:
            return handleKeyEvent(type: type, event: event)
        case .mouseMoved:
            return handleMouseMoved(event: event)
        case .leftMouseDown, .rightMouseDown:
            // A click during momentum scrolling should stop it, so an
            // in-flight inertial scroll doesn't keep scrolling the page out
            // from under an unrelated click. Always pass the click through
            // unmodified either way — we only ever observe it here.
            if momentumActive {
                let typeName = type == .leftMouseDown ? "left" : "right"
                stopMomentum(reason: "\(typeName) mouse click")
            }
            return Unmanaged.passRetained(event)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Diagnostic: shows whether a given physical key press (e.g. a
        // keyboard combo sending F15) reaches the tap at all, and whether it
        // arrives as a real hold or as an instant tap. Debug level: every
        // keystroke on the system passes through here, and the callback must
        // stay light so the tap is not disabled by timeout under load.
        Self.logger.debug(
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
                if momentumActive {
                    stopMomentum(reason: "new Scroll Mode started")
                }
                cancelFlickDetection()
                scrollActive = true
                isFirstScrollEventOfDrag = true
                resetScrollVelocityTracking()
                disassociateCursor()
                recordTriggerVerifiability(keyCode)
                Self.logger.notice("Scroll Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, scrollActive {
                endScrollMode(reason: "keyUp")
            }
            return nil
        }

        if keyCode == settings.zoomTriggerKeyCode {
            if type == .keyDown, !zoomActive {
                zoomActive = true
                disassociateCursor()
                recordTriggerVerifiability(keyCode)
                postZoomEvent(phase: .began, magnification: 0)
                Self.logger.notice("Zoom Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, zoomActive {
                endZoomMode(reason: "keyUp")
            }
            return nil
        }

        if keyCode == settings.gestureTriggerKeyCode {
            if type == .keyDown, !gestureActive {
                gestureActive = true
                gestureAccumulatedX = 0.0
                gestureAccumulatedY = 0.0
                hasTriggeredGesture = false
                disassociateCursor()
                recordTriggerVerifiability(keyCode)
                Self.logger.notice("Gesture Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, gestureActive {
                endGestureMode(reason: "keyUp")
            }
            return nil
        }

        if let action = settings.threeDAction(forKeyCode: keyCode) {
            if type == .keyDown, threeDSession?.action != action {
                beginThreeDMode(action, keyCode: keyCode)
            } else if type == .keyUp, threeDSession?.action == action {
                endThreeDMode(reason: "keyUp")
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func endScrollMode(reason: String) {
        scrollActive = false
        verifiableTriggerKeyCodes.remove(settings.scrollTriggerKeyCode)
        reassociateCursor()
        if !momentumActive {
            // No flick was detected while the key was held, so this
            // release is the natural end of the drag gesture.
            postScrollPhaseMarker(scrollPhase: .ended, momentumPhase: nil)
        }
        // Deliberately NOT starting or stopping momentum here — see
        // the "Momentum scrolling" MARK above. If a flick was
        // already detected mid-hold, momentum keeps running
        // independently of this key release (so flick-then-release
        // works naturally); if not, nothing further happens.
        Self.logger.notice("Scroll Mode ENDED (\(reason, privacy: .public)).")
    }

    private func endZoomMode(reason: String) {
        postZoomEvent(phase: .ended, magnification: 0)
        zoomActive = false
        verifiableTriggerKeyCodes.remove(settings.zoomTriggerKeyCode)
        reassociateCursor()
        Self.logger.notice("Zoom Mode ENDED (\(reason, privacy: .public)).")
    }

    private func endGestureMode(reason: String) {
        gestureActive = false
        verifiableTriggerKeyCodes.remove(settings.gestureTriggerKeyCode)
        reassociateCursor()
        Self.logger.notice("Gesture Mode ENDED (\(reason, privacy: .public)).")
    }

    private static func isKeyPhysicallyHeld(_ keyCode: Int64) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(truncatingIfNeeded: keyCode))
    }

    /// Only trusts the HID key state for a trigger if it reads as held right
    /// when its keyDown arrives; a key delivered some other way (e.g. posted
    /// by software) may never show up there, and must not end its mode early.
    private func recordTriggerVerifiability(_ keyCode: Int64) {
        if Self.isKeyPhysicallyHeld(keyCode) {
            verifiableTriggerKeyCodes.insert(keyCode)
        } else {
            verifiableTriggerKeyCodes.remove(keyCode)
        }
    }

    /// Ends any active mode whose trigger key is no longer held even though
    /// its keyUp never arrived.
    private func endModesWhoseTriggerWasReleased() {
        func released(_ keyCode: Int64) -> Bool {
            verifiableTriggerKeyCodes.contains(keyCode) && !Self.isKeyPhysicallyHeld(keyCode)
        }
        if scrollActive, released(settings.scrollTriggerKeyCode) {
            cancelFlickDetection()
            resetScrollVelocityTracking()
            endScrollMode(reason: "trigger no longer held, keyUp missed")
        }
        if zoomActive, released(settings.zoomTriggerKeyCode) {
            endZoomMode(reason: "trigger no longer held, keyUp missed")
        }
        if gestureActive, released(settings.gestureTriggerKeyCode) {
            endGestureMode(reason: "trigger no longer held, keyUp missed")
        }
        if let session = threeDSession, released(session.keyCode) {
            endThreeDMode(reason: "trigger no longer held, keyUp missed")
        }
    }

    private func handleMouseMoved(event: CGEvent) -> Unmanaged<CGEvent>? {
        if scrollActive || zoomActive || gestureActive || threeDSession != nil {
            endModesWhoseTriggerWasReleased()
        }
        if threeDSession != nil {
            let delta = effectiveDelta(from: event)
            moveThreeD(dx: delta.dx, dy: delta.dy)
            return nil
        }
        if scrollActive {
            if momentumActive {
                // The ball was flicked (momentum already started) but has
                // been grabbed/moved again — cancel the synthetic decay and
                // resume real-time scrolling seamlessly, as one continuous
                // gesture from the user's perspective.
                stopMomentum(reason: "ball moved again")
                isFirstScrollEventOfDrag = true
            }
            let delta = effectiveDelta(from: event)
            postScroll(deltaX: delta.dx, deltaY: delta.dy)
            pinCursorIfNeeded(source: "mouseMoved")
            scheduleFlickDetection()
            return nil
        }
        if zoomActive {
            let delta = effectiveDelta(from: event)
            postZoomDelta(deltaY: delta.dy)
            pinCursorIfNeeded(source: "mouseMoved")
            return nil
        }
        if gestureActive {
            if !hasTriggeredGesture {
                let delta = effectiveDelta(from: event)
                gestureAccumulatedX += delta.dx
                gestureAccumulatedY += delta.dy

                // Fire only once one axis is clearly dominant (2x the other),
                // not merely first past the threshold: a leftward trackball
                // swipe naturally carries some diagonal drift, so deciding
                // the direction at the instant either axis crosses the
                // threshold resolves ~45° input to the wrong gesture (Back
                // turning into Mission Control). Ambiguous diagonal input
                // waits for more movement instead.
                let threshold = settings.gestureDistance
                let ax = abs(gestureAccumulatedX)
                let ay = abs(gestureAccumulatedY)
                let horizontalWins = ax > threshold && ax > 2 * ay
                let verticalWins = ay > threshold && ay > 2 * ax
                if horizontalWins || verticalWins {
                    hasTriggeredGesture = true
                    triggerGesture(dx: gestureAccumulatedX, dy: gestureAccumulatedY)
                    pinCursorIfNeeded(source: "gestureTriggered")
                }
            } else {
                pinCursorIfNeeded(source: "mouseMoved")
            }
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    /// Resets the flick-idle timer: as long as mouseMoved events keep
    /// arriving within `flickIdleDetectionInterval` of each other, this
    /// never fires and we just keep scrolling at whatever real speed is
    /// being reported. Once movement actually stops (or slows enough that
    /// events stop arriving that quickly), `checkForFlick()` fires and
    /// decides whether that was a flick worth continuing as momentum.
    private func scheduleFlickDetection() {
        flickDetectionTimer?.invalidate()
        let timer = Timer(timeInterval: Self.flickIdleDetectionInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForFlick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        flickDetectionTimer = timer
    }

    private func cancelFlickDetection() {
        flickDetectionTimer?.invalidate()
        flickDetectionTimer = nil
    }

    /// Called when no mouseMoved arrived for `flickIdleDetectionInterval`.
    /// If the tracked speed at that moment is still fast, this was a flick:
    /// close out the drag phase (as if fingers were lifted) and start
    /// momentum from here, regardless of whether the trigger key is still
    /// physically held.
    private func checkForFlick() {
        flickDetectionTimer = nil
        guard !momentumActive else { return }

        let speed = (scrollVelocityX * scrollVelocityX + scrollVelocityY * scrollVelocityY).squareRoot()
        guard settings.momentumScrollingEnabled, speed >= Self.momentumStartThreshold else {
            resetScrollVelocityTracking()
            return
        }

        postScrollPhaseMarker(scrollPhase: .ended, momentumPhase: nil)
        beginMomentum(velocityX: scrollVelocityX, velocityY: scrollVelocityY)
        resetScrollVelocityTracking()
    }

    /// Reads mouseEventDeltaX/Y off the event; if a third-party mouse
    /// utility (Mac Mouse Fix) is intercepting input and re-synthesizing the
    /// mouseMoved events we see, those synthetic events are not guaranteed
    /// to carry non-zero delta fields the way raw HID movement does. When
    /// both deltas are zero, this falls back to the position change since
    /// the last event as the delta instead, so Scroll/Zoom Mode keeps
    /// working either way. Logged at debug level on every event so a real
    /// device can confirm whether raw deltas are actually arriving as zero.
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
        Self.logger.debug("\(message, privacy: .public)")

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
        // Debug level: this runs at ~60Hz while the cursor is pinned, too
        // often to keep in the persisted log.
        Self.logger.debug(
            "pinCursor[\(source, privacy: .public)]: before=\(String(describing: before), privacy: .public) locked=\(String(describing: locked), privacy: .public) warpResult=\(warpResult.rawValue, privacy: .public) after=\(String(describing: after), privacy: .public)"
        )
    }

    private func postScroll(deltaX: Double, deltaY: Double) {
        guard deltaX != 0 || deltaY != 0 else { return }

        // Natural direction: moving the pointer down scrolls down (content
        // follows the movement), matching macOS's "natural scrolling" feel.
        let sign: Double = settings.naturalScrollDirection ? 1 : -1
        let sensitivity = settings.scrollSensitivity

        let rawScrollY = deltaY * sensitivity * sign
        let rawScrollX = deltaX * sensitivity * sign
        updateScrollVelocity(scrollX: rawScrollX, scrollY: rawScrollY)

        let scrollY = Int32(rawScrollY.rounded())
        let scrollX = Int32(rawScrollX.rounded())
        guard scrollY != 0 || scrollX != 0 else { return }

        guard let scrollEvent = Self.pixelScrollEvent(x: scrollX, y: scrollY) else { return }

        // First event of a drag carries .began, the rest .changed — this is
        // a real trackpad-style scroll phase sequence (see
        // ScrollPhaseExtensions.swift), not just discrete wheel ticks.
        let phase: ScrollPhase = isFirstScrollEventOfDrag ? .began : .changed
        isFirstScrollEventOfDrag = false
        scrollEvent.setScrollPhases(scrollPhase: phase, momentumPhase: nil)

        scrollEvent.post(tap: .cghidEventTap)
    }

    /// Posts a zero-delta scroll event carrying only a phase transition
    /// (e.g. drag .ended, or momentum .end). Real trackpad scrolling always
    /// sends one of these to mark a transition, separate from any event
    /// that actually carries movement. `tap` defaults to `.cghidEventTap`
    /// (matching regular drag events); momentum-related markers pass
    /// `.cgSessionEventTap` instead — see the comment in `momentumTick()`.
    private func postScrollPhaseMarker(
        scrollPhase: ScrollPhase?,
        momentumPhase: MomentumScrollPhase?,
        tap: CGEventTapLocation = .cghidEventTap
    ) {
        guard let event = Self.pixelScrollEvent(x: 0, y: 0) else { return }

        event.setScrollPhases(scrollPhase: scrollPhase, momentumPhase: momentumPhase)
        event.post(tap: tap)
    }

    /// A two-axis scroll event measured in pixels, the kind a trackpad sends.
    private static func pixelScrollEvent(x: Int32, y: Int32) -> CGEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)
    }

    /// Updates the exponential moving average of scroll speed (px/s) used
    /// as momentum's starting velocity if the trigger key is released while
    /// still moving. `scrollX`/`scrollY` are in the same already-sensitivity/
    /// direction-adjusted units posted to real scroll events.
    private func updateScrollVelocity(scrollX: Double, scrollY: Double) {
        let now = CFAbsoluteTimeGetCurrent()
        defer { lastVelocitySampleTime = now }

        guard let last = lastVelocitySampleTime else { return }
        let dt = now - last
        guard dt > 0.001 else { return }

        let instantVelocityX = scrollX / dt
        let instantVelocityY = scrollY / dt
        let alpha = Self.velocityEMAAlpha
        scrollVelocityX = alpha * instantVelocityX + (1 - alpha) * scrollVelocityX
        scrollVelocityY = alpha * instantVelocityY + (1 - alpha) * scrollVelocityY
    }

    private func resetScrollVelocityTracking() {
        scrollVelocityX = 0
        scrollVelocityY = 0
        lastVelocitySampleTime = nil
    }

    /// Starts a decaying momentum phase from the given velocity. Called
    /// from `checkForFlick()` when a flick is detected — never from key
    /// release directly (see the "Momentum scrolling" MARK above).
    private func beginMomentum(velocityX: Double, velocityY: Double) {
        momentumVelocityX = velocityX
        momentumVelocityY = velocityY
        momentumActive = true
        isFirstMomentumTick = true
        momentumStartTime = CFAbsoluteTimeGetCurrent()

        let speed = (velocityX * velocityX + velocityY * velocityY).squareRoot()
        let startMessage = "Momentum scrolling STARTED initialVelocity=(\(velocityX),\(velocityY))px/s " +
            "speed=\(speed)px/s strength=\(settings.momentumStrength)"
        Self.logger.notice("\(startMessage, privacy: .public)")

        let timer = Timer(timeInterval: Self.momentumTickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.momentumTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        momentumTimer = timer
    }

    private func momentumTick() {
        guard momentumActive else { return }

        let decay = Self.momentumDecayFactorPerTick(strength: settings.momentumStrength)
        momentumVelocityX *= decay
        momentumVelocityY *= decay

        let speed = (momentumVelocityX * momentumVelocityX + momentumVelocityY * momentumVelocityY).squareRoot()
        guard speed >= Self.momentumStopThreshold else {
            stopMomentum(reason: "decayed below threshold")
            return
        }

        let scrollX = Int32((momentumVelocityX * Self.momentumTickInterval).rounded())
        let scrollY = Int32((momentumVelocityY * Self.momentumTickInterval).rounded())
        guard let event = Self.pixelScrollEvent(x: scrollX, y: scrollY) else { return }

        let phase: MomentumScrollPhase = isFirstMomentumTick ? .begin : .continue
        isFirstMomentumTick = false
        event.setScrollPhases(scrollPhase: nil, momentumPhase: phase)

        // Momentum-phase events specifically are posted at .cgSessionEventTap
        // (not .cghidEventTap like regular drag events) so they bypass any
        // HID-level event tap entirely — including Mac Mouse Fix's own
        // scroll-wheel tap, which sits at kCGHIDEventTap. Per Mac Mouse
        // Fix's own (open) source (Helper/Core/Scroll/Scroll.m), it already
        // passes through continuous/phased events unmodified, but injecting
        // downstream of any such HID-level tap is a strictly safer
        // guarantee than relying on that.
        event.post(tap: .cgSessionEventTap)
    }

    private func stopMomentum(reason: String) {
        guard momentumActive else { return }
        let duration = momentumStartTime.map { CFAbsoluteTimeGetCurrent() - $0 } ?? 0
        Self.logger.notice("Momentum scrolling ENDED reason=\(reason, privacy: .public) duration=\(duration, privacy: .public)s")

        // Always send the momentum .end marker exactly once here, regardless
        // of why momentum is stopping (natural decay, a new Scroll Mode
        // starting, a mouse click, or app termination), so the receiving
        // app's momentum state machine is always closed out cleanly.
        postScrollPhaseMarker(scrollPhase: nil, momentumPhase: .end, tap: .cgSessionEventTap)

        momentumTimer?.invalidate()
        momentumTimer = nil
        momentumActive = false
        momentumVelocityX = 0
        momentumVelocityY = 0
        momentumStartTime = nil
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

    // MARK: 3D Mode

    private func beginThreeDMode(_ action: ThreeDAction, keyCode: Int64) {
        if threeDSession != nil {
            endThreeDMode(reason: "switched to \(action.rawValue)")
        }
        if momentumActive {
            stopMomentum(reason: "3D Mode started")
        }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let binding = settings.threeDProfile(forBundleID: bundleID)[action]
        disassociateCursor()
        let origin = currentCursorPosition()
        threeDSession = ThreeDSession(action: action, keyCode: keyCode, binding: binding, origin: origin, position: origin)
        recordTriggerVerifiability(keyCode)

        if Self.holdsShift(binding.output) {
            postShiftKey(down: true)
        }
        if let button = Self.dragButton(for: binding.output) {
            postDragEvent(.down, button: button, at: origin, shift: Self.holdsShift(binding.output))
        } else if binding.output == .pinch {
            postZoomEvent(phase: .began, magnification: 0)
        }
        Self.logger.notice(
            "3D Mode STARTED (action=\(action.rawValue, privacy: .public), output=\(binding.output.rawValue, privacy: .public), reversed=\(binding.reversed, privacy: .public), frontmost=\(bundleID ?? "nil", privacy: .public))."
        )
    }

    private func endThreeDMode(reason: String) {
        guard let session = threeDSession else { return }
        threeDSession = nil
        verifiableTriggerKeyCodes.remove(session.keyCode)
        let output = session.binding.output

        if let button = Self.dragButton(for: output) {
            postDragEvent(.up, button: button, at: session.position, shift: Self.holdsShift(output))
        } else if output == .pinch {
            postZoomEvent(phase: .ended, magnification: 0)
        } else if output == .scroll || output == .shiftScroll, !session.isFirstScrollEvent {
            postThreeDScroll(x: 0, y: 0, phase: .ended, shift: output == .shiftScroll)
        }
        if Self.holdsShift(output) {
            postShiftKey(down: false)
        }
        reassociateCursor()
        CGWarpMouseCursorPosition(session.origin)
        Self.logger.notice("3D Mode ENDED (\(reason, privacy: .public)).")
    }

    private func moveThreeD(dx rawDX: Double, dy rawDY: Double) {
        guard var session = threeDSession else { return }
        let output = session.binding.output
        let scale = settings.threeDSensitivity * (session.binding.reversed ? -1 : 1)
        // Zoom is one-dimensional: only vertical movement counts.
        let dx = session.action == .zoom ? 0 : rawDX * scale
        let dy = rawDY * scale

        if let button = Self.dragButton(for: output) {
            moveDrag(&session, button: button, dx: dx, dy: dy)
        } else {
            switch output {
            case .scroll, .shiftScroll:
                // Content follows the pointer, as with natural scrolling.
                let x = Int32(dx.rounded())
                let y = Int32(dy.rounded())
                if x != 0 || y != 0 {
                    postThreeDScroll(
                        x: x, y: y,
                        phase: session.isFirstScrollEvent ? .began : .changed,
                        shift: output == .shiftScroll
                    )
                    session.isFirstScrollEvent = false
                }
            case .pinch:
                // Moving up magnifies, as in Zoom Mode.
                if dy != 0 {
                    postZoomEvent(phase: .changed, magnification: -dy * 0.01)
                }
            case .wheel:
                // Moving up sends wheel-up notches.
                session.wheelRemainder += -dy / Self.threeDWheelStep
                let notches = Int32(session.wheelRemainder.rounded(.towardZero))
                if notches != 0 {
                    session.wheelRemainder -= Double(notches)
                    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: notches, wheel2: 0, wheel3: 0)?
                        .post(tap: .cgSessionEventTap)
                }
            default:
                break
            }
            pinCursorIfNeeded(source: "mouseMoved")
        }
        threeDSession = session
    }

    /// Moves the synthesized drag, and the pointer with it, since 3D views
    /// read the pointer location rather than event deltas. When the drag
    /// would leave the screen, it lets go and grabs again from the origin so
    /// the view can keep turning in the same direction.
    private func moveDrag(_ session: inout ThreeDSession, button: CGMouseButton, dx: Double, dy: Double) {
        guard dx != 0 || dy != 0 else { return }
        let shift = Self.holdsShift(session.binding.output)
        var next = CGPoint(x: session.position.x + dx, y: session.position.y + dy)
        if !Self.isOnScreen(next) {
            postDragEvent(.up, button: button, at: session.position, shift: shift)
            CGWarpMouseCursorPosition(session.origin)
            postDragEvent(.down, button: button, at: session.origin, shift: shift)
            next = CGPoint(x: session.origin.x + dx, y: session.origin.y + dy)
        }
        session.position = next
        postDragEvent(.dragged, button: button, at: next, shift: shift, delta: (dx, dy))
        CGWarpMouseCursorPosition(next)
        lockedCursorPosition = next
        lastDeltaTrackingPosition = next
    }

    private enum DragStage { case down, dragged, up }

    private func postDragEvent(
        _ stage: DragStage,
        button: CGMouseButton,
        at point: CGPoint,
        shift: Bool,
        delta: (dx: Double, dy: Double) = (0, 0)
    ) {
        let type: CGEventType
        switch (button, stage) {
        case (.left, .down): type = .leftMouseDown
        case (.left, .dragged): type = .leftMouseDragged
        case (.left, .up): type = .leftMouseUp
        case (.right, .down): type = .rightMouseDown
        case (.right, .dragged): type = .rightMouseDragged
        case (.right, .up): type = .rightMouseUp
        case (_, .down): type = .otherMouseDown
        case (_, .dragged): type = .otherMouseDragged
        case (_, .up): type = .otherMouseUp
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { return }
        event.flags = Self.currentFlags(addingShift: shift)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.dx.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.dy.rounded()))
        // Session level, past HID-level taps of mouse utilities that would
        // otherwise claim synthesized middle-button drags for themselves.
        event.post(tap: .cgSessionEventTap)
    }

    private func postThreeDScroll(x: Int32, y: Int32, phase: ScrollPhase, shift: Bool) {
        guard let event = Self.pixelScrollEvent(x: x, y: y) else { return }
        event.flags = Self.currentFlags(addingShift: shift)
        event.setScrollPhases(scrollPhase: phase, momentumPhase: nil)
        event.post(tap: .cghidEventTap)
    }

    /// Presses or releases Shift for real, so apps that read the keyboard
    /// state rather than event flags see it held for the whole drag.
    private func postShiftKey(down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: down)
        else { return }
        event.type = .flagsChanged
        event.flags = down ? .maskShift : []
        event.post(tap: .cghidEventTap)
    }

    private static func currentFlags(addingShift shift: Bool) -> CGEventFlags {
        var flags = CGEventSource.flagsState(.combinedSessionState)
        if shift { flags.insert(.maskShift) }
        return flags
    }

    private static func dragButton(for output: ThreeDOutput) -> CGMouseButton? {
        switch output {
        case .leftDrag: return .left
        case .rightDrag: return .right
        case .middleDrag, .shiftMiddleDrag: return .center
        case .scroll, .shiftScroll, .pinch, .wheel: return nil
        }
    }

    private static func holdsShift(_ output: ThreeDOutput) -> Bool {
        output == .shiftMiddleDrag || output == .shiftScroll
    }

    private static func isOnScreen(_ point: CGPoint) -> Bool {
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(point, 0, nil, &count)
        return count > 0
    }

    private func triggerGesture(dx: Double, dy: Double) {
        if abs(dx) > abs(dy) {
            // Horizontal
            if dx < 0 {
                // Left: Browser Back (Cmd + [ )
                Self.logger.notice("Gesture Triggered: Browser Back (Left)")
                postKeyboardShortcut(keyCode: 33, flags: .maskCommand) // 33 is '['
            } else {
                // Right: Browser Forward (Cmd + ] )
                Self.logger.notice("Gesture Triggered: Browser Forward (Right)")
                postKeyboardShortcut(keyCode: 30, flags: .maskCommand) // 30 is ']'
            }
        } else {
            // Vertical
            if dy < 0 {
                // Up: Mission Control
                Self.logger.notice("Gesture Triggered: Mission Control (Up)")
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") {
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                }
            } else {
                // Down: Show Desktop (Cmd + Option + Control + D)
                Self.logger.notice("Gesture Triggered: Show Desktop (Down)")
                // F11 (103) is often blocked by macOS or Karabiner.
                // We send a reliable complex shortcut (Cmd+Opt+Ctrl+D, keyCode: 2) instead.
                postKeyboardShortcut(keyCode: 2, flags: [.maskCommand, .maskAlternate, .maskControl])
            }
        }
    }

    private func postKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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
