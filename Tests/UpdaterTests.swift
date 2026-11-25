// Updater tests — the same checks as in Lens: versions, the release feed, signatures, and a real install on a fake bundle.
import Cocoa
import CryptoKit

func blocking<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
    let box = UnsafeMutableTransferBox<T?>(nil)
    let sem = DispatchSemaphore(value: 0)
    Task.detached { box.value = await work(); sem.signal() }
    while sem.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return box.value!
}
final class UnsafeMutableTransferBox<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@discardableResult func shell(_ tool: String, _ args: String...) -> Bool {
    let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit(); return p.terminationStatus == 0
}

@MainActor func testUpdater() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lingo-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    section("Updates")
    expect(Updater.isNewer("1.2.1", than: "1.2.0") && Updater.isNewer("1.2.10", than: "1.2.9") && Updater.isNewer("1.3", than: "1.2.9"), "newer versions compare numerically")
    expect(!Updater.isNewer("1.2.0", than: "1.2.0") && !Updater.isNewer("1.1.9", than: "1.2.0") && !Updater.isNewer("1.2", than: "1.2.0"), "same or older is never an update")
    expect(!Updater.isNewer("2.0-beta", than: "1.0") && !Updater.isRelease("ci") && !Updater.isRelease("0.0.0-dev"), "pre-releases and dev builds are ignored")
    let feedJSON = #"{"tag_name":"v1.4.0","assets":[{"name":"Lingo.dmg","browser_download_url":"https://x/Lingo.dmg"},{"name":"Lingo.zip","browser_download_url":"https://x/Lingo.zip"},{"name":"Lingo.zip.sig","browser_download_url":"https://x/Lingo.zip.sig"}]}"#
    expectEqual(Updater.parse(Data(feedJSON.utf8)), Updater.Release(version: "1.4.0", archive: URL(string: "https://x/Lingo.zip")!, signature: URL(string: "https://x/Lingo.zip.sig")!), "GitHub release JSON → version, archive, signature")
    expect(Updater.parse(Data(feedJSON.replacingOccurrences(of: "Lingo.zip.sig", with: "other").utf8)) == nil, "a release without a signature is never installed")
    expect(Data(base64Encoded: Updater.publicKey).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) } != nil, "the built-in public key is a valid Ed25519 key")

    let line = { (state: Updater.State) in Updater.menuLine(state, version: "1.2.1") }
    expectEqual(line(.upToDate).title, "Lingo Is Up to Date", "menu: up to date")
    expectEqual(line(.upToDate).subtitle, "1.2.1 is the latest version", "menu: says which version is the latest")
    expect(line(.available("1.3.0")).title == "Update to Lingo 1.3.0…" && line(.available("1.3.0")).highlighted, "menu: a new version stands out")
    expect(!line(.checking).enabled && !line(.installing("1.3.0")).enabled, "menu: no double clicks while checking or installing")
    expect(!Updater.menuLine(.unknown, version: "dev", enabled: false).enabled, "menu: development builds can't update")
    for symbol in [Updater.State.unknown, .checking, .upToDate, .failed, .available("2"), .installing("2")].map({ line($0).symbol }) {
        expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "menu icon exists: \(symbol)")
    }
    let feedFile = tmp.appendingPathComponent("feed.json")
    try? Data(feedJSON.utf8).write(to: feedFile)
    let foundRelease = blocking { await Updater.shared.refresh(feed: feedFile) }
    expect(foundRelease?.version == "1.4.0" && Updater.shared.state == .available("1.4.0"), "check finds a newer release → “Update to Lingo 1.4.0…”")
    try? Data(feedJSON.replacingOccurrences(of: "v1.4.0", with: "v0").utf8).write(to: feedFile)
    _ = blocking { await Updater.shared.refresh(feed: feedFile) }
    expectEqual(Updater.shared.state, .upToDate, "same version → “Lingo Is Up to Date”")
    _ = blocking { await Updater.shared.refresh(feed: tmp.appendingPathComponent("missing.json")) }
    expectEqual(Updater.shared.state, .failed, "no connection → “Couldn’t connect — try again”")

    // end to end on a fake bundle: sign → "download" (file://) → verify → unpack → install over an older copy
    let key = Curve25519.Signing.PrivateKey(), pub = key.publicKey.rawRepresentation.base64EncodedString()
    let testID = "com.serhii.Lingo.updatetest"
    func fakeApp(_ dir: URL, version: String, id: String = testID) -> URL {
        let app = dir.appendingPathComponent("Lingo.app")
        try? FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/Lingo").path)
        (["CFBundleIdentifier": id, "CFBundleExecutable": "Lingo", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        shell("/usr/bin/codesign", "--force", "-s", "-", app.path)
        return app
    }
    func release(_ name: String, version: String, bundleVersion: String? = nil, id: String = testID, tamper: Bool = false) -> Updater.Release {
        let dir = tmp.appendingPathComponent("rel-\(name)")
        let app = fakeApp(dir, version: bundleVersion ?? version, id: id)
        let zip = dir.appendingPathComponent("Lingo.zip")
        shell("/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path)
        var data = (try? Data(contentsOf: zip)) ?? Data()
        let sig = (try? key.signature(for: data).base64EncodedString()) ?? ""
        if tamper { data[data.count / 2] ^= 0xFF; try? data.write(to: zip) }
        try? Data(sig.utf8).write(to: dir.appendingPathComponent("Lingo.zip.sig"))
        return Updater.Release(version: version, archive: zip, signature: dir.appendingPathComponent("Lingo.zip.sig"))
    }
    let installed = fakeApp(tmp.appendingPathComponent("Applications"), version: "1.0.0")
    func prepare(_ r: Updater.Release, publicKey: String? = nil) -> Result<URL, Error> {
        let pk = publicKey ?? pub
        return blocking { do { return .success(try await Updater.prepare(r, replacing: installed, publicKey: pk, bundleID: testID, current: "1.0.0")) } catch { return .failure(error) } }
    }
    func failure(_ result: Result<URL, Error>) -> String { if case .failure(let e) = result { return "\(e)" }; return "success" }
    let good = prepare(release("good", version: "9.9.9"))
    if case .success(let staged) = good {
        expect((try? Updater.install(staged, over: installed)) != nil, "the new bundle replaces the installed one")
        expectEqual(NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String, "9.9.9", "installed copy is now the new version")
        expect(shell("/usr/bin/codesign", "--verify", "--strict", installed.path), "installed copy keeps a valid signature")
    } else { expect(false, "a correctly signed update is accepted: \(failure(good))") }
    expectEqual(failure(prepare(release("tampered", version: "9.9.9", tamper: true))), "badSignature", "a modified archive is rejected")
    expectEqual(failure(prepare(release("otherkey", version: "9.9.9"), publicKey: Updater.publicKey)), "badSignature", "an archive signed with another key is rejected")
    expectEqual(failure(prepare(release("otherapp", version: "9.9.9", id: "com.evil.App"))), "badArchive", "another app's bundle is rejected")
    expectEqual(failure(prepare(release("mismatch", version: "9.9.9", bundleVersion: "1.0.0"))), "badArchive", "a bundle whose version doesn't match the release is rejected (no downgrades)")

}
