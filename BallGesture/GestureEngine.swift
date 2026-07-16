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
                if momentumActive {
                    stopMomentum(reason: "new Scroll Mode started")
                }
                cancelFlickDetection()
                scrollActive = true
                isFirstScrollEventOfDrag = true
                resetScrollVelocityTracking()
                disassociateCursor()
                Self.logger.notice("Scroll Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, scrollActive {
                scrollActive = false
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

        if keyCode == settings.gestureTriggerKeyCode {
            if type == .keyDown, !gestureActive {
                gestureActive = true
                gestureAccumulatedX = 0.0
                gestureAccumulatedY = 0.0
                hasTriggeredGesture = false
                disassociateCursor()
                Self.logger.notice("Gesture Mode STARTED (keyCode=\(keyCode, privacy: .public)).")
            } else if type == .keyUp, gestureActive {
                gestureActive = false
                reassociateCursor()
                Self.logger.notice("Gesture Mode ENDED (keyCode=\(keyCode, privacy: .public)).")
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func handleMouseMoved(event: CGEvent) -> Unmanaged<CGEvent>? {
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
                // swipe naturally carries some diagonal drift, and deciding
                // the direction at the instant either axis crossed the
                // threshold made ~45° inputs resolve to the wrong gesture
                // (Back turning into Mission Control). Ambiguous diagonal
                // input now just waits for more movement instead.
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
        let timer = Timer(timeInterval: Self.flickIdleDetectionInterval, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.checkForFlick()
            }
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

        let rawScrollY = deltaY * sensitivity * sign
        let rawScrollX = deltaX * sensitivity * sign
        updateScrollVelocity(scrollX: rawScrollX, scrollY: rawScrollY)

        let scrollY = Int32(rawScrollY.rounded())
        let scrollX = Int32(rawScrollX.rounded())
        guard scrollY != 0 || scrollX != 0 else { return }

        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: scrollY,
            wheel2: scrollX,
            wheel3: 0
        ) else { return }

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
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ) else { return }

        event.setScrollPhases(scrollPhase: scrollPhase, momentumPhase: momentumPhase)
        event.post(tap: tap)
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

        let timer = Timer(timeInterval: Self.momentumTickInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.momentumTick()
            }
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
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: scrollY,
            wheel2: scrollX,
            wheel3: 0
        ) else { return }

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
