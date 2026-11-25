// Minimal test kit shared by the menu bar apps (no XCTest / Xcode project needed).
// Build: swiftc -D TESTING main.swift Tests.swift ../menubar/tests/TestKit.swift -o tests && ./tests
import Foundation

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed: [String] = []
nonisolated(unsafe) var skipped: [String] = []
nonisolated(unsafe) var currentSection = ""

func section(_ name: String) { currentSection = name; print("\n▸ \(name)") }

func expect(_ cond: @autoclosure () -> Bool, _ what: String, file: String = #fileID, line: Int = #line) {
    if cond() { passed += 1; print("  ✓ \(what)") }
    else { failed.append("\(currentSection): \(what)  (\(file):\(line))"); print("  ✗ \(what)  ← \(file):\(line)") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ what: String, file: String = #fileID, line: Int = #line) {
    if a == b { passed += 1; print("  ✓ \(what)") }
    else { failed.append("\(currentSection): \(what) — got \(a), expected \(b)  (\(file):\(line))"); print("  ✗ \(what) — got «\(a)», expected «\(b)»") }
}

func skip(_ what: String, _ why: String) { skipped.append("\(what): \(why)"); print("  ⤼ \(what) — skipped (\(why))") }

/// Prints the summary and exits with 1 if anything failed (so release.sh stops).
func finish(_ suite: String) -> Never {
    print("\n\(suite): \(passed) passed, \(failed.count) failed, \(skipped.count) skipped")
    for f in failed { print("  FAIL \(f)") }
    exit(failed.isEmpty ? 0 : 1)
}
