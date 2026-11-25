// App delegate: menu bar item and its menu, settings window, single-instance handling.

import AppKit
import SwiftUI
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = Store.shared
    var settingsWindow: NSWindow?
    weak var updateItem: NSMenuItem?

    // keyboard tap state (see App+KeyboardTap)
    var tap: CFMachPort?
    var swallowedKeyUps: Set<Int64> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard becomeSingleInstance() else { return }
        installEditMenu()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        store.onChange = { [weak self] in self?.refresh() }
        refresh()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        installKeyboardTap()
        Updater.shared.isIdle = { [weak self] in !(self?.settingsWindow?.isVisible ?? false) }
        Updater.shared.onChange = { [weak self] in self?.showUpdateState() }
        Updater.shared.start()
    }

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
            MainActor.assumeIsolated { self?.openSettings() }
        }
        return true
    }

    /// Redraws the menu bar glyph for the active layout.
    func refresh() {
        let id = currentSourceID()
        if store.current != id { store.current = id }
        let index = store.langs.firstIndex { $0.sourceID == id }
        let code = index.map { store.langs[$0].code } ?? suggestCode(id)
        statusItem.button?.image = glyph(code: code, count: store.langs.count, current: index)
        statusItem.button?.toolTip = sourceName(id)
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
