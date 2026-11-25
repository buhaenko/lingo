// The modifier held together with a language key, and the decision "does this key press switch?".

import AppKit

enum Trigger: String, CaseIterable, Identifiable {
    case fn, control, option, controlOption
    var id: String { rawValue }

    static var current: Trigger { Trigger(rawValue: UserDefaults.standard.string(forKey: "trigger") ?? "") ?? .fn }

    var label: String {
        switch self {
        case .fn: "fn 🌐"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .controlOption: "⌃⌥ Control-Option"
        }
    }

    var keycap: String {
        switch self {
        case .fn: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .controlOption: "⌃⌥"
        }
    }

    var note: String {
        switch self {
        case .fn: "Works on every Mac keyboard with a fn / 🌐 key"
        case .control: "Replaces ⌃ + those letters (e.g. ⌃E end of line)"
        case .option: "Replaces ⌥ + those letters (e.g. accents like ⌥E)"
        case .controlOption: "Rarely used by apps — safest on external keyboards"
        }
    }

    var flags: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .control: .maskControl
        case .option: .maskAlternate
        case .controlOption: [.maskControl, .maskAlternate]
        }
    }
}

/// Which language, if any, this key press switches to. Exactly the trigger must be held:
/// fn + ⇧ + E or ⌘ + fn + E are left alone (Caps Lock doesn't matter).
func matchShortcut(flags: CGEventFlags, keyCode: Int64, trigger: Trigger, langs: [Lang]) -> Lang? {
    let held = flags.intersection([.maskSecondaryFn, .maskCommand, .maskControl, .maskAlternate, .maskShift])
    guard held == trigger.flags else { return nil }
    return langs.first { Int64($0.key) == keyCode }
}
