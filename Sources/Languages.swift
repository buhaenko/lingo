// The user's languages: layout + short code + key, persisted in UserDefaults.

import Foundation
import Combine
import Carbon.HIToolbox

struct Lang: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceID: String    // keyboard layout, e.g. "com.apple.keylayout.German"
    var code: String        // shown in the menu bar, e.g. "DE"
    var key: Int            // physical key (virtual key code), pressed together with the trigger
}

/// Assignable keys: A–Z and 0–9, by physical position (independent of the active layout).
let keyLetters: [Int: String] = [
    kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G",
    kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N",
    kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U",
    kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
    kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
    kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
]

/// The languages Lingo switches between are exactly the input sources in System Settings → Keyboard → Input Sources,
/// in that order. Lingo only adds what's its own: the short code in the menu bar and the key for each one.
/// Adding a language here adds it to macOS, removing it here removes it from macOS — so it always works,
/// and the Globe key / Control-Space cycle through the same list.
@MainActor final class Store: ObservableObject {
    static let shared = Store()

    @Published var langs: [Lang] { didSet { save() } }
    @Published var current = ""                 // input source id of the active layout
    var onChange: () -> Void = {}

    init(enabled: [String] = enabledKeyboardLayouts()) {
        var saved: [Lang] = []
        if let data = UserDefaults.standard.data(forKey: "langs"), let list = try? JSONDecoder().decode([Lang].self, from: data) { saved = list }
        knownEnabled = enabled
        langs = Store.reconciled(saved, enabled: enabled)
    }

    /// Popular languages and their usual macOS layout — offered first under "Add language".
    static let standardLayouts: [String: String] = [
        "en": "com.apple.keylayout.US", "de": "com.apple.keylayout.German", "es": "com.apple.keylayout.Spanish-ISO",
        "fr": "com.apple.keylayout.French", "uk": "com.apple.keylayout.Ukrainian-PC", "it": "com.apple.keylayout.Italian",
        "pt": "com.apple.keylayout.Portuguese", "pl": "com.apple.keylayout.PolishPro", "ru": "com.apple.keylayout.Russian",
        "sv": "com.apple.keylayout.Swedish", "tr": "com.apple.keylayout.Turkish-QWERTY-PC", "cs": "com.apple.keylayout.Czech",
    ]
    static let popular = ["en", "de", "es", "fr", "uk", "it", "pt", "pl"]

    /// Suggestions for "Add language": the person's macOS languages first, then popular ones — only those not on yet.
    static func suggestions(enabled: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        var out: [String] = []
        let bases = preferred.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 } + popular
        for base in bases {
            guard let id = standardLayouts[base], !enabled.contains(id), !out.contains(id), source(id, includeAll: true) != nil else { continue }
            out.append(id)
        }
        return out
    }

    /// The system's list, with the person's own codes and keys kept for sources Lingo already knew.
    /// Sources that left macOS leave; new ones join on a free key.
    static func reconciled(_ saved: [Lang], enabled: [String]) -> [Lang] {
        guard !enabled.isEmpty else { return saved }     // macOS always has one; an empty answer is a glitch
        var out: [Lang] = []
        for id in enabled {
            if let known = saved.first(where: { $0.sourceID == id }), !out.contains(where: { $0.key == known.key }) {
                out.append(known)
            } else {
                out.append(make(id, usedKeys: Set(out.map(\.key) + saved.filter { enabled.contains($0.sourceID) }.map(\.key))))
            }
        }
        return out
    }

    /// A new entry for a source, on a free key: the code's letters first, then the language name's.
    static func make(_ id: String, usedKeys used: Set<Int>) -> Lang {
        let code = suggestCode(id)
        let letters = Array(code) + Array(languageName(id).uppercased())
        let key = letters.lazy.compactMap { ch in keyLetters.first { $0.value == String(ch) && !used.contains($0.key) }?.key }.first
            ?? keyLetters.keys.sorted().first { !used.contains($0) } ?? kVK_ANSI_L
        return Lang(sourceID: id, code: code, key: key)
    }

    /// What macOS had on when Lingo last looked.
    private var knownEnabled: [String]

    /// Re-reads System Settings; updates the list when it changed there (or with the Globe key's "Edit…").
    func followSystem(enabled: [String] = enabledKeyboardLayouts()) {
        guard enabled != knownEnabled || langs.map(\.sourceID) != enabled else { return }
        knownEnabled = enabled
        let updated = Store.reconciled(langs, enabled: enabled)
        if updated != langs { langs = updated }
    }

    /// "Add language": turns it on in macOS, then it shows up here. False if macOS refused.
    @discardableResult func add(_ id: String) -> Bool {
        let ok = enableInSystem(id)
        followSystem()
        return ok
    }

    /// The − button: turns it off in macOS too. Never the last one.
    @discardableResult func remove(_ id: String) -> Bool {
        guard langs.count > 1 else { return false }
        let ok = disableInSystem(id)
        followSystem()
        return ok
    }

    func save() {
        if let data = try? JSONEncoder().encode(langs) { UserDefaults.standard.set(data, forKey: "langs") }
        onChange()
    }
}
