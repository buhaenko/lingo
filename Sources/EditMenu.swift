// Menu bar apps have no main menu, and without an Edit menu ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z do nothing in text fields.
// This installs a standard (never shown) Edit menu so the usual shortcuts work everywhere.

import AppKit

@MainActor func installEditMenu() {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    let main = NSMenu()
    main.addItem(NSMenuItem())          // app menu slot
    main.addItem(editItem)
    NSApplication.shared.mainMenu = main
}
