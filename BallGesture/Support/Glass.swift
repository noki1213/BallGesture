//
//  Glass.swift
//  BallGesture
//
//  The colours, material and motion shared by the menu panel and the settings window.
//

import AppKit
import SwiftUI

enum Palette {
    static let black = Color(.sRGB, red: 0x26 / 255, green: 0x24 / 255, blue: 0x27 / 255, opacity: 1)
    static let red = Color(.sRGB, red: 0xfc / 255, green: 0x9c / 255, blue: 0x9c / 255, opacity: 1)
    static let green = Color(.sRGB, red: 0x33 / 255, green: 0xA5 / 255, blue: 0xA5 / 255, opacity: 1)
    static let yellow = Color(.sRGB, red: 0xF4 / 255, green: 0xC9 / 255, blue: 0x80 / 255, opacity: 1)
    static let white = Color(.sRGB, red: 0xc4 / 255, green: 0xc4 / 255, blue: 0xc4 / 255, opacity: 1)
    static let brightWhite = Color(.sRGB, red: 0xfc / 255, green: 0xfc / 255, blue: 0xfa / 255, opacity: 1)
    /// Secondary text: the plain white faded, never the dark grey, which sinks into the glass.
    static let dimWhite = white.opacity(0.75)
    static let hairline = Color.white.opacity(0.20)
    static let selection = green.opacity(0.30)
}

enum Motion {
    /// Moving a selection highlight from one row to another.
    static func selection(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.28, bounce: 0)
    }

    /// A sheet materializing: scale, blur and fade driven by one progress value.
    static func materialize(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.30, dampingFraction: 1)
    }
}

struct VisualEffectView: NSViewRepresentable {
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
struct GlassBackground<S: Shape>: View {
    let shape: S

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.50)), in: shape)
            }
        } else {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.50)
            }
            .clipShape(shape)
        }
    }
}
