import Foundation

enum ActionPlaceholders {
    static let names = ["filename", "filepath", "parentpath"]

    static func validate(_ text: String) throws {
        let remainder = names.reduce(text) { $0.replacingOccurrences(of: "{\($1)}", with: "") }
        guard !remainder.contains("{"), !remainder.contains("}") else {
            throw ActionsConfigurationError.invalid("Use the full placeholder names: {filename}, {filepath}, or {parentpath}.")
        }
    }

    static func expand(_ text: String, file: URL, encodeURL: Bool = false) -> String {
        let values = ["filename": file.lastPathComponent, "filepath": file.path,
                      "parentpath": file.deletingLastPathComponent().path]
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
