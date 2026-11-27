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

private func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
    TISGetInputSourceProperty(source, key).map { Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue() == kCFBooleanTrue } ?? false
}

/// Keyboard input sources you can actually type with and switch to: layouts (U.S., Ukrainian) and input-method
/// modes (2-Set Korean, Pinyin, Hiragana). Not the bare input methods, and not layouts macOS can't select on
/// their own (e.g. the Hangul layouts that only work inside the Korean input method).
private func inputSources(includeAllInstalled: Bool) -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
    let all = (TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource]) ?? []
    return all.filter { source in
        guard flag(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
        let type = property(source, kTISPropertyInputSourceType)
        if type == kTISTypeKeyboardLayout as String { return true }
        guard type == kTISTypeKeyboardInputMode as String else { return false }
        // macOS reports some modes as "enabled" while their input method is off (they're not in the Input menu
        // and can't be switched to). Count a mode as on only when its input method is on too.
        return includeAllInstalled || inputMethodIsOn(for: source)
    }
}

private func inputMethodIsOn(for mode: TISInputSource) -> Bool {
    guard let bundle = property(mode, kTISPropertyBundleID), let methodID = inputMethodID(bundle: bundle),
          let method = source(methodID, includeAll: true) else { return false }
    return flag(method, kTISPropertyInputSourceIsEnabled)
}

/// Everything that can be added (for the picker), sorted by name.
func allKeyboardSources() -> [Source] {
    var seen = Set<String>()
    return inputSources(includeAllInstalled: true).compactMap { layout -> Source? in
        guard let id = property(layout, kTISPropertyInputSourceID),
              let name = property(layout, kTISPropertyLocalizedName),
              seen.insert(id).inserted else { return nil }
        return Source(id: id, name: name)
    }
    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}

/// What System Settings → Keyboard → Input Sources has, in its order — the list Lingo shows.
func enabledKeyboardLayouts() -> [String] {
    inputSources(includeAllInstalled: false).compactMap { property($0, kTISPropertyInputSourceID) }
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

/// Switches to an input source that's on in macOS. Anything else is ignored — Lingo never turns sources on
/// behind the person's back (that's what "Add language" is for).
func activate(_ id: String) {
    guard let enabled = source(id), flag(enabled, kTISPropertyInputSourceIsSelectCapable) else { return }
    TISSelectInputSource(enabled)
}

/// Adds an input source to macOS, as System Settings → Input Sources → + would.
/// Input-method modes (2-Set Korean, Pinyin…) need their input method turned on first. Returns whether it's on now.
@discardableResult func enableInSystem(_ id: String) -> Bool {
    guard let installed = source(id, includeAll: true) else { return false }
    if property(installed, kTISPropertyInputSourceType) == kTISTypeKeyboardInputMode as String,
       let methodID = property(installed, kTISPropertyBundleID).flatMap({ bundle in
           inputMethodID(bundle: bundle) }), let method = source(methodID, includeAll: true) {
        TISEnableInputSource(method)
    }
    TISEnableInputSource(installed)
    if !enabledKeyboardLayouts().contains(id) {          // the mode may only stick once its method is fully on
        TISEnableInputSource(installed)
    }
    return enabledKeyboardLayouts().contains(id)
}

/// The input method a mode belongs to: com.apple.inputmethod.Korean.2SetKorean → com.apple.inputmethod.Korean.
private func inputMethodID(bundle: String) -> String? {
    let filter = [kTISPropertyBundleID as String: bundle, kTISPropertyInputSourceType as String: kTISTypeKeyboardInputMethodModeEnabled as String] as CFDictionary
    let methods = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
    return methods.first.flatMap { property($0, kTISPropertyInputSourceID) }
}

/// Removes an input source from macOS, as System Settings → Input Sources → − would. Never the last one.
/// Returns whether it's off now.
@discardableResult func disableInSystem(_ id: String) -> Bool {
    let enabled = enabledKeyboardLayouts()
    guard enabled.contains(id), enabled.count > 1, let src = source(id) else { return !enabled.contains(id) }
    if currentSourceID() == id, let other = enabled.first(where: { $0 != id }) { activate(other) }
    TISDisableInputSource(src)
    // the last mode of an input method gone → the input method goes too, as in System Settings
    if property(src, kTISPropertyInputSourceType) == kTISTypeKeyboardInputMode as String,
       let bundle = property(src, kTISPropertyBundleID), let methodID = inputMethodID(bundle: bundle),
       let method = source(methodID, includeAll: true),
       !enabledKeyboardLayouts().contains(where: { other in source(other).flatMap { property($0, kTISPropertyBundleID) } == bundle }) {
        TISDisableInputSource(method)
    }
    return !enabledKeyboardLayouts().contains(id)
}

/// Primary language of a layout, e.g. "uk" for Ukrainian – PC.
private func languageCode(_ id: String) -> String? {
    guard let layout = source(id, includeAll: true),
          let raw = TISGetInputSourceProperty(layout, kTISPropertyInputSourceLanguages),
          let codes = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String],
          let first = codes.first, !first.isEmpty else { return nil }
    return Locale.Language(identifier: first).languageCode?.identifier ?? first
}

/// ISO 639-1 code for a layout: U.S. → EN, German → DE, Ukrainian → UK.
func suggestCode(_ id: String) -> String {
    if let code = languageCode(id), !code.isEmpty { return String(code.prefix(3)).uppercased() }
    let letters = sourceName(id).filter(\.isLetter)
    return String((letters.isEmpty ? "?" : letters).prefix(2)).uppercased()
}

/// The layout's language in that language: "Deutsch", "Українська".
func languageName(_ id: String) -> String {
    guard let code = languageCode(id), let name = Locale(identifier: code).localizedString(forLanguageCode: code) else { return sourceName(id) }
    return name.prefix(1).uppercased() + name.dropFirst()
}
