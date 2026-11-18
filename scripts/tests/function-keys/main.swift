import Foundation

var failures = 0, checks = 0
func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok { failures += 1; print("FAIL: \(what())") }
}
func show(_ s: String?) -> String { s.map { $0.replacingOccurrences(of: "\u{1B}", with: "ESC") } ?? "nil" }

// 1. Name parsing
for n in 1...12 { expect(KeyID.functionKeyNumber("F\(n)") == n, "F\(n) -> \(n)") }
for bad in ["F0", "F13", "F01", "F+1", "F-1", "f1", "F", "F1 ", " F1", "Esc", "", "FF1", "F１"] {
    expect(KeyID.functionKeyNumber(bad) == nil, "\"\(bad)\" rejected, got \(String(describing: KeyID.functionKeyNumber(bad)))")
}

// 2. HID usage: F1 = 0x3A ... F12 = 0x45 (USB HID usage table, keyboard page)
for n in 1...12 { expect(Ghostty.TerminalView.functionKeyHIDUsage(n)?.rawValue == 0x39 + n, "HID F\(n)") }
for n in [0, 13, -1] { expect(Ghostty.TerminalView.functionKeyHIDUsage(n) == nil, "HID \(n) nil") }

// 3. Sequences against a hand-written xterm table
let base = ["\u{1B}OP", "\u{1B}OQ", "\u{1B}OR", "\u{1B}OS", "\u{1B}[15~", "\u{1B}[17~",
            "\u{1B}[18~", "\u{1B}[19~", "\u{1B}[20~", "\u{1B}[21~", "\u{1B}[23~", "\u{1B}[24~"]
for n in 1...12 {
    let got = Ghostty.TerminalView.functionKeySequence(n, modifiers: [])
    expect(got == base[n - 1], "plain F\(n): \(show(got)) vs \(show(base[n - 1]))")
}

// 4. Sequences against tmux 3.4's output (tmux-raw.bin, order as in oracle.sh)
let mods: [(String, KeyModifiers)] = [
    ("", []), ("S-", [.shift]), ("M-", [.alt]), ("C-", [.control]), ("S-M-", [.shift, .alt]),
    ("C-S-", [.control, .shift]), ("C-M-", [.control, .alt]), ("C-M-S-", [.control, .alt, .shift]),
]
let raw = try! Data(contentsOf: URL(fileURLWithPath: "tmux-raw.bin"))
let fields = raw.split(separator: UInt8(ascii: "|"), omittingEmptySubsequences: false).dropLast()
    .map { String(decoding: $0, as: UTF8.self) }
expect(fields.count == 96, "oracle has 96 entries, got \(fields.count)")
for (m, (prefix, modifiers)) in mods.enumerated() {
    for n in 1...12 {
        let want = fields[m * 12 + n - 1]
        let got = Ghostty.TerminalView.functionKeySequence(n, modifiers: modifiers)
        expect(got == want, "\(prefix)F\(n): \(show(got)) vs tmux \(show(want))")
    }
}

// 5. Cmd maps to the Alt bit, as for arrows and navigation keys
for n in 1...12 {
    expect(Ghostty.TerminalView.functionKeySequence(n, modifiers: [.command])
           == Ghostty.TerminalView.functionKeySequence(n, modifiers: [.alt]), "Cmd-F\(n) == Alt-F\(n)")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
