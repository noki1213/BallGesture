//
//  SettingsView.swift
//  BallGesture
//
//  The settings window: pages listed on the left, the chosen page on the right.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    @Namespace private var sidebarHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)
            ZStack {
                page(model.page)
                    .id(model.page)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .background(
            // Blurs what is behind the window so desktop icons and other windows don't show through
            // sharply under the text; the material stays active so the ground doesn't change with focus.
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.60)
            }
            .ignoresSafeArea()
        )
        .overlay { DropdownLayer(model: model) }
        .coordinateSpace(name: DropdownSpace.name)
        .environmentObject(model)
        .foregroundStyle(Palette.white)
        .tint(Palette.green)
        // Anything still drawn by the system keeps its in-front look when the window is behind.
        .environment(\.controlActiveState, .key)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { page in
                sidebarRow(page)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        // Clears the window buttons, which sit over the top of the sidebar.
        .padding(.top, 48)
        .padding(.bottom, 12)
    }

    private func sidebarRow(_ page: SettingsPage) -> some View {
        let isSelected = model.page == page
        return HStack(spacing: 9) {
            Image(systemName: page.systemImage)
                .font(.system(size: 13))
                .frame(width: 18)
            Text(page.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Palette.brightWhite : Palette.white)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.selection)
                    .matchedGeometryEffect(id: "sidebarSelection", in: sidebarHighlight)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            guard inside, model.page != page else { return }
            model.select(page, animated: true)
        }
        .onTapGesture { model.select(page, animated: true) }
    }

    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralSettingsPage()
        case .scroll: ScrollSettingsPage()
        case .zoom: ZoomSettingsPage()
        case .gesture: GestureSettingsPage()
        case .cad: CADSettingsPage()
        case .mouseLayer: MouseLayerSettingsPage()
        }
    }
}
