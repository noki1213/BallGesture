//
//  ScrollPhaseExtensions.swift
//  BallGesture
//
//  `kCGScrollWheelEventScrollPhase` / `kCGScrollWheelEventMomentumPhase` and
//  their value enums (`CGScrollPhase`, `CGMomentumScrollPhase`) are PUBLIC
//  CoreGraphics API — unlike the pinch/magnify gesture fields in
//  GestureCGExtensions.swift, these are declared directly in the public SDK
//  header CoreGraphics.framework/Headers/CGEventTypes.h:
//
//    kCGScrollWheelEventScrollPhase   = 99
//    kCGScrollWheelEventMomentumPhase = 123
//    CGScrollPhase: began=1 changed=2 ended=4 cancelled=8 mayBegin=128
//    CGMomentumScrollPhase: none=0 begin=1 continue=2 end=3
//
//  Setting these correctly is what makes apps (browsers, editors) treat a
//  synthesized scroll sequence as a real trackpad drag, and a following
//  momentum sequence as real inertial scrolling (natural deceleration,
//  rubber-banding at content edges, etc.) instead of a series of unrelated
//  discrete wheel ticks.
//

import CoreGraphics

enum ScrollPhase: Int64 {
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
}

enum MomentumScrollPhase: Int64 {
    case none = 0
    case begin = 1
    case `continue` = 2
    case end = 3
}

/// `kCGScrollWheelEventIsContinuous = 88` (also public, same header). Real
/// trackpad/momentum scroll events always have this set to 1 — it's what
/// tells apps (and utilities like Mac Mouse Fix) to treat the
/// deltas as pixel-precise continuous scrolling rather than legacy
/// line-based mouse wheel ticks. `CGEvent(scrollWheelEvent2Source:units:.pixel,...)`
/// already sets this automatically, but it's set explicitly here too so it
/// can never silently regress if that construction detail changes.
private let scrollWheelEventIsContinuousField = CGEventField(rawValue: 88)!

extension CGEvent {
    /// Sets both phase fields on a scroll wheel event, plus the continuous
    /// (pixel-precision) flag. Pass `nil` for whichever phase doesn't apply
    /// to this event (a regular drag event has no momentum phase; a
    /// momentum-phase event has no scroll phase).
    func setScrollPhases(scrollPhase: ScrollPhase?, momentumPhase: MomentumScrollPhase?) {
        setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase?.rawValue ?? 0)
        setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase?.rawValue ?? MomentumScrollPhase.none.rawValue)
        setIntegerValueField(scrollWheelEventIsContinuousField, value: 1)
    }
}
