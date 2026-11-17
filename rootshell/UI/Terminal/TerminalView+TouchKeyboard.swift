#if !os(visionOS) && !targetEnvironment(macCatalyst)
import UIKit

extension Ghostty.TerminalView: TerminalTouchKeyboardHost {
    var touchKeyboardThemeColors: ThemeManager.ThemeInfo.ThemeColors? {
        let (name, _) = ThemeOverrideManager.shared.resolveTheme(tabId: containingTabID, windowId: windowId)
        return ThemeManager.shared.themeInfo(for: name)?.colors
    }

    var touchKeyboardCanSend: Bool {
        isFirstResponder && window != nil && !aiAgentOverlayActive && !showComposeOverlay
    }

    func prepareTouchKeyboardSwitch() {
        // Resolve the current input method before replacing its input view.
        commitKoreanCompositionIfNeeded(external: true)
        if markedTextString != nil { unmarkText() }
        endDictationSession()
        invalidateWritingAssistance(resetDocument: true)
        resetDoubleSpaceTracking()
    }

    func touchKeyboardInsert(_ text: String) {
        guard touchKeyboardCanSend else { return }
        touchKeyboardInputDepth += 1
        defer { touchKeyboardInputDepth -= 1 }
        insertText(text)
    }

    func touchKeyboardSend(_ key: String, modifiers: KeyModifiers, shifted: Character?) {
        guard touchKeyboardCanSend else { return }
        // Special keys bypass insertText, but still interrupt consecutive spaces.
        resetDoubleSpaceTracking()
        if key == "\u{7f}", modifiers.isEmpty {
            touchKeyboardInputDepth += 1
            defer { touchKeyboardInputDepth -= 1 }
            deleteBackward()
            return
        }
        invalidateWritingAssistance()
        let special: [String: UIKeyboardHIDUsage] = [
            "\r": .keyboardReturnOrEnter, "\t": .keyboardTab,
            "\u{7f}": .keyboardDeleteOrBackspace,
            "\u{1b}[A": .keyboardUpArrow, "\u{1b}[B": .keyboardDownArrow,
            "\u{1b}[C": .keyboardRightArrow, "\u{1b}[D": .keyboardLeftArrow,
            "\u{1b}[H": .keyboardHome, "\u{1b}[F": .keyboardEnd,
            "\u{1b}[5~": .keyboardPageUp, "\u{1b}[6~": .keyboardPageDown,
            "\u{1b}[3~": .keyboardDeleteForward
        ]
        let functionUsage = KeyID.functionKeyNumber(key).flatMap(Self.functionKeyHIDUsage)
        if let usage = special[key] ?? functionUsage {
            var flags: UIKeyModifierFlags = []
            if modifiers.contains(.control) { flags.insert(.control) }
            if modifiers.contains(.alt) { flags.insert(.alternate) }
            if modifiers.contains(.shift) { flags.insert(.shift) }
            if modifiers.contains(.command) { flags.insert(.command) }
            NotificationCenter.default.post(name: .ghosttyDidReceiveInput, object: self)
            if sendKeyViaGhostty(keyCode: usage, action: .press, modifiers: flags) {
                _ = sendKeyViaGhostty(keyCode: usage, action: .release, modifiers: flags)
                if key == "\r" { invalidateWritingAssistance(resetDocument: true) }
                return
            }
        }
        // This path also preserves local-shell Ctrl-C and Escape overlays,
        // and encodes F1-F12 itself when Ghostty can't.
        keyPressed(key, modifiers: modifiers, shifted: shifted)
    }

    var touchKeyboardSuggestionContext: TerminalTouchKeyboardModel.SuggestionContext? {
        guard keyboardAccessoryController?.usesTouchKeyboard == true,
              refreshWritingAssistanceTraits(), activeKeyboardModifiers.isEmpty else { return nil }
        return TerminalTouchKeyboardModel.SuggestionContext(
            document: correctionContext.document, eligibleCount: correctionContext.eligibleUTF16Count,
            generation: correctionContext.generation, documentGeneration: correctionContext.documentGeneration)
    }

    var touchKeyboardPredictionContext: TerminalTouchKeyboardModel.PredictionSnapshot? {
        guard touchKeyboardCanSend, keyboardAccessoryController?.usesTouchKeyboard == true,
              markedTextString == nil, !koreanCompositionModel.hasActiveComposition,
              correctionContext.dictation == nil, activeKeyboardModifiers.isEmpty,
              virtualModTapModifier == nil, heldHardwareModifiers == .none else { return nil }
        return touchPredictionContext.snapshot
    }

    func touchKeyboardAccept(_ text: String, context: TerminalTouchKeyboardModel.SuggestionContext) {
        guard touchKeyboardCanSend, touchKeyboardSuggestionContext == context else { return }
        _ = applyWritingAssistanceReplacement(context.range, text: text + " ", generation: context.generation)
    }

    func touchKeyboardInvalidateSuggestions() { invalidateWritingAssistance() }
}

// TerminalKeyboardAccessoryHost
extension Ghostty.TerminalView {
    var keyboardTouchKeyboardHost: TerminalTouchKeyboardHost? { self }
    var keyboardTabID: UUID? { containingTabID }
    var keyboardLostFocusOutsideWindow: Bool { lostFocusOutsideWindow }
    func keyboardPrepareTouchKeyboardSwitch() { prepareTouchKeyboardSwitch() }
}

#endif
