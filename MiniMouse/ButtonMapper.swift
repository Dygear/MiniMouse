//
//  ButtonMapper.swift
//  MiniMouse
//
//  CGEvent (Core Graphics event) tap that remaps Logitech MX Master 4
//  side buttons to Space switching, Mission Control and App Exposé by injecting the stock
//  Ctrl+Arrow shortcuts. Installs the tap once Accessibility access is granted, polling
//  until it is so no relaunch is needed after the permission prompt.
//
//  Created by Mark Tomlin on 9/2/26.
//

// ButtonMapper.swift — CGEvent (Core Graphics event) tap that remaps Logitech MX Master 4
// side buttons to Space switching, Mission Control and App Exposé by injecting the stock
// Ctrl+Arrow shortcuts. Installs the tap once Accessibility access is granted, polling
// until it is so no relaunch is needed after the permission prompt.

import AppKit
import Carbon.HIToolbox   // kVK_* virtual key codes

@Observable
final class ButtonMapper {
    // Button numbers as macOS reports them (0 = left, 1 = right, 2 = middle).
    static let backMost: Int64 = 3      // -> left Space
    static let middle: Int64 = 4        // -> right Space
    static let forwardMost: Int64 = 5   // -> App Exposé (kVK_F11 without .maskControl gives Show Desktop)
    static let thumbPad: Int64 = 6      // -> Mission Control

    var enabled = true {
        didSet { if let t = tap { CGEvent.tapEnable(tap: t, enable: enabled) } }
    }
    private(set) var needsAccessibility = false
    private var tap: CFMachPort?
    private var retry: Timer?

    init() { install() }

    // Shows the system Accessibility prompt; install() keeps polling until it's granted.
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func install() {
        guard AXIsProcessTrusted() else {
            needsAccessibility = true
            if retry == nil {
                requestAccessibility()
                retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.install() }
            }
            return
        }
        retry?.invalidate(); retry = nil
        needsAccessibility = false

        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()   // lets the C callback find self
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback, userInfo: refcon) else { return }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: enabled)
    }

    // Returns nil to swallow the event so no app ever sees the raw button press.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap it thinks is hung; just turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: enabled) }
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        switch button {
        case Self.backMost, Self.middle, Self.forwardMost, Self.thumbPad:
            if type == .otherMouseDown {   // act on press, swallow both press and release
                switch button {
                case Self.backMost:    press(kVK_LeftArrow,  flags: .maskControl)
                case Self.middle:      press(kVK_RightArrow, flags: .maskControl)
                case Self.forwardMost: press(kVK_DownArrow,  flags: .maskControl)
                default:               press(kVK_UpArrow,    flags: .maskControl)
                }
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // Post a key press + release with modifiers (e.g. Ctrl+Left = "move left a Space").
    //
    // The Spaces / Mission Control hotkeys are matched by WindowServer, not by an app, and it
    // only recognises them when the sequence looks like a real keyboard: a separate modifier
    // key-down first, then the arrow key carrying the Fn + numeric-pad flags a physical arrow
    // key has, then the releases. Setting `.maskControl` on the arrow event alone is ignored.
    // The events are also posted after the tap callback returns; posting from inside it is
    // unreliable and can get the tap disabled for taking too long.
    private func press(_ key: Int, flags: CGEventFlags) {
        DispatchQueue.main.async {
            let src = CGEventSource(stateID: .hidSystemState)
            let isArrow = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(key)
            let keyFlags: CGEventFlags = isArrow ? flags.union([.maskSecondaryFn, .maskNumericPad]) : flags
            let modifiers = Self.modifierKeys.filter { flags.contains($0.flag) }

            var sequence: [CGEvent] = []
            var held: CGEventFlags = []
            for m in modifiers {   // modifiers down, accumulating flags like a real keyboard would
                held.insert(m.flag)
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: m.code, keyDown: true) else { return }
                e.flags = held
                sequence.append(e)
            }
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: true),
                  let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: false) else { return }
            down.flags = keyFlags
            up.flags = keyFlags
            sequence.append(down)
            sequence.append(up)
            for m in modifiers.reversed() {   // modifiers up
                held.remove(m.flag)
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: m.code, keyDown: false) else { return }
                e.flags = held
                sequence.append(e)
            }
            for e in sequence { e.post(tap: .cghidEventTap) }
        }
    }

    // Modifier flag -> the virtual key that produces it, for synthesising modifier key events.
    private static let modifierKeys: [(flag: CGEventFlags, code: CGKeyCode)] = [
        (.maskControl,   CGKeyCode(kVK_Control)),
        (.maskAlternate, CGKeyCode(kVK_Option)),
        (.maskShift,     CGKeyCode(kVK_Shift)),
        (.maskCommand,   CGKeyCode(kVK_Command)),
    ]
}

// C-convention trampoline: CGEventTapCallBack can't capture Swift context, so self rides in refcon.
private func callback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                      refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<ButtonMapper>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
