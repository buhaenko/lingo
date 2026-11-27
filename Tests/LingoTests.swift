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

    section("The merged is System Settings → Input Sources — nothing that can't work")
    let usID = "com.apple.keylayout.US", deID = "com.apple.keylayout.German", ukID = "com.apple.keylayout.Ukrainian-PC", abcID = "com.apple.keylayout.ABC"
    let system = enabledKeyboardLayouts()
    expect(!system.isEmpty, "reads the Mac's input sources (\(system.map(sourceName).joined(separator: ", ")))")
    let first = Store.reconciled([], enabled: system)
    expectEqual(first.map(\.sourceID), system, "first launch: exactly the Mac's input sources, in the same order")
    expectEqual(Set(first.map(\.key)).count, first.count, "every one gets its own key")
    expect(first.allSatisfy { !$0.code.isEmpty && $0.code != "?" || sourceName($0.sourceID).isEmpty }, "every one gets a code (\(first.map(\.code).joined(separator: " ")))")
    expect(!system.contains("com.apple.keylayout.2SetHangul"), "layouts macOS can't switch to on their own (Hangul) aren't listed")
    let mine = [Lang(sourceID: deID, code: "GE", key: kVK_ANSI_G), Lang(sourceID: usID, code: "US", key: kVK_ANSI_U)]
    var merged = Store.reconciled(mine, enabled: [usID, deID, ukID])
    expectEqual(merged.map(\.sourceID), [usID, deID, ukID], "same order as macOS (the Globe key cycles in it)")
    expect(merged[0].code == "US" && merged[0].key == kVK_ANSI_U && merged[1].code == "GE", "your own codes and keys are kept")
    expect(merged[2].code == "UK" && merged[2].key != kVK_ANSI_U && merged[2].key != kVK_ANSI_G, "a source added in macOS joins on a free key")
    merged = Store.reconciled(merged, enabled: [usID, ukID])
    expect(!merged.contains { $0.sourceID == deID }, "a source removed in macOS leaves Lingo")
    let stale = [Lang(sourceID: "com.apple.keylayout.3SetHangul", code: "", key: kVK_ANSI_A), Lang(sourceID: "com.apple.keylayout.French", code: "FR", key: kVK_ANSI_F)]
    expectEqual(Store.reconciled(stale, enabled: [usID]).map(\.sourceID), [usID], "old entries that aren't on in macOS (they could never switch) are dropped")
    expectEqual(Store.reconciled(mine, enabled: []), mine, "an empty answer from macOS (a glitch) changes nothing")
    let clash = [Lang(sourceID: usID, code: "EN", key: kVK_ANSI_E), Lang(sourceID: abcID, code: "AB", key: kVK_ANSI_E)]
    expectEqual(Set(Store.reconciled(clash, enabled: [usID, abcID]).map(\.key)).count, 2, "two sources on one key → the second gets a free one")
    let suggested = Store.suggestions(enabled: [usID], preferred: ["uk-UA", "en"])
    expect(suggested.first == ukID && !suggested.contains(usID), "Add language suggests your macOS languages first, never one that's already on (\(suggested.map(suggestCode)))")
    expectEqual(suggestCode("com.apple.keylayout.3SetHangul").isEmpty, false, "a source without a language still gets a code (\(suggestCode("com.apple.keylayout.3SetHangul")))")
    expect(allKeyboardSources().contains { $0.id == "com.apple.inputmethod.Korean.2SetKorean" }, "Korean, Chinese, Japanese input methods can be added")
    expect(!allKeyboardSources().contains { $0.id == "com.apple.keylayout.2SetHangul" }, "but not the bare Hangul layouts that can't be switched to")

    section("Adding and removing goes through macOS — real input sources")
    let irish = "com.apple.keylayout.Irish"
    if source(irish, includeAll: true) != nil && !system.contains(irish) {
        let store = Store()
        expect(store.add(irish), "Add language turns it on in macOS")
        expect(enabledKeyboardLayouts().contains(irish), "it's in System Settings → Input Sources now")
        expect(store.langs.contains { $0.sourceID == irish }, "and in Lingo, on its own key")
        activate(irish)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        expectEqual(currentSourceID(), irish, "fn + its key switches to it")
        expect(store.remove(irish), "− turns it off in macOS")
        expect(!enabledKeyboardLayouts().contains(irish), "gone from System Settings")
        expect(!store.langs.contains { $0.sourceID == irish }, "and from Lingo")
        expect(currentSourceID() != irish, "if it was active, macOS moved to another one first")
        expectEqual(enabledKeyboardLayouts(), system, "the Mac's input sources are exactly as before the test")
    } else { skip("add/remove in macOS", "Irish is already on, or not installed") }
    let before = enabledKeyboardLayouts()
    activate("com.apple.keylayout.3SetHangul")
    activate("com.apple.keylayout.Irish")
    expectEqual(enabledKeyboardLayouts(), before, "switching never turns sources on behind your back")
    if before.count == 1 { expect(!Store().remove(before[0]), "the last input source can't be removed") }

    section("Menu bar glyph")
    for n in [0, 1, 3, 6] {
        let img = glyph(code: "EN", count: n, current: n > 0 ? 0 : nil)
        expect(img.size.width > 0 && img.size.height == 18 && img.isTemplate, "\(n) dot(s): valid template image (\(Int(img.size.width))×18)")
    }
    let five = glyph(code: "EN", count: 5, current: 0, style: .dots).size.width
    for n in [6, 8, 12, 30] {
        expect(glyph(code: "EN", count: n, current: Double(n / 2), style: .dots).size.width <= five, "\(n) languages: the icon stays as narrow as with five")
    }
    expectEqual(dotWindow(count: 4, current: 2).map(\.index), [0, 1, 2, 3], "up to five: one dot per language")
    for n in [6, 9, 15] {
        for cur in 0..<n {
            let w = dotWindow(count: n, current: Double(cur))
            if w.count != 5 || !w.contains(where: { $0.index == cur }) { expect(false, "\(n) languages, #\(cur + 1) active: the lit dot is in view (\(w.map(\.index)))") }
        }
    }
    expect(true, "with 6, 9 and 15 languages the active one is always among the five dots")
    section("Indicator styles — chosen in Settings")
    expectEqual(Indicator.auto.resolved(count: 5), .dots, "Auto: dots up to five languages")
    expectEqual(Indicator.auto.resolved(count: 6), .slider, "Auto: a slider from six on")
    expectEqual(Indicator.number.resolved(count: 3), .number, "a chosen style is kept")
    for style in Indicator.allCases {
        var widths: [Int] = []
        for n in [1, 4, 6, 9, 15, 40] {
            for p in [0.0, Double(n - 1) / 2, Double(n - 1)] {
                let img = glyph(code: "UK", count: n, current: p, style: style)
                widths.append(Int(img.size.width))
                if !(img.size.width > 0 && img.size.height == 18 && img.isTemplate) { expect(false, "\(style.title), \(n) languages: valid image") }
            }
        }
        expect(widths.max()! <= 34, "\(style.title): stays narrow with up to 40 languages (max \(widths.max()!) pt)")
    }
    expect(glyph(code: "EN", count: 0, current: nil, style: .slider).size.width > 0 && glyph(code: "EN", count: 6, current: nil, style: .number).size.width > 0,
           "no languages or no current one → still draws, no crash")
    expect(glyph(code: "EN", count: 8, current: 2.4, style: .slider).size.width > 0, "in-between positions (the slide animation) draw fine")
    let saved = UserDefaults.standard.string(forKey: "indicator")
    UserDefaults.standard.set("nonsense", forKey: "indicator")
    expectEqual(Indicator.current, .auto, "a broken setting falls back to Auto")
    if let saved { UserDefaults.standard.set(saved, forKey: "indicator") } else { UserDefaults.standard.removeObject(forKey: "indicator") }

    let middle = dotWindow(count: 12, current: 6)
    expect(middle.first!.scale < 1 && middle.last!.scale < 1, "more on both sides → both edge dots are small")
    let atStart = dotWindow(count: 12, current: 0)
    expect(atStart.first!.scale == 1 && atStart.last!.scale < 1, "at the start → only the right edge is small")
    expect(dotWindow(count: 0, current: nil).isEmpty && dotWindow(count: 9, current: nil).count == 5 && dotWindow(count: 9, current: 99).count == 5, "no current or a bad index → no crash")

    // ───────────────────────── integration (real input sources)
    testUpdater()

    section("Switching layouts — real TIS calls")
    let original = currentSourceID()
    let enabled = enabledKeyboardLayouts().map { Source(id: $0, name: sourceName($0)) }
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

    section("Menu bar icon follows every switch — the Globe/fn key, Control-Space, Lingo itself")
    if enabled.count > 1 {
        let app = AppDelegate()
        app.watchLayouts()
        var lagged: [String] = []
        for round in 0..<3 {
            for layout in enabled {
                guard let tis = source(layout.id) else { continue }
                TISSelectInputSource(tis)                // the way macOS switches: Lingo only hears the notification
                RunLoop.main.run(until: Date().addingTimeInterval(1.5))
                let active = currentSourceID()             // what macOS really has now (it can switch back on its own)
                let index = app.store.langs.firstIndex { $0.sourceID == active }
                let code = index.map { app.store.langs[$0].code } ?? suggestCode(active)
                if !app.drawn.hasPrefix(code + "|") { lagged.append("\(round):\(sourceName(active))→\(app.drawn)") }
            }
        }
        expect(lagged.isEmpty, "the icon shows the active layout after every switch (\(enabled.count * 3) switches) \(lagged)")
        app.pollTimer?.invalidate()
        activate(original)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    } else { skip("icon follows switches", "only one keyboard layout is enabled") }

    runRobustnessTests()

    finish("Lingo")
}
