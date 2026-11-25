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
    let sources: [Source]
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
            Menu {
                ForEach(sources) { src in Button(src.name) { lang.sourceID = src.id; lang.code = suggestCode(src.id) } }
            } label: {
                HStack(spacing: 6) {
                    Text(languageName(lang.sourceID)).font(.system(size: 13)).foregroundStyle(.primary)
                    Text(sourceName(lang.sourceID)).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Change the keyboard layout")
            Spacer(minLength: 8)
            KeyRecorder(key: $lang.key, trigger: trigger)
            Button(action: remove) {
                Image(systemName: "minus.circle").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Remove")
        }
        .padding(.horizontal, 12).frame(height: 38)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    let sources = allKeyboardSources()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trigger = Trigger.current
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
                            LangRow(lang: $lang, isCurrent: lang.sourceID == store.current, trigger: trigger, sources: sources) {
                                withAnimation(.easeOut(duration: 0.15)) { store.langs.removeAll { $0.id == lang.id } }
                            }
                        }
                        .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    }
                    .onMove { store.langs.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(true)
                .frame(height: CGFloat(store.langs.count) * 38 + CGFloat(max(store.langs.count - 1, 0)))
                .id(trigger)
                Divider()
                Button(action: add) {
                    Label("Add language", systemImage: "plus").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            group("Options") {
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

            Text(duplicateKeys ? "Two languages use the same key" : "\(trigger.note) · drag to reorder · v\(version)")
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

    func add() {
        let used = Set(store.langs.map(\.sourceID))
        guard let pick = sources.first(where: { !used.contains($0.id) }) ?? sources.first else { return }
        let usedKeys = Set(store.langs.map(\.key))
        let first = suggestCode(pick.id).first.map(String.init) ?? ""
        let key = keyLetters.first { $0.value == first && !usedKeys.contains($0.key) }?.key
            ?? keyLetters.keys.sorted().first { !usedKeys.contains($0) } ?? kVK_ANSI_L
        withAnimation { store.langs.append(Lang(sourceID: pick.id, code: suggestCode(pick.id), key: key)) }
    }
}
