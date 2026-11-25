// Lingo — switch keyboard languages with fn + a letter; the current one sits in the menu bar.

import AppKit

#if TESTING
MainActor.assumeIsolated { runTests() }
#else
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
#endif
