import AppKit

/// Модальное окно с индикатором и процентами.
/// `present()` блокирует вызывающий поток (как NSAlert.runModal) и возвращается после `dismiss()`.
/// Все методы — только из главного потока.
final class ProgressModal: NSObject {
    private let window: NSWindow
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Отмена", target: nil, action: nil)

    private var stopped = false
    private var running = false

    /// Нажата «Отмена».
    var onCancel: (() -> Void)?
    /// Вызывается после закрытия окна — удобное место показать итоговое сообщение.
    var onClosed: (() -> Void)?

    init(title: String, message: String, cancellable: Bool = true) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false

        titleLabel.stringValue = message
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2

        detailLabel.stringValue = " "
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        bar.style = .bar
        bar.isIndeterminate = true
        bar.minValue = 0
        bar.maxValue = 100
        bar.startAnimation(nil)

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.isHidden = !cancellable

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [titleLabel, bar, detailLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            content.widthAnchor.constraint(equalToConstant: 440)
        ])
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
    }

    /// `fraction` = nil — неопределённый прогресс; иначе 0…1 (показывается как процент).
    func update(message: String? = nil, detail: String? = nil, fraction: Double?) {
        if let message { titleLabel.stringValue = message }
        if let fraction {
            let clamped = min(1, max(0, fraction))
            if bar.isIndeterminate {
                bar.stopAnimation(nil)
                bar.isIndeterminate = false
            }
            bar.doubleValue = clamped * 100
            detailLabel.stringValue = detail ?? "\(Int((clamped * 100).rounded()))%"
        } else {
            if !bar.isIndeterminate { bar.isIndeterminate = true }
            bar.startAnimation(nil)
            detailLabel.stringValue = detail ?? " "
        }
    }

    func setCancelEnabled(_ enabled: Bool) {
        cancelButton.isEnabled = enabled
    }

    /// Показывает окно модально и ждёт `dismiss()`.
    func present() {
        guard !stopped else {
            onClosed?()
            return
        }
        running = true
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        NSApp.runModal(for: window)
        window.orderOut(nil)
        running = false
        onClosed?()
    }

    /// Закрывает окно (можно вызывать и до `present()` — тогда окно не покажется).
    func dismiss() {
        stopped = true
        guard running else { return }
        NSApp.stopModal()
        // Будим цикл событий: stopModal, вызванный не из обработчика события, иначе сработает не сразу.
        if let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
        ) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    @objc private func cancelPressed() {
        cancelButton.isEnabled = false
        cancelButton.title = "Отмена…"
        onCancel?()
    }
}
