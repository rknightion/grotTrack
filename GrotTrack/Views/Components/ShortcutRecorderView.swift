import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var key: String
    @Binding var modifiers: Int
    var onChanged: (() -> Void)?

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Text(displayText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 120)
            .background(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .onTapGesture {
                startRecording()
            }
            .onDisappear {
                removeMonitor()
            }
    }

    private var displayText: String {
        if isRecording {
            return "Press shortcut\u{2026}"
        }
        if key.isEmpty {
            return "Click to set"
        }
        return Self.formatShortcut(key: key, modifiers: modifiers)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape cancels recording without changing the shortcut
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Require at least one modifier key (Ctrl, Option, Shift, or Cmd)
        let requiredModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        guard !flags.isDisjoint(with: requiredModifiers) else { return }

        let characters = event.charactersIgnoringModifiers ?? ""
        guard !characters.isEmpty else { return }

        key = characters.lowercased()
        modifiers = Int(flags.rawValue)
        stopRecording()
        onChanged?()
    }

    private func stopRecording() {
        isRecording = false
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Formatting

    static func formatShortcut(key: String, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var parts: [String] = []

        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Opt") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Cmd") }

        parts.append(key.uppercased())
        return parts.joined(separator: "+")
    }
}
