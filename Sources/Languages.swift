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
            langs = Store.fromEnabledLayouts()
        }
    }

    /// First run: the layouts the user already has enabled, each on the first letter of its code.
    static func fromEnabledLayouts() -> [Lang] {
        var usedKeys = Set<Int>()
        var result: [Lang] = []
        for id in enabledKeyboardLayouts().prefix(6) {
            let code = suggestCode(id)
            let preferred = keyLetters.first { $0.value == String(code.prefix(1)) && !usedKeys.contains($0.key) }?.key
            guard let key = preferred ?? keyLetters.keys.sorted().first(where: { !usedKeys.contains($0) }) else { continue }
            usedKeys.insert(key)
            result.append(Lang(sourceID: id, code: code, key: key))
        }
        return result.isEmpty ? [Lang(sourceID: "com.apple.keylayout.US", code: "EN", key: kVK_ANSI_E)] : result
    }

    func save() {
        if let data = try? JSONEncoder().encode(langs) { UserDefaults.standard.set(data, forKey: "langs") }
        onChange()
    }
}
