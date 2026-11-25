// Keyboard tap: catches trigger + letter, switches the layout and swallows the key so it isn't typed.
// Needs Accessibility (an active event tap).

import AppKit

extension AppDelegate {
    func installKeyboardTap() {
        if !AXIsProcessTrusted() { requestAccessibility() }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                let app = Unmanaged<AppDelegate>.fromOpaque(context!).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { app.handleKey(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            // not trusted yet — try again once the user flips the switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.installKeyboardTap() }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Lingo: shortcuts active")
    }

    /// Returns true when the event should be swallowed.
    private func handleKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp { return swallowedKeyUps.remove(keyCode) != nil }
        if settingsWindow?.isKeyWindow == true && NSApp.isActive { return false }   // Settings may be recording a key
        guard let lang = matchShortcut(flags: event.flags, keyCode: keyCode, trigger: .current, langs: store.langs) else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { activate(lang.sourceID) }
        swallowedKeyUps.insert(keyCode)
        return true
    }
}
