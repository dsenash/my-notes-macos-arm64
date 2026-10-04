import AppKit

enum Dialogs {
    static func prompt(title: String, message: String = "", defaultValue: String = "", ok: String = "OK") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Отмена")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.layout()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, ok: String, destructive: Bool = true) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        let button = alert.addButton(withTitle: ok)
        if destructive { button.hasDestructiveAction = true }
        alert.addButton(withTitle: "Отмена")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func info(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
