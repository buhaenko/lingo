// Signs an update archive with the release key, so Lingo only installs updates that come from this repo.
//
//   UPDATE_SIGNING_KEY=<base64 Ed25519 private key> swift scripts/sign-update.swift build/Lingo.zip > build/Lingo.zip.sig
//
// The key lives in the repo's Actions secrets (and a backup in the login Keychain: "Lingo update signing key").
// The matching public key is Updater.publicKey.
import CryptoKit
import Foundation

guard let encoded = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"], let raw = Data(base64Encoded: encoded),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("UPDATE_SIGNING_KEY is missing or invalid\n".utf8)); exit(1)
}
guard CommandLine.arguments.count == 2, let file = FileManager.default.contents(atPath: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: sign-update.swift <file>\n".utf8)); exit(1)
}
print(try key.signature(for: file).base64EncodedString())
