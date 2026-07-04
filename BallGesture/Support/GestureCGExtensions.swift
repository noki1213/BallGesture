//
//  GestureCGExtensions.swift
//  BallGesture
//
//  Synthesizes a real trackpad pinch/magnify (NSEventTypeGesture) CGEvent so the
//  system and apps treat mouse movement as an actual pinch gesture, not a
//  keyboard shortcut. This is a private/undocumented Core Graphics event type,
//  so the field numbers below are NOT invented from memory: they are ported
//  from LinearMouse (MIT License, https://github.com/linearmouse/linearmouse),
//  which in turn cites Apple/WebKit's internal SPI header:
//  https://github.com/WebKit/WebKit/blob/main/Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h
//
//  Because this relies on undocumented behavior, it may stop working on a
//  future macOS release. GestureEngine falls back to Ctrl/Cmd+scroll if this
//  does not produce visible zooming.
//

import AppKit
import CoreGraphics

extension CGEventType {
    init?(nsEventType: NSEvent.EventType) {
        self.init(rawValue: UInt32(nsEventType.rawValue))
    }
}

extension CGEventField {
    static let gestureHIDType = Self(rawValue: 110)!
    static let gestureZoomValue = Self(rawValue: 113)!
    static let gesturePhase = Self(rawValue: 132)!
}

/// Phase values for the synthesized gesture sequence.
enum CGSGesturePhase: UInt8 {
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
}

/// IOHIDEventType values relevant to the zoom (pinch) gesture.
private enum IOHIDEventType: UInt32 {
    case zoom = 8
}

/// Builds and posts a single synthetic magnify/pinch CGEvent.
enum PinchGestureEvent {
    /// - Parameters:
    ///   - phase: began / changed / ended / cancelled.
    ///   - magnification: incremental magnification for this event (not cumulative).
    static func post(phase: CGSGesturePhase, magnification: Double, tap: CGEventTapLocation) {
        guard let event = CGEvent(source: nil) else { return }
        guard let gestureType = CGEventType(nsEventType: .gesture) else { return }

        event.type = gestureType
        event.flags = []
        event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoom.rawValue))
        event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
        event.setDoubleValueField(.gestureZoomValue, value: magnification)

        event.post(tap: tap)
    }
}
