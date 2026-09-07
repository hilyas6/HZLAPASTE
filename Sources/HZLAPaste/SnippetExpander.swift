import AppKit
import Carbon.HIToolbox

/// Whole-word exact match: the buffer (whatever's been typed since the last
/// delimiter) must equal a snippet's keyword exactly — case-sensitive, so
/// "Sig" and "sig" can be different snippets, matching how Raycast/TextExpander
/// behave by default. Pure and side-effect free so it's unit-testable without
/// any AppKit/CGEventTap machinery.
func matchSnippet(buffer: String, in snippets: [Snippet]) -> Snippet? {
    guard !buffer.isEmpty else { return nil }
    return snippets.first { $0.keyword == buffer }
}

/// Global text expansion: watches keystrokes system-wide (via a listen-only
/// CGEventTap, the same Accessibility-gated mechanism every macOS text
/// expander uses) for a registered snippet keyword followed by a delimiter,
/// then deletes the keyword and pastes the snippet body in its place.
///
/// Deliberately narrow in what it does with what it sees: it only ever keeps
/// the last ~40 characters in memory to check for a keyword match, never
/// writes typed text anywhere, and stops looking entirely the moment macOS
/// reports Secure Event Input is active (a real password field is focused) —
/// that's a deliberate OS defense against exactly this class of tool, and no
/// app can or should try to work around it.
final class SnippetExpander {
    private let snippetStore: SnippetStore
    private let monitor: ClipboardMonitor
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""

    /// Punctuation allowed inside a keyword in addition to letters/numbers —
    /// notably semicolon/colon, the prefixes suggested in the Snippets editor
    /// UI ("a distinctive prefix like ';' or ':' avoids accidentally
    /// triggering on real words") specifically so those prefixes aren't
    /// themselves misread as the delimiter that ends the word.
    private static let keywordPunctuation: Set<Character> = [";", ":", "@", "#", "!", "\\", "_", "-"]

    init(snippetStore: SnippetStore, monitor: ClipboardMonitor) {
        self.snippetStore = snippetStore
        self.monitor = monitor
    }

    /// Safe to call repeatedly (e.g. every time the bar opens) — no-ops once
    /// already running, and picks up Accessibility being granted after launch
    /// without requiring an app restart.
    func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let expander = Unmanaged<SnippetExpander>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = expander.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                expander.handle(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(_ cgEvent: CGEvent) {
        guard !IsSecureEventInputEnabled() else { buffer = ""; return }
        guard AppSettings.snippetExpansionEnabled else { return }
        if let bundleID = ForegroundAppTracker.shared.lastForegroundApp?.bundleIdentifier, ExcludedApps.contains(bundleID) {
            buffer = ""
            return
        }

        guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return }
        // Shortcuts (⌘C, ⌃Tab, etc.) aren't typing — don't let them pollute the buffer.
        guard nsEvent.modifierFlags.intersection([.command, .control, .option]).isEmpty else { buffer = ""; return }
        guard let char = nsEvent.charactersIgnoringModifiers?.first else { return }

        if char.isLetter || char.isNumber || Self.keywordPunctuation.contains(char) {
            buffer.append(char)
            if buffer.count > 40 { buffer.removeFirst(buffer.count - 40) }
            return
        }

        // Any other character (space, tab, return, punctuation) delimits a word:
        // check what was just typed, then start fresh regardless of the outcome.
        let candidate = buffer
        buffer = ""
        guard let snippet = matchSnippet(buffer: candidate, in: snippetStore.snippets) else { return }
        expand(snippet, delimiter: char)
    }

    private func expand(_ snippet: Snippet, delimiter: Character) {
        let pasteboard = NSPasteboard.general
        let savedItem = pasteboard.pasteboardItems?.first
        let savedTypesData: [(NSPasteboard.PasteboardType, Data)] =
            savedItem?.types.compactMap { type in savedItem?.data(forType: type).map { (type, $0) } } ?? []

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            deleteCharacters(count: snippet.keyword.count + 1) // + the delimiter just typed

            pasteboard.clearContents()
            pasteboard.setString(snippet.body, forType: .string)
            monitor.markOwnWrite(changeCount: pasteboard.changeCount)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.postKeystroke(keyCode: 9, flags: .maskCommand) // ⌘V
                self.postDelimiter(delimiter)
                self.snippetStore.recordUse(snippet.id)

                // Restore whatever was really on the clipboard before we borrowed it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    pasteboard.clearContents()
                    if !savedTypesData.isEmpty {
                        let restored = NSPasteboardItem()
                        for (type, data) in savedTypesData { restored.setData(data, forType: type) }
                        pasteboard.writeObjects([restored])
                    }
                    self.monitor.markOwnWrite(changeCount: pasteboard.changeCount)
                }
            }
        }
    }

    private func deleteCharacters(count: Int) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true), // delete/backspace
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) else { continue }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Re-types the delimiter consumed by the backspaces so the cursor ends up
    /// exactly where normal typing would have left it. Space/Tab/Return use
    /// their real keycodes (some apps hook the keycode itself, e.g. Return to
    /// submit a message) rather than a synthesized Unicode character.
    private func postDelimiter(_ char: Character) {
        switch char {
        case " ": postKeystroke(keyCode: 49, flags: [])
        case "\t": postKeystroke(keyCode: 48, flags: [])
        case "\r", "\n": postKeystroke(keyCode: 36, flags: [])
        default: postUnicodeCharacter(char)
        }
    }

    private func postUnicodeCharacter(_ char: Character) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        let utf16 = Array(String(char).utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
