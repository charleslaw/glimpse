import AppKit
import GlimpseCore

@MainActor
final class CustomBackgroundWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let fields = (0..<3).map { _ in NSTextField(string: "") }
    private let colorWell = NSColorWell()
    private let status = NSTextField(labelWithString: "Enter RGB values from 0 to 255, or click the color swatch.")
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let onApply: (BackgroundRGBColor) -> Void

    init(color: BackgroundRGBColor, onApply: @escaping (BackgroundRGBColor) -> Void) {
        self.onApply = onApply
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Custom Background"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        configure(window)
        setColor(color)
    }

    required init?(coder: NSCoder) { nil }

    func controlTextDidChange(_ notification: Notification) {
        let color = enteredColor()
        applyButton.isEnabled = color != nil
        status.stringValue = color == nil ? "Enter whole numbers from 0 to 255." : "Click Apply to use this background in every image window."
        if let color { colorWell.color = color.nsColor }
    }

    private func enteredColor() -> BackgroundRGBColor? {
        let values = fields.compactMap { Int($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 3 else { return nil }
        return BackgroundRGBColor(red: values[0], green: values[1], blue: values[2])
    }

    private func setColor(_ color: BackgroundRGBColor) {
        for (field, component) in zip(fields, [color.red, color.green, color.blue]) { field.stringValue = String(component) }
        colorWell.color = color.nsColor
        applyButton.isEnabled = true
        status.stringValue = "Enter RGB values from 0 to 255, or click the color swatch."
    }

    @objc private func pickedColor() {
        guard let color = colorWell.color.usingColorSpace(.sRGB) else { return }
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return }
        let values = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        if let rgb = BackgroundRGBColor(red: values[0], green: values[1], blue: values[2]) { setColor(rgb) }
    }

    @objc private func applyColor() {
        // End editing first so a click always uses the latest typed RGB values.
        window?.makeFirstResponder(nil)
        guard let color = enteredColor() else { return }
        onApply(color)
        close()
    }

    @objc private func cancel() { close() }

    func windowWillClose(_ notification: Notification) { colorWell.deactivate() }

    override func close() {
        colorWell.deactivate()
        super.close()
    }

    private func configure(_ window: NSWindow) {
        let content = NSView()
        window.contentView = content
        let title = NSTextField(labelWithString: "Custom background color")
        title.font = .boldSystemFont(ofSize: 14)
        let rgbRow = NSStackView()
        rgbRow.orientation = .horizontal
        rgbRow.spacing = 8
        for (field, name) in zip(fields, ["Red", "Green", "Blue"]) {
            field.delegate = self
            field.alignment = .right
            field.setAccessibilityLabel("\(name) (0–255)")
            field.widthAnchor.constraint(equalToConstant: 52).isActive = true
            rgbRow.addArrangedSubview(NSTextField(labelWithString: name))
            rgbRow.addArrangedSubview(field)
        }
        colorWell.target = self
        colorWell.action = #selector(pickedColor)
        colorWell.isContinuous = true
        colorWell.setAccessibilityLabel("Choose background color")
        NSColorPanel.shared.showsAlpha = false
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        applyButton.target = self
        applyButton.action = #selector(applyColor)
        applyButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        for view in [title, rgbRow, colorWell, status, cancelButton, applyButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            colorWell.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            colorWell.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            colorWell.widthAnchor.constraint(equalToConstant: 44),
            colorWell.heightAnchor.constraint(equalToConstant: 28),
            rgbRow.centerYAnchor.constraint(equalTo: colorWell.centerYAnchor),
            rgbRow.leadingAnchor.constraint(equalTo: colorWell.trailingAnchor, constant: 14),
            rgbRow.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            status.topAnchor.constraint(equalTo: colorWell.bottomAnchor, constant: 16),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            applyButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            applyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
        ])
    }
}
