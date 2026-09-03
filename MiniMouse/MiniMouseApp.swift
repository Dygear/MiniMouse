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

@main
struct MiniMouseApp: App {
    @State private var mapper = ButtonMapper()

    var body: some Scene {
        MenuBarExtra("MiniMouse", systemImage: "computermouse") {
            if mapper.needsAccessibility {
                Button("Grant Accessibility access…") { mapper.requestAccessibility() }
                Divider()
            }
            Toggle("Enabled", isOn: $mapper.enabled)
            Divider()
            Button("Quit MiniMouse") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
