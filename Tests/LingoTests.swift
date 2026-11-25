// Lingo tests — compiled together with main.swift (-D TESTING). Run: ./test.sh
import Cocoa
import Carbon

@MainActor func runTests() -> Never {
    UserDefaults.standard.removeObject(forKey: "trigger")
    let en = Lang(sourceID: "com.apple.keylayout.US", code: "EN", key: kVK_ANSI_E)
    let de = Lang(sourceID: "com.apple.keylayout.German-DIN-2137", code: "DE", key: kVK_ANSI_D)
    let uk = Lang(sourceID: "com.apple.keylayout.Ukrainian-PC", code: "UK", key: kVK_ANSI_U)
    let list = [en, de, uk]

    // ───────────────────────── unit
    section("matchShortcut — which key presses switch the language")
    expectEqual(matchShortcut(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: list)?.code, "EN", "fn + E → English")
    expectEqual(matchShortcut(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_D), trigger: .fn, langs: list)?.code, "DE", "fn + D → Deutsch")
    expect(matchShortcut(flags: [], keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: list) == nil, "plain E is typed normally")
    expect(matchShortcut(flags: [.maskSecondaryFn, .maskShift], keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: list) == nil, "fn + ⇧ + E is left alone")
    expect(matchShortcut(flags: [.maskSecondaryFn, .maskCommand], keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: list) == nil, "⌘ + fn + E is left alone")
    expect(matchShortcut(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_Q), trigger: .fn, langs: list) == nil, "fn + an unassigned key is left alone")
    expect(matchShortcut(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: []) == nil, "empty list → nothing to switch")
    expectEqual(matchShortcut(flags: .maskAlternate, keyCode: Int64(kVK_ANSI_D), trigger: .option, langs: list)?.code, "DE", "⌥ trigger: ⌥ + D → Deutsch")
    expect(matchShortcut(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_D), trigger: .option, langs: list) == nil, "⌥ trigger ignores fn + D")
    expectEqual(matchShortcut(flags: [.maskControl, .maskAlternate], keyCode: Int64(kVK_ANSI_U), trigger: .controlOption, langs: list)?.code, "UK", "⌃⌥ trigger: ⌃⌥ + U")
    expect(matchShortcut(flags: .maskControl, keyCode: Int64(kVK_ANSI_U), trigger: .controlOption, langs: list) == nil, "⌃⌥ trigger needs both modifiers")
    expectEqual(matchShortcut(flags: [.maskSecondaryFn, .maskAlphaShift], keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: list)?.code, "EN", "works with Caps Lock on")
    let dup = [en, Lang(sourceID: de.sourceID, code: "DE", key: kVK_ANSI_E)]
    expectEqual(matchShortcut(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_E), trigger: .fn, langs: dup)?.code, "EN", "duplicate key → first in the list wins (UI warns about it)")

    section("Edit shortcuts in text fields")
    installEditMenu()
    let edit = NSApplication.shared.mainMenu?.items.first { $0.submenu?.title == "Edit" }?.submenu
    for (key, action) in [("a", "selectAll:"), ("c", "copy:"), ("v", "paste:"), ("x", "cut:"), ("z", "undo:")] {
        let item = edit?.items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
        expect(item?.action.map(NSStringFromSelector) == action, "⌘\(key.uppercased()) → \(action)")
    }

    section("Trigger")
    expectEqual(Trigger.current, .fn, "default trigger is fn")
    UserDefaults.standard.set("option", forKey: "trigger"); expectEqual(Trigger.current, .option, "saved trigger is read back")
    UserDefaults.standard.set("garbage", forKey: "trigger"); expectEqual(Trigger.current, .fn, "unknown value falls back to fn")
    UserDefaults.standard.removeObject(forKey: "trigger")
    expect(Trigger.allCases.allSatisfy { !$0.keycap.isEmpty && !$0.label.isEmpty && !$0.note.isEmpty }, "every trigger has keycap, label and note")
    expectEqual(Set(Trigger.allCases.map(\.flags.rawValue)).count, Trigger.allCases.count, "triggers have distinct modifier sets")

    section("Key letters")
    expectEqual(keyLetters.count, 36, "A–Z and 0–9 are assignable")
    expectEqual(Set(keyLetters.values).count, 36, "every key has a unique label")
    expectEqual(keyLetters[kVK_ANSI_E], "E", "E key")

    section("Config — saving & loading")
    let data = try? JSONEncoder().encode(list)
    let back = data.flatMap { try? JSONDecoder().decode([Lang].self, from: $0) }
    expectEqual(back ?? [], list, "languages survive a save / load round trip")
    expect((try? JSONDecoder().decode([Lang].self, from: Data("[{\"bad\":1}]".utf8))) == nil, "malformed config is rejected (Store then falls back to the system layouts)")

    section("Codes & names (international)")
    expectEqual(suggestCode("com.apple.keylayout.US"), "EN", "U.S. → EN")
    expectEqual(suggestCode("com.apple.keylayout.German-DIN-2137"), "DE", "German → DE")
    expectEqual(suggestCode("com.apple.keylayout.Ukrainian-PC"), "UK", "Ukrainian → UK (ISO 639-1)")
    expectEqual(suggestCode("com.apple.keylayout.French"), "FR", "French → FR")
    expectEqual(suggestCode("com.apple.keylayout.Spanish"), "ES", "Spanish → ES")
    expectEqual(suggestCode("com.apple.keylayout.Russian"), "RU", "Russian → RU")
    expect(suggestCode("com.example.does-not-exist").count >= 1, "unknown layout still gets a code, no crash")
    expectEqual(languageName("com.apple.keylayout.German-DIN-2137"), "Deutsch", "language names are native (Deutsch)")
    expectEqual(languageName("com.example.unknown"), "com.example.unknown", "unknown layout → its id, no crash")

    section("First run — picks the user's own layouts")
    let first = Store.fromEnabledLayouts()
    expect(!first.isEmpty, "at least one language (\(first.map(\.code).joined(separator: ", ")))")
    expectEqual(Set(first.map(\.key)).count, first.count, "every language gets its own key")
    expect(first.allSatisfy { !$0.code.isEmpty && keyLetters[$0.key] != nil }, "every language has a code and a valid key")
    expect(first.allSatisfy { source($0.sourceID) != nil }, "only layouts that are actually enabled")

    section("Menu bar glyph")
    for n in [0, 1, 3, 6] {
        let img = glyph(code: "EN", count: n, current: n > 0 ? 0 : nil)
        expect(img.size.width > 0 && img.size.height == 18 && img.isTemplate, "\(n) dot(s): valid template image (\(Int(img.size.width))×18)")
    }
    expect(glyph(code: "EN", count: 12, current: 3).size.width >= glyph(code: "EN", count: 3, current: 0).size.width, "many languages → glyph grows to fit the dots")

    // ───────────────────────── integration (real input sources)
    testUpdater()

    section("Switching layouts — real TIS calls")
    let original = currentSourceID()
    let enabled = allKeyboardSources().filter { source($0.id) != nil }
    expect(!original.isEmpty, "current layout is readable (\(original))")
    expect(allKeyboardSources().count > 20, "all installed layouts are listed for the picker (\(allKeyboardSources().count))")
    if let other = enabled.first(where: { $0.id != original }) {
        activate(other.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expectEqual(currentSourceID(), other.id, "activate() switches to \(other.name)")
        activate(original)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expectEqual(currentSourceID(), original, "and back to the original layout")
    } else { skip("layout switching", "only one keyboard layout is enabled") }
    activate("com.example.does-not-exist")
    expectEqual(currentSourceID(), original, "activating a missing layout does nothing (no crash)")

    finish("Lingo")
}
