import Foundation

enum ActionPlaceholders {
    static let names = ["filename", "filepath", "fname", "fpath", "ppath"]

    static func validate(_ text: String) throws {
        let remainder = names.reduce(text) { $0.replacingOccurrences(of: "{\($1)}", with: "") }
        guard !remainder.contains("{"), !remainder.contains("}") else {
            throw ActionsConfigurationError.invalid("Use {fname}, {fpath}, {ppath}, {filename}, or {filepath} placeholders.")
        }
    }

    static func expand(_ text: String, file: URL, encodeURL: Bool = false) -> String {
        let values = ["fname": file.lastPathComponent, "filename": file.lastPathComponent,
                      "fpath": file.path, "filepath": file.path,
                      "ppath": file.deletingLastPathComponent().path]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        var output = "", cursor = text.startIndex
        // Scan only the template: braces/quotes inside filenames remain data.
        while cursor < text.endIndex {
            if text[cursor] == "{", let end = text[cursor...].firstIndex(of: "}"),
               let value = values[String(text[text.index(after: cursor)..<end])] {
                output += encodeURL ? (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") : value
                cursor = text.index(after: end)
            } else {
                output.append(text[cursor])
                cursor = text.index(after: cursor)
            }
        }
        return output
    }
}
