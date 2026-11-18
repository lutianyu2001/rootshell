//
//  TerminalView+ToolbarKeyTest.swift
//  rootshell
//
//  Test switch for builds that cannot show or tap the keyboard toolbar (the
//  Mac Catalyst app on an Intel Mac; see docs/old-xcode-compat.md).
//  ROOTSHELL_TEST_TOOLBAR_KEYS lists toolbar keys as KeyID raw values, each
//  with optional "ctrl+", "alt+", "shift+" or "cmd+" prefixes, e.g.
//  "esc,f1,ctrl+f5". Fifteen seconds after the last terminal appeared (the tab
//  an ssh:// URL opens comes after the restored ones), each key goes through
//  that terminal's toolbar keyPressed with the value its button sends, half a
//  second apart, so a test server can log each one. Runs once per process.
//  Progress goes to toolbar-key-test.log in the app's temporary directory: the
//  unified log shows nothing from an ad hoc signed build there.
//

import Foundation
import UIKit

extension Ghostty.TerminalView {
    private static var toolbarKeyTestStarted = false
    private static weak var toolbarKeyTestLatest: Ghostty.TerminalView?

    func scheduleToolbarKeyTestIfRequested() {
        guard let spec = ProcessInfo.processInfo.environment["ROOTSHELL_TEST_TOOLBAR_KEYS"],
              window != nil, !Self.toolbarKeyTestStarted else { return }
        var steps: [(KeyID, KeyModifiers)] = []
        for token in spec.split(separator: ",") {
            var parts = token.split(separator: "+").map(String.init)
            guard let key = parts.popLast().flatMap(KeyID.init(rawValue:)) else {
                Self.toolbarKeyTestLog("unknown key in \(token)")
                return
            }
            var modifiers: KeyModifiers = []
            for part in parts {
                switch part {
                case "ctrl": modifiers.insert(.control)
                case "alt": modifiers.insert(.alt)
                case "shift": modifiers.insert(.shift)
                case "cmd": modifiers.insert(.command)
                default:
                    Self.toolbarKeyTestLog("unknown modifier \(part)")
                    return
                }
            }
            steps.append((key, modifiers))
        }
        Self.toolbarKeyTestLatest = self
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, Self.toolbarKeyTestLatest === self, !Self.toolbarKeyTestStarted else { return }
            Self.toolbarKeyTestStarted = true
            guard let toolbar = self.keyboardAccessory?.toolbarView else {
                Self.toolbarKeyTestLog("the terminal has no toolbar")
                return
            }
            Self.toolbarKeyTestLog("sending \(steps.count) keys")
            for (key, modifiers) in steps {
                toolbar.keyPressed(key.keyValue, modifiers: modifiers)
                Self.toolbarKeyTestLog("pressed \(key.rawValue) modifiers=\(modifiers.rawValue)")
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private static func toolbarKeyTestLog(_ message: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toolbar-key-test.log")
        let line = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
