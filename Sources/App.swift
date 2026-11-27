// App delegate: menu bar item and its menu, settings window, single-instance handling.

import AppKit
import SwiftUI
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = Store.shared
    var settingsWindow: NSWindow?
    weak var updateItem: NSMenuItem?
    var drawn = ""                     // what the menu bar glyph shows now
    var pollCount = 0
    var pollTimer: Timer?
    var shownPosition: Double?             // where the indicator is drawn
    var indicatorAnimation: Timer?

    // keyboard tap state (see App+KeyboardTap)
    var tap: CFMachPort?
    var swallowedKeyUps: Set<Int64> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard becomeSingleInstance() else { return }
        Appearance.apply()
        installEditMenu()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        store.onChange = { [weak self] in self?.refresh() }
        refresh()
        watchLayouts()
        NSLog("Lingo: launched \(Updater.currentVersion)")
        if Self.e2e { return }               // end-to-end test copy: no keyboard tap, prompts or update checks
        installKeyboardTap()
        Updater.shared.isIdle = { [weak self] in !(self?.settingsWindow?.isVisible ?? false) }
        Updater.shared.onChange = { [weak self] in self?.showUpdateState() }
        Updater.shared.start()
    }

    /// Keeps the icon and the list in step with macOS, however the layout is switched.
    func watchLayouts() {
        // macOS posts "layout changed" a moment before the new layout is reported as current — reading it right
        // away gives the previous one, so the icon lagged a step behind. Look again shortly after, and keep a
        // once-a-second check in case macOS is slower still or a notification is missed.
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        center.addObserver(forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.followSystem(); self?.refreshSoon() }
        }
        pollTimer?.invalidate()
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pollCount += 1
                if self.pollCount % 3 == 0 { self.store.followSystem() }
                self.refresh()
            }
        }
        poll.tolerance = 0.3
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
    }

    /// Set by scripts/e2e.sh, which runs a renamed copy next to the real app.
    static let e2e = ProcessInfo.processInfo.environment["LINGO_E2E"] == "1"

    /// Opening Lingo again (Finder, Spotlight) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return false
    }

    /// If Lingo is already running, ask that copy to show Settings and quit this one.
    private func becomeSingleInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return true }
        let center = DistributedNotificationCenter.default()
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            center.postNotificationName(.init(id + ".open"), object: nil, deliverImmediately: true)
            exit(0)
        }
        center.addObserver(forName: .init(id + ".open"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if Self.e2e { NSLog("Lingo: asked to open"); return }
                self?.openSettings()
            }
        }
        return true
    }

    /// Redraws the menu bar glyph for the active layout (only when something changed).
    /// Moving to another language in the same list slides the indicator there instead of jumping.
    func refresh() {
        let id = currentSourceID()
        if store.current != id { store.current = id }
        let index = store.langs.firstIndex { $0.sourceID == id }
        let code = index.map { store.langs[$0].code } ?? suggestCode(id)
        let count = store.langs.count, style = Indicator.current
        let shown = "\(code)|\(count)|\(index ?? -1)|\(style.rawValue)"
        guard shown != drawn else { return }
        let sameList = drawn.split(separator: "|").dropFirst().first == Substring("\(count)") && drawn.hasSuffix("|\(style.rawValue)")
        drawn = shown
        statusItem.button?.toolTip = sourceName(id)
        let to = index.map(Double.init)
        let from = shownPosition
        shownPosition = to
        indicatorAnimation?.invalidate()
        guard sameList, let from, let to, from != to, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            statusItem.button?.image = glyph(code: code, count: count, current: to, style: style)
            return
        }
        let start = Date(), duration = 0.22
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                let eased = 1 - pow(1 - t, 3)
                self?.statusItem.button?.image = glyph(code: code, count: count, current: from + (to - from) * eased, style: style)
                if t >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        indicatorAnimation = timer
    }

    /// Now, and again a moment later — macOS reports the new layout with a small delay.
    func refreshSoon() {
        refresh()
        for delay in [0.05, 0.15, 0.4, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = currentSourceID()
        let trigger = Trigger.current
        for (index, lang) in store.langs.enumerated() {
            let item = NSMenuItem(title: sourceName(lang.sourceID), action: #selector(pick(_:)), keyEquivalent: "")
            item.attributedTitle = menuTitle(sourceName(lang.sourceID), hint: "\(trigger.keycap) \(keyLetters[lang.key] ?? "?")")
            item.target = self
            item.tag = index
            item.state = lang.sourceID == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(item("Allow Accessibility…", "hand.raised", #selector(requestAccessibility)))
        }
        menu.addItem(item("Settings…", "gearshape", #selector(openSettings), key: ","))
        let update = item("", "", #selector(checkForUpdates))
        updateItem = update
        showUpdateState()
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = item("Quit Lingo", "power", #selector(NSApplication.terminate(_:)), key: "q")
        quit.target = NSApp
        menu.addItem(quit)
        Updater.shared.refreshIfStale()   // the line updates in place while the menu is open
    }

    private func item(_ title: String, _ symbol: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.showsImage()
        return item
    }

    @objc func checkForUpdates() { Updater.shared.menuAction() }

    /// "Lingo Is Up to Date · 1.0.0 is the latest version", "Update to Lingo 1.1…", "Checking…".
    func showUpdateState() {
        guard let updateItem else { return }
        let line = Updater.menuLine(Updater.shared.state, version: Updater.currentVersion, enabled: Updater.enabled)
        updateItem.title = line.title
        if #available(macOS 14.4, *) { updateItem.subtitle = line.subtitle } else { updateItem.toolTip = line.subtitle }
        updateItem.isEnabled = line.enabled
        let config = line.highlighted ? NSImage.SymbolConfiguration(paletteColors: [.white, .controlAccentColor]) : NSImage.SymbolConfiguration()
        updateItem.image = NSImage(systemSymbolName: line.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        updateItem.showsImage()
    }

    /// "Deutsch          fn D" — the hint is text: fn can't be a real key equivalent in an app menu.
    private func menuTitle(_ title: String, hint: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 190)]
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title + "\t", attributes: [.font: font, .paragraphStyle: paragraph])
        text.append(NSAttributedString(string: hint, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]))
        return text
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard store.langs.indices.contains(sender.tag) else { return }
        activate(store.langs[sender.tag].sourceID)
    }

    @objc func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "Lingo"
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension NSMenuItem {
    /// macOS 27 hides menu item images unless asked. Set by name, so it builds with older SDKs (CI) too.
    func showsImage() {
        if responds(to: NSSelectorFromString("setPreferredImageVisibility:")) { setValue(1, forKey: "preferredImageVisibility") }   // .visible
    }
}
