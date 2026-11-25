// Keyboard layouts via Text Input Sources (TIS): list, names, switching, suggested codes.

import Foundation
import Carbon

struct Source: Identifiable, Hashable {
    let id: String
    let name: String
}

private func property(_ source: TISInputSource, _ key: CFString) -> String? {
    TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
}

private func keyboardLayouts(includeAllInstalled: Bool) -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                  kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
    return (TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

/// Every keyboard layout macOS has (for the picker), sorted by name.
func allKeyboardSources() -> [Source] {
    var seen = Set<String>()
    return keyboardLayouts(includeAllInstalled: true).compactMap { layout -> Source? in
        guard let id = property(layout, kTISPropertyInputSourceID),
              let name = property(layout, kTISPropertyLocalizedName),
              seen.insert(id).inserted else { return nil }
        return Source(id: id, name: name)
    }
    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}

/// Ids of the layouts enabled in System Settings, in the user's order.
func enabledKeyboardLayouts() -> [String] {
    keyboardLayouts(includeAllInstalled: false).compactMap { property($0, kTISPropertyInputSourceID) }
}

func source(_ id: String, includeAll: Bool = false) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    return (TISCreateInputSourceList(filter, includeAll)?.takeRetainedValue() as? [TISInputSource])?.first
}

func sourceName(_ id: String) -> String {
    source(id, includeAll: true).flatMap { property($0, kTISPropertyLocalizedName) } ?? id
}

func currentSourceID() -> String {
    property(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID) ?? ""
}

/// Switches to a layout, enabling it in macOS first if needed. Unknown ids are ignored.
func activate(_ id: String) {
    if let enabled = source(id) {
        TISSelectInputSource(enabled)
    } else if let installed = source(id, includeAll: true) {
        TISEnableInputSource(installed)
        TISSelectInputSource(installed)
    }
}

/// Primary language of a layout, e.g. "uk" for Ukrainian – PC.
private func languageCode(_ id: String) -> String? {
    guard let layout = source(id, includeAll: true),
          let raw = TISGetInputSourceProperty(layout, kTISPropertyInputSourceLanguages),
          let codes = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String],
          let first = codes.first else { return nil }
    return Locale.Language(identifier: first).languageCode?.identifier ?? first
}

/// ISO 639-1 code for a layout: U.S. → EN, German → DE, Ukrainian → UK.
func suggestCode(_ id: String) -> String {
    if let code = languageCode(id) { return String(code.prefix(3)).uppercased() }
    return String(sourceName(id).prefix(2)).uppercased()
}

/// The layout's language in that language: "Deutsch", "Українська".
func languageName(_ id: String) -> String {
    guard let code = languageCode(id), let name = Locale(identifier: code).localizedString(forLanguageCode: code) else { return sourceName(id) }
    return name.prefix(1).uppercased() + name.dropFirst()
}
