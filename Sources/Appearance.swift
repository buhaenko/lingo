// Light, dark, or follow macOS — for the Settings window.

import AppKit

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    static var current: Appearance { Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Saves the choice and repaints everything at once.
    @MainActor static func apply(_ choice: Appearance = current) {
        UserDefaults.standard.set(choice.rawValue, forKey: "appearance")
        NSApp.appearance = choice.nsAppearance
    }
}
