//
//  SettingsPages.swift
//  BallGesture
//
//  One view per settings page.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - General

struct GeneralSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = GestureEngine.shared
    @ObservedObject private var status = SystemStatus.shared
    @State private var resetCommandCopied = false

    var body: some View {
        SettingsPageScaffold(page: .general) {
            SettingsGroup {
                ToggleRow(
                    title: "Enabled",
                    subtitle: "Turns every mode and the mouse layer on or off.",
                    isOn: $settings.isEnabled
                )
            }

            SettingsGroup(title: "Accessibility") {
                SettingsRow(title: AccessibilityStatus.text(engine.tapStatus, trusted: status.isAccessibilityTrusted)) {
                    Circle()
                        .fill(AccessibilityStatus.color(engine.tapStatus))
                        .frame(width: 8, height: 8)
                }
                if engine.tapStatus != .running {
                    SettingsDivider()
                    accessibilityHelp
                }
            }

            SettingsGroup(title: "Settings File", footer: "Edits to the file apply right away.") {
                SettingsRow(title: (AppSettings.configFileURL.path as NSString).abbreviatingWithTildeInPath) {
                    HStack(spacing: 14) {
                        TextButton(title: "Show in Finder", color: Palette.white) {
                            NSWorkspace.shared.activateFileViewerSelecting([AppSettings.configFileURL])
                        }
                        TextButton(title: "Open") {
                            NSWorkspace.shared.open(AppSettings.configFileURL)
                        }
                    }
                }
                if let message = settings.configErrorMessage {
                    SettingsDivider()
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            if status.isAccessibilityTrusted {
                // System Settings can show the switch on while the grant is stale: a reinstall
                // replaces the bundle at the same path and the old grant doesn't carry over.
                Text("System Settings may show the switch on although the grant is stale, which happens after reinstalling. If the status doesn't turn green, reset the permission in Terminal, then grant it again.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dimWhite)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AccessibilityPermission.resetCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.brightWhite)
                    .textSelection(.enabled)
                HStack(spacing: 14) {
                    TextButton(title: resetCommandCopied ? "Copied" : "Copy Command") {
                        AccessibilityPermission.copyResetCommandToClipboard()
                        resetCommandCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { resetCommandCopied = false }
                    }
                    TextButton(title: "Open Accessibility Settings", color: Palette.white) {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            } else {
                Text("Grant access in System Settings. BallGesture starts working as soon as it is granted.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dimWhite)
                    .fixedSize(horizontal: false, vertical: true)
                TextButton(title: "Open Accessibility Settings") {
                    AccessibilityPermission.requestIfNeeded()
                    AccessibilityPermission.openSystemSettings()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// The one-line status shared by the menu panel and the General page.
enum AccessibilityStatus {
    static func color(_ status: TapStatus) -> Color {
        switch status {
        case .running: return Palette.green
        case .retrying: return Palette.yellow
        case .notStarted: return Palette.red
        }
    }

    static func text(_ status: TapStatus, trusted: Bool) -> String {
        switch status {
        case .running: return "Accessibility access granted"
        case .retrying: return "Accessibility access needed"
        case .notStarted: return trusted ? "Access granted, but not running" : "Accessibility access needed"
        }
    }
}

// MARK: - Scroll, Zoom, Gesture

struct ScrollSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsPageScaffold(page: .scroll) {
            SettingsGroup(footer: "Hold the key and roll the ball to scroll.") {
                KeyRow(
                    title: "Trigger Key",
                    target: .scrollTrigger,
                    keyName: KeyCodeNaming.displayName(for: settings.scrollTriggerKeyCode)
                )
            }
            SettingsGroup {
                ToggleRow(title: "Natural Scrolling", subtitle: "Content follows the ball.", isOn: $settings.naturalScrollDirection)
                SettingsDivider()
                SliderRow(title: "Sensitivity", value: $settings.scrollSensitivity, range: 0.1...5.0, format: SliderRow.multiplier)
            }
            SettingsGroup {
                ToggleRow(title: "Momentum", subtitle: "Keeps scrolling after a flick.", isOn: $settings.momentumScrollingEnabled)
                SettingsDivider()
                SliderRow(title: "Momentum Strength", value: $settings.momentumStrength, range: 0...1) {
                    "\(Int(($0 * 100).rounded()))%"
                }
                .disabled(!settings.momentumScrollingEnabled)
                .opacity(settings.momentumScrollingEnabled ? 1 : 0.4)
            }
        }
    }
}

struct ZoomSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsPageScaffold(page: .zoom) {
            SettingsGroup(footer: "Hold the key and roll the ball up or down to zoom.") {
                KeyRow(
                    title: "Trigger Key",
                    target: .zoomTrigger,
                    keyName: KeyCodeNaming.displayName(for: settings.zoomTriggerKeyCode)
                )
            }
            SettingsGroup {
                SettingsRow(title: "Method", subtitle: "What the app receives.") {
                    DropdownButton(
                        title: settings.zoomMethod.displayName,
                        options: ZoomMethod.allCases.map { DropdownOption(id: $0.rawValue, title: $0.displayName) },
                        selectedID: settings.zoomMethod.rawValue
                    ) { id in
                        if let method = ZoomMethod(rawValue: id) { settings.zoomMethod = method }
                    }
                }
                SettingsDivider()
                SliderRow(title: "Sensitivity", value: $settings.zoomSensitivity, range: 0.1...5.0, format: SliderRow.multiplier)
            }
        }
    }
}

struct GestureSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsPageScaffold(page: .gesture) {
            SettingsGroup(footer: "Hold the key and roll the ball: left for Back, right for Forward, up for Mission Control, down for Show Desktop.") {
                KeyRow(
                    title: "Trigger Key",
                    target: .gestureTrigger,
                    keyName: KeyCodeNaming.displayName(for: settings.gestureTriggerKeyCode)
                )
            }
            SettingsGroup {
                SliderRow(title: "Trigger Distance", value: $settings.gestureDistance, range: 10...200, step: 10) {
                    "\(Int($0)) px"
                }
            }
        }
    }
}

// MARK: - CAD

struct CADSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var model: SettingsModel
    /// Bundle ID of the app whose outputs are shown; empty for the default set.
    @State private var selectedApp = ""
    @Namespace private var appHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageScaffold(page: .cad) {
            SettingsGroup(title: "Trigger Keys", footer: "Hold a key and roll the ball to pan, zoom or rotate the view in 3D apps.") {
                ForEach(Array(ThreeDAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { SettingsDivider() }
                    KeyRow(
                        title: action.displayName,
                        target: .threeDTrigger(action),
                        keyName: KeyCodeNaming.displayName(for: settings.threeDTriggerKeyCode(for: action))
                    )
                }
                SettingsDivider()
                SliderRow(title: "Sensitivity", value: $settings.threeDSensitivity, range: 0.1...5.0, format: SliderRow.multiplier)
            }

            appsGroup

            SettingsGroup(title: "Output in \(selectedAppName)") {
                ForEach(Array(ThreeDAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { SettingsDivider() }
                    outputRow(action)
                }
                if let reversesShiftScroll = reversesShiftScrollBinding {
                    SettingsDivider()
                    ToggleRow(
                        title: "Reverse Shift + Trackpad Scroll",
                        subtitle: "For apps that pan the wrong way with Shift and two fingers.",
                        isOn: reversesShiftScroll
                    )
                }
            }
        }
    }

    private var appsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.dimWhite)
                Spacer()
                AddAppButton(added: Set(settings.threeDAppProfiles.map(\.bundleID)), onAdd: addApp)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 2) {
                appRow(
                    bundleID: "",
                    name: "All Other Apps",
                    icon: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) ?? NSImage()
                )
                ForEach(settings.threeDAppProfiles) { app in
                    appRow(bundleID: app.bundleID, name: AppInfo.name(for: app.bundleID), icon: AppInfo.icon(for: app.bundleID))
                }
            }
            .padding(5)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            Text("Each app can send its own output. Apps not listed use All Other Apps.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.dimWhite)
                .padding(.horizontal, 4)
        }
    }

    private func appRow(bundleID: String, name: String, icon: NSImage) -> some View {
        let isSelected = selectedApp == bundleID
        return HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Palette.brightWhite : Palette.white)
            Spacer()
            if !bundleID.isEmpty {
                Button {
                    removeApp(bundleID)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Palette.dimWhite)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.selection)
                    .matchedGeometryEffect(id: "cadAppSelection", in: appHighlight)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(bundleID) }
    }

    private func outputRow(_ action: ThreeDAction) -> some View {
        let binding = selectedProfile.wrappedValue[action]
        return SettingsRow(
            title: action.displayName,
            subtitle: KeyCodeNaming.displayName(for: settings.threeDTriggerKeyCode(for: action))
        ) {
            HStack(spacing: 12) {
                DropdownButton(
                    title: binding.output.displayName,
                    options: ThreeDOutput.allCases.map { DropdownOption(id: $0.rawValue, title: $0.displayName) },
                    selectedID: binding.output.rawValue,
                    width: 170
                ) { id in
                    guard let output = ThreeDOutput(rawValue: id) else { return }
                    selectedProfile.wrappedValue[action].output = output
                }
                HStack(spacing: 6) {
                    Text("Reverse")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.dimWhite)
                    Toggle("", isOn: Binding(
                        get: { selectedProfile.wrappedValue[action].reversed },
                        set: { selectedProfile.wrappedValue[action].reversed = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
        }
    }

    private var selectedAppName: String {
        selectedApp.isEmpty ? "All Other Apps" : AppInfo.name(for: selectedApp)
    }

    /// The profile being edited: the selected app's override, or the default set.
    private var selectedProfile: Binding<ThreeDProfile> {
        let settings = settings
        let bundleID = selectedApp
        return Binding(
            get: { settings.threeDAppProfiles.first { $0.bundleID == bundleID }?.profile ?? settings.threeDDefaultProfile },
            set: { profile in
                if let index = settings.threeDAppProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                    settings.threeDAppProfiles[index].profile = profile
                } else {
                    settings.threeDDefaultProfile = profile
                }
            }
        )
    }

    /// The selected app's switch; nil while All Other Apps is selected,
    /// because the switch belongs to one app, never to the default set.
    private var reversesShiftScrollBinding: Binding<Bool>? {
        let bundleID = selectedApp
        guard settings.threeDAppProfiles.contains(where: { $0.bundleID == bundleID }) else { return nil }
        let settings = settings
        return Binding(
            get: { settings.threeDAppProfiles.first { $0.bundleID == bundleID }?.reversesShiftTrackpadScroll ?? false },
            set: { newValue in
                if let index = settings.threeDAppProfiles.firstIndex(where: { $0.bundleID == bundleID }) {
                    settings.threeDAppProfiles[index].reversesShiftTrackpadScroll = newValue
                }
            }
        )
    }

    private func select(_ bundleID: String) {
        withAnimation(Motion.selection(reduceMotion: reduceMotion)) { selectedApp = bundleID }
    }

    private func addApp(_ bundleID: String) {
        settings.addThreeDAppProfile(bundleID: bundleID)
        select(bundleID)
    }

    private func removeApp(_ bundleID: String) {
        if selectedApp == bundleID { select("") }
        settings.threeDAppProfiles.removeAll { $0.bundleID == bundleID }
    }
}

/// Drops the running apps to pick from, and a way to pick from /Applications.
/// Running apps come first because some apps start from a launcher in /Applications whose
/// bundle ID differs from the process that ends up frontmost.
private struct AddAppButton: View {
    let added: Set<String>
    let onAdd: (String) -> Void

    @EnvironmentObject private var model: SettingsModel
    @State private var frame: CGRect = .zero
    @State private var isHovered = false

    private static let chooseID = "\u{0}choose"

    var body: some View {
        Text("Add App")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.green.opacity(isHovered ? 1 : 0.85))
            .underline(isHovered, color: Palette.green.opacity(0.5))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DropdownSpace.name)) } action: { frame = $0 }
            .onPressDown(open)
    }

    private func open() {
        AppSettings.shared.cancelCapture()
        let running = runningApps.map {
            DropdownOption(id: $0.bundleIdentifier ?? "", title: $0.localizedName ?? $0.bundleIdentifier ?? "", icon: $0.icon)
        }
        let choose = DropdownOption(
            id: Self.chooseID,
            title: "Choose from Applications…",
            icon: NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        )
        let width: CGFloat = 240
        // Right-aligned with the button, which sits at the right end of the row.
        let anchor = CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        model.dropdown = DropdownRequest(anchor: anchor, width: width, options: running + [choose], selectedID: nil) { id in
            if id == Self.chooseID {
                chooseApplications()
            } else {
                onAdd(id)
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        var seen = added
        seen.insert(Bundle.main.bundleIdentifier ?? "")
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else { return false }
                return seen.insert(bundleID).inserted
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        let add: ([URL]) -> Void = { urls in
            for url in urls {
                if let bundleID = Bundle(url: url)?.bundleIdentifier { onAdd(bundleID) }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { add(panel.urls) }
            }
        } else if panel.runModal() == .OK {
            add(panel.urls)
        }
    }
}

enum AppInfo {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Mouse Layer

struct MouseLayerSettingsPage: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = GestureEngine.shared
    @ObservedObject private var status = SystemStatus.shared

    private static let anyDeviceID = ""

    var body: some View {
        SettingsPageScaffold(page: .mouseLayer) {
            SettingsGroup {
                ToggleRow(
                    title: "Auto Mouse Layer",
                    subtitle: "While the pointer moves, these keys click instead of typing.",
                    isOn: $settings.autoMouseEnabled
                )
            }

            Group {
                SettingsGroup {
                    SettingsRow(title: "Device", subtitle: "Movement from this device turns the layer on.") {
                        DropdownButton(
                            title: deviceTitle(settings.autoMouseDevice),
                            options: deviceOptions,
                            selectedID: settings.autoMouseDevice?.id ?? Self.anyDeviceID,
                            width: 210
                        ) { id in
                            settings.autoMouseDevice = deviceChoices.first { $0.id == id }
                        }
                    }
                    if engine.pointingMonitorNeedsAccess {
                        SettingsDivider()
                        SettingsRow(title: "Watching one device needs Input Monitoring access.") {
                            TextButton(title: "Open Settings") {
                                PointingDeviceMonitor.openInputMonitoringSettings()
                            }
                        }
                    }
                    SettingsDivider()
                    SliderRow(title: "Stays On After Moving", value: $settings.autoMouseTimeout, range: 0.2...2.0, step: 0.1) {
                        "\(Int(($0 * 1000).rounded())) ms"
                    }
                }

                SettingsGroup(title: "Click Keys") {
                    ForEach(Array(AutoMouseButton.allCases.enumerated()), id: \.element) { index, button in
                        if index > 0 { SettingsDivider() }
                        KeyRow(
                            title: button.displayName,
                            target: .autoMouseButton(button),
                            keyName: KeyCodeNaming.displayName(for: settings.autoMouseKeyCode(for: button))
                        )
                    }
                }

                SettingsGroup(
                    title: "Hold Keys",
                    footer: "For keys that send a modifier when held, such as home row mods: holding sends that modifier, which then holds the button down to drag."
                ) {
                    ForEach(Array(AutoMouseButton.allCases.enumerated()), id: \.element) { index, button in
                        if index > 0 { SettingsDivider() }
                        let keyCode = settings.autoMouseHoldKeyCodes[button]
                        KeyRow(
                            title: button.displayName,
                            target: .autoMouseHoldKey(button),
                            keyName: keyCode.map(KeyCodeNaming.displayName(for:)) ?? "None",
                            onClear: keyCode == nil ? nil : { settings.clearAutoMouseHoldKey(for: button) }
                        )
                    }
                }
            }
            .disabled(!settings.autoMouseEnabled)
            .opacity(settings.autoMouseEnabled ? 1 : 0.4)
        }
    }

    /// Connected devices, plus the chosen one while it is disconnected.
    private var deviceChoices: [PointingDeviceID] {
        guard let chosen = settings.autoMouseDevice, !status.pointingDevices.contains(chosen) else {
            return status.pointingDevices
        }
        return status.pointingDevices + [chosen]
    }

    private var deviceOptions: [DropdownOption] {
        [DropdownOption(id: Self.anyDeviceID, title: "Any Pointer")]
            + deviceChoices.map { DropdownOption(id: $0.id, title: deviceTitle($0)) }
    }

    private func deviceTitle(_ device: PointingDeviceID?) -> String {
        guard let device else { return "Any Pointer" }
        return status.pointingDevices.contains(device) ? device.product : "\(device.product) (not connected)"
    }
}
