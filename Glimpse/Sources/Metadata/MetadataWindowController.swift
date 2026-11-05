import AppKit
import GlimpseCore

@MainActor
final class MetadataWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let reader = ImageMetadataReader()
    private let table = NSTableView()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "Loading metadata…")
    private var entries: [MetadataEntry] = []
    private var visible: [MetadataEntry] = []
    private var readTask: Task<Void, Never>?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 350)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent(window)
    }

    required init?(coder: NSCoder) { nil }
    deinit { readTask?.cancel() }

    func showMetadata(for file: URL) {
        readTask?.cancel()
        window?.title = "\(file.lastPathComponent) — Metadata"
        window?.representedURL = file
        entries = []
        visible = []
        table.reloadData()
        status.stringValue = "Loading metadata…"
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        let reader = reader
        readTask = Task { @MainActor [weak self] in
            do {
                let report = try await reader.read(file)
                guard let self, !Task.isCancelled else { return }
                self.entries = report.entries
                self.filterChanged()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.status.stringValue = error.localizedDescription
            }
        }
    }

    func windowWillClose(_ notification: Notification) { readTask?.cancel() }

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row) else { return nil }
        let entry = visible[row]
        let text = tableColumn?.identifier.rawValue == "property" ? entry.key : entry.value
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.isSelectable = true
        field.toolTip = text
        return field
    }

    @objc private func filterChanged() {
        let query = search.stringValue
        visible = query.isEmpty ? entries : entries.filter {
            $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
        table.reloadData()
        status.stringValue = "\(visible.count) of \(entries.count) fields"
    }

    @objc private func copyMetadata() {
        let text = entries.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func configureContent(_ window: NSWindow) {
        let content = NSView()
        window.contentView = content
        search.placeholderString = "Filter properties and values"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(filterChanged)

        let property = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("property"))
        property.title = "Property"
        property.width = 330
        let value = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        value.title = "Value"
        value.width = 510
        table.addTableColumn(property)
        table.addTableColumn(value)
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 24
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let copy = NSButton(title: "Copy All Metadata", target: self, action: #selector(copyMetadata))
        status.textColor = .secondaryLabelColor
        for view in [search, scroll, status, copy] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -10),
            copy.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            copy.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            status.centerYAnchor.constraint(equalTo: copy.centerYAnchor),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: copy.trailingAnchor, constant: 12),
        ])
    }
}
