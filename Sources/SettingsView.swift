// Settings window: languages (layout, code, key), trigger modifier, launch at login.

import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import ServiceManagement

/// "fn E" — the shortcut as one quiet pill; click it, then press a new key.
struct KeyRecorder: View {
    @Binding var key: Int
    let trigger: Trigger
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Text(recording ? "Press a key…" : "\(trigger.keycap) \(keyLetters[key] ?? "?")")
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(recording ? Color.accentColor : .secondary)
            .padding(.horizontal, 8).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(recording ? 0.12 : 0.07)))
            .contentShape(Rectangle())
            .onTapGesture { recording ? stop() : start() }
            .help(recording ? "Press a letter or digit · Esc cancels" : "Click to change the key")
            .onDisappear { stop() }
    }
    func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if Int(e.keyCode) == kVK_Escape { stop(); return nil }
            if keyLetters[Int(e.keyCode)] != nil { key = Int(e.keyCode); stop() }
            return nil
        }
    }
    func stop() { recording = false; if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
}

struct LangRow: View {
    @Binding var lang: Lang
    let isCurrent: Bool
    let trigger: Trigger
    var remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(isCurrent ? Color.accentColor : Color.clear).frame(width: 6, height: 6)
                .help(isCurrent ? "Current layout" : "")
            TextField("", text: Binding(get: { lang.code }, set: { lang.code = String($0.uppercased().prefix(3)) }))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .frame(width: 30)
                .help("Short code shown in the menu bar")
            HStack(spacing: 6) {
                Text(languageName(lang.sourceID)).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
                Text(sourceName(lang.sourceID)).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
            .fixedSize()
            Spacer(minLength: 8)
            KeyRecorder(key: $lang.key, trigger: trigger)
            Button(action: remove) {
                Image(systemName: "minus.circle").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Remove — also from your Mac’s input sources")
        }
        .padding(.horizontal, 12).frame(height: 38)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct SettingsView: View {
    @State private var appearance = Appearance.current
    @ObservedObject var store = Store.shared
    let sources = allKeyboardSources()
    @State private var addError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trigger = Trigger.current
    @State private var indicator = Indicator.current
    @State private var axTrusted = AXIsProcessTrusted()
    let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @AppStorage("autoUpdate") private var autoUpdate = true
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                Text("Lingo").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Hold \(trigger.keycap) + key to switch").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }

            group("Languages") {
                List {
                    ForEach(Array($store.langs.enumerated()), id: \.element.id) { i, $lang in
                        VStack(spacing: 0) {
                            if i > 0 { Divider().padding(.leading, 28) }
                            LangRow(lang: $lang, isCurrent: lang.sourceID == store.current, trigger: trigger) {
                                let id = lang.sourceID
                                withAnimation(.easeOut(duration: 0.15)) { _ = store.remove(id) }
                            }
                        }
                        .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(true)
                .frame(height: CGFloat(store.langs.count) * 38 + CGFloat(max(store.langs.count - 1, 0)))
                .id(trigger)
                Divider()
                Menu {
                    let enabled = store.langs.map(\.sourceID)
                    let suggested = Store.suggestions(enabled: enabled)
                    if !suggested.isEmpty {
                        Section("Suggested") {
                            ForEach(suggested, id: \.self) { id in Button("\(languageName(id)) — \(sourceName(id))") { add(id) } }
                        }
                    }
                    Menu("All input sources") {
                        ForEach(sources.filter { !enabled.contains($0.id) }) { src in Button(src.name) { add(src.id) } }
                    }
                } label: {
                    Label("Add language", systemImage: "plus").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 34)
                if let addError {
                    Text(addError).font(.system(size: 11)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 8)
                }
            }

            group("Options") {
                row("Appearance") {
                    Picker("", selection: $appearance) {
                        ForEach(Appearance.allCases) { choice in Label(choice.title, systemImage: choice.symbol).tag(choice) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                    .onChange(of: appearance) { _, choice in Appearance.apply(choice) }
                }
                Divider().padding(.leading, 12)
                row("Indicator") {
                    IndicatorPreview(style: indicator, count: max(store.langs.count, 1),
                                     current: store.langs.firstIndex { $0.sourceID == store.current } ?? 0,
                                     code: store.langs.first { $0.sourceID == store.current }?.code ?? store.langs.first?.code ?? "EN")
                    Picker("", selection: $indicator) {
                        ForEach(Indicator.allCases) { Text($0 == .auto ? "Auto — dots, then a slider" : $0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: indicator) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "indicator"); store.save() }
                }
                Divider().padding(.leading, 12)
                row("Switch with") {
                    Picker("", selection: $trigger) { ForEach(Trigger.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().fixedSize()
                        .onChange(of: trigger) { _, v in UserDefaults.standard.set(v.rawValue, forKey: "trigger"); store.save() }
                }
                Divider().padding(.leading, 12)
                row("Launch at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .onChange(of: launchAtLogin) { _, on in
                            do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                            catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                        }
                }
                Divider().padding(.leading, 12)
                row("Update automatically") {
                    Toggle("", isOn: $autoUpdate).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if !axTrusted {
                    Divider().padding(.leading, 12)
                    row("Accessibility access is off") {
                        Button("Allow…") {
                            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                        }.controlSize(.small)
                    }
                }
            }

            Text(duplicateKeys ? "Two languages use the same key" : "Same list as System Settings → Keyboard → Input Sources · v\(version)")
                .font(.system(size: 11)).foregroundStyle(duplicateKeys ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 16)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(tick) { _ in axTrusted = AXIsProcessTrusted() }
    }

    func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    func row<C: View>(_ title: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack { Text(title).font(.system(size: 13)); Spacer(); trailing() }
            .padding(.horizontal, 12).frame(height: 38)
    }

    var duplicateKeys: Bool { Set(store.langs.map(\.key)).count != store.langs.count }

    /// Adds it to macOS (System Settings → Input Sources) — then it appears here with its own key.
    func add(_ id: String) {
        addError = withAnimation { store.add(id) } ? nil : "macOS didn’t add \(sourceName(id)). Try System Settings → Keyboard → Input Sources."
    }
}

/// The menu bar icon as it will look with this indicator, for the person's own list of languages.
private struct IndicatorPreview: View {
    let style: Indicator
    let count: Int
    let current: Int
    let code: String

    var body: some View {
        Image(nsImage: glyph(code: code, count: count, current: Double(current), style: style))
            .renderingMode(.template)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            .help("How the menu bar icon looks with \(count) languages")
    }
}
