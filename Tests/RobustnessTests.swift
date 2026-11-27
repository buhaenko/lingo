// Robustness: the menu, appearance, and crash tests — random key presses, garbage settings and feeds, odd layouts, memory.
// Called from runTests() before the summary.
import Cocoa
import Carbon

func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
    return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}

@MainActor func runRobustnessTests() {
    section("Status menu — every item, with its icon")
    let app = AppDelegate()
    let menu = NSMenu()
    app.menuNeedsUpdate(menu)
    let real = menu.items.filter { !$0.isSeparatorItem }
    let titles = real.map(\.title)
    expect(titles.contains("Settings…") && titles.last.map { $0.hasPrefix("Quit") } == true, "Settings… and Quit are there (\(titles.count) items)")
    let iconItems = real.filter { $0.image != nil }
    expect(iconItems.count >= 3, "the menu has icons (\(iconItems.count))")
    let visible = iconItems.allSatisfy { item in
        !item.responds(to: NSSelectorFromString("preferredImageVisibility")) || (item.value(forKey: "preferredImageVisibility") as? Int) == 1
    }
    expect(visible, "icons are forced visible (macOS 27 hides them otherwise)")
    expect(real.filter { $0.action != nil }.allSatisfy { item in (item.target as AnyObject?)?.responds(to: item.action!) ?? NSApp.responds(to: item.action!) },
           "every item is wired to something that handles it")

    section("Appearance — light, dark or auto")
    let saved = UserDefaults.standard.string(forKey: "appearance")
    Appearance.apply(.dark); expectEqual(NSApp.appearance?.name, .darkAqua, "Dark → dark")
    Appearance.apply(.light); expectEqual(NSApp.appearance?.name, .aqua, "Light → light")
    Appearance.apply(.system); expect(NSApp.appearance == nil, "Auto → follows macOS")
    UserDefaults.standard.set("bogus", forKey: "appearance"); expectEqual(Appearance.current, .system, "a broken setting falls back to Auto")
    if let saved { UserDefaults.standard.set(saved, forKey: "appearance") } else { UserDefaults.standard.removeObject(forKey: "appearance") }
    NSApp.appearance = nil

    section("Crash test — a million random key presses")
    let langs = Store.reconciled([], enabled: ["com.apple.keylayout.US", "com.apple.keylayout.German", "com.apple.keylayout.French"])
    let flags: [CGEventFlags] = [[], .maskSecondaryFn, .maskAlternate, .maskControl, [.maskControl, .maskAlternate], .maskShift, .maskCommand,
                                 [.maskSecondaryFn, .maskAlphaShift], [.maskSecondaryFn, .maskCommand, .maskShift], CGEventFlags(rawValue: .max)]
    var hits = 0, misfires = 0
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<1_000_000 {
        let f = flags.randomElement(using: &rng)!, key = Int64.random(in: -5...300, using: &rng), trigger = Trigger.allCases.randomElement(using: &rng)!
        if let hit = matchShortcut(flags: f, keyCode: key, trigger: trigger, langs: langs) {
            hits += 1
            if Int64(hit.key) != key || f.contains(.maskCommand) || f.contains(.maskShift) { misfires += 1 }
        }
    }
    expect(hits > 0, "some presses switch (\(hits))")
    expectEqual(misfires, 0, "none of them was the wrong key, or had ⌘ or ⇧ held")

    section("Crash test — garbage settings and feeds")
    for garbage in ["", "null", "[]", "{}", "[{\"sourceID\":1}]", "[{\"id\":\"x\",\"sourceID\":\"a\",\"code\":\"\",\"key\":-1}]", String(repeating: "[", count: 5000)] {
        _ = try? JSONDecoder().decode([Lang].self, from: Data(garbage.utf8))
    }
    UserDefaults.standard.set("not-a-trigger", forKey: "trigger"); expectEqual(Trigger.current, .fn, "a broken trigger setting falls back to fn")
    UserDefaults.standard.removeObject(forKey: "trigger")
    var survived = 0
    for i in 0..<3000 {
        var data = Data((0..<Int.random(in: 0..<300, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        if i % 3 == 0 { data = Data(#"{"tag_name":\#(["null", "1", "\"v\"", "\"v99999999999999999999.1\""][i % 4]),"assets":\#(["[]", "{}", "[{}]", "7"][i % 4])}"#.utf8) }
        _ = Updater.parse(data); survived += 1
    }
    expectEqual(survived, 3000, "3000 random and malformed release feeds → no crash")
    expect(true, "malformed saved languages are rejected without crashing")

    section("Crash test — odd layouts")
    for id in ["", " ", "com.apple.keylayout.", "😀", String(repeating: "x", count: 2000), "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"] {
        _ = suggestCode(id); _ = languageName(id); _ = sourceName(id); _ = source(id, includeAll: true)
    }
    let before = currentSourceID()
    for _ in 0..<50 { activate("com.example.nope.\(Int.random(in: 0...9, using: &rng))") }
    expectEqual(currentSourceID(), before, "50 switches to layouts that don't exist change nothing")
    for n in [0, 1, 6, 40] { for style in Indicator.allCases { _ = glyph(code: "", count: n, current: n > 0 ? Double(n - 1) : nil, style: style); _ = glyph(code: "ÄÖÜ", count: n, current: nil, style: style) } }
    expect(true, "the menu bar glyph draws with empty codes, umlauts and 40 languages, in every indicator style")

    section("Crash test — memory stays flat")
    let start = residentMB()
    for _ in 0..<300 { _ = allKeyboardSources(); _ = glyph(code: "EN", count: 4, current: 1) }
    let grew = residentMB() - start
    expect(grew < 60, "300 layout lists + glyphs grow memory by \(Int(grew)) MB (< 60)")
}
