//
//  MiniMouseApp.swift
//  MiniMouse
//
//  Declares only a MenuBarExtra scene (no WindowGroup), so the app lives in the
//  menu bar and never opens a window. Combined with LSUIElement = YES in Info.plist
//  it also never appears in the Dock or Cmd-Tab.
//
//  Created by Mark Tomlin on 9/2/26.
//

import SwiftUI
import ServiceManagement   // SMAppService: registers the app as a Login Item

@main
struct MiniMouseApp: App {
    @State private var mapper = ButtonMapper()
    // Mirrors the system Login Item registration. Kept in @State rather than a computed
    // Binding because SwiftUI re-invokes a menu Toggle's setter when the menu is rebuilt,
    // which silently re-registered the item right after the user unchecked it.
    @State private var launchAtLogin = Self.isLoginItem

    private static var isLoginItem: Bool { SMAppService.mainApp.status == .enabled }

    // Registers or unregisters the app as a Login Item (System Settings > General > Login Items).
    private func setLaunchAtLogin(_ on: Bool) {
        guard on != Self.isLoginItem else { return }   // already in sync; nothing to do
        do {
            if on { try SMAppService.mainApp.register() }
            else   { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MiniMouse: could not change Launch at Login: \(error)")
            launchAtLogin = Self.isLoginItem   // revert the toggle to reality
        }
    }

    var body: some Scene {
        MenuBarExtra("MiniMouse", systemImage: "computermouse") {
            if mapper.needsAccessibility {
                Button("Grant Accessibility access…") { mapper.requestAccessibility() }
                Divider()
            }
            Toggle("Enabled", isOn: $mapper.enabled)
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                .onAppear { launchAtLogin = Self.isLoginItem }   // pick up changes made in System Settings
            Divider()
            Button("Quit MiniMouse") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
