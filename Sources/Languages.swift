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

@MainActor final class Store: ObservableObject {
    static let shared = Store()

    @Published var langs: [Lang] { didSet { save() } }
    @Published var current = ""                 // input source id of the active layout
    var onChange: () -> Void = {}

    init() {
        if let data = UserDefaults.standard.data(forKey: "langs"), let saved = try? JSONDecoder().decode([Lang].self, from: data) {
            langs = saved
        } else {
            langs = Store.firstRun()
        }
    }

    /// The usual macOS layout for a language — used when the person doesn't have one enabled yet.
    static let standardLayouts: [String: String] = [
        "en": "com.apple.keylayout.US", "de": "com.apple.keylayout.German", "es": "com.apple.keylayout.Spanish-ISO",
        "fr": "com.apple.keylayout.French", "uk": "com.apple.keylayout.Ukrainian-PC", "it": "com.apple.keylayout.Italian",
        "pt": "com.apple.keylayout.Portuguese", "pl": "com.apple.keylayout.PolishPro", "ru": "com.apple.keylayout.Russian",
        "sv": "com.apple.keylayout.Swedish", "tr": "com.apple.keylayout.Turkish-QWERTY-PC", "cs": "com.apple.keylayout.Czech",
    ]
    /// Ready to go on first launch, after the person's own layouts and languages.
    static let popular = ["en", "de", "es", "fr"]

    /// First run: the person's enabled layouts, then their macOS languages, then popular ones — at least four, at most six.
    /// Layouts that aren't enabled yet get enabled the first time they're used.
    static func firstRun(enabled: [String] = enabledKeyboardLayouts(),
                         preferred: [String] = Locale.preferredLanguages,
                         installed: (String) -> Bool = { source($0, includeAll: true) != nil }) -> [Lang] {
        var ids: [String] = [], codes = Set<String>()
        func add(_ id: String) {
            guard ids.count < 6, installed(id) else { return }
            let code = suggestCode(id)
            guard codes.insert(code).inserted else { return }      // ABC and U.S. are both English: keep one
            ids.append(id)
        }
        enabled.forEach(add)
        for language in preferred {
            let base = Locale.Language(identifier: language).languageCode?.identifier ?? language
            if let id = standardLayouts[base] { add(id) }
        }
        for language in popular where ids.count < 4 { if let id = standardLayouts[language] { add(id) } }
        if ids.isEmpty { ids = ["com.apple.keylayout.US"] }

        var used = Set<Int>()
        return ids.map { id in
            let code = suggestCode(id)
            let letters = Array(code) + Array(languageName(id).uppercased())
            let key = letters.lazy.compactMap { ch in keyLetters.first { $0.value == String(ch) && !used.contains($0.key) }?.key }.first
                ?? keyLetters.keys.sorted().first { !used.contains($0) }!
            used.insert(key)
            return Lang(sourceID: id, code: code, key: key)
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(langs) { UserDefaults.standard.set(data, forKey: "langs") }
        onChange()
    }
}
