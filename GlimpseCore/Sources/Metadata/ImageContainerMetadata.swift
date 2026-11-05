import Foundation

/// Small, bounds-checked container inspection supplements properties ImageIO
/// does not expose (notably GIF palette sizes and JPEG quantization tables).
enum ImageContainerMetadata {
    static func inspect(_ data: Data) -> [MetadataEntry] {
        if data.starts(with: [71, 73, 70, 56]) { return gif(data) }
        if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return png(data) }
        if data.starts(with: [255, 216]) { return jpeg(data) }
        return []
    }

    private static func png(_ data: Data) -> [MetadataEntry] {
        guard data.count >= 33, data.subdata(in: 12..<16) == Data("IHDR".utf8) else { return [] }
        let colors = [0: "Grayscale", 2: "Truecolor", 3: "Indexed palette", 4: "Grayscale + alpha", 6: "Truecolor + alpha"]
        return [MetadataEntry("PNG.Bit Depth", String(data[24])),
                MetadataEntry("PNG.Color Type", colors[Int(data[25])] ?? String(data[25])),
                MetadataEntry("PNG.Compression", data[26] == 0 ? "Deflate (lossless)" : "Method \(data[26])"),
                MetadataEntry("PNG.Filter Method", String(data[27])),
                MetadataEntry("PNG.Interlace", [0: "None", 1: "Adam7"][Int(data[28])] ?? "Unknown (\(data[28]))")]
    }

    private static func gif(_ data: Data) -> [MetadataEntry] {
        guard data.count >= 13 else { return [] }
        let packed = data[10]
        let globalColors = packed & 0x80 == 0 ? 0 : 1 << (Int(packed & 7) + 1)
        var entries = Entries([MetadataEntry("GIF.Version", String(data: data.prefix(6), encoding: .ascii) ?? ""),
                       MetadataEntry("GIF.Compression", "LZW (lossless)"),
                       MetadataEntry("GIF.Global Palette Entries", String(globalColors)),
                       MetadataEntry("GIF.Color Resolution (bits)", String(((packed >> 4) & 7) + 1))])
        var cursor = Cursor(data: data, offset: 13)
        guard cursor.skip(globalColors * 3) else { return entries.values }
        var frame = 0, comment = 0
        while !Task.isCancelled, !entries.isFull, let marker = cursor.byte(), frame < 1_000 {
            if marker == 0x3b { break }
            if marker == 0x21 {
                guard let label = cursor.byte() else { break }
                guard let bytes = cursor.subBlocks(capture: label == 0xfe) else { break }
                if label == 0xfe {
                    comment += 1
                    let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
                    entries.append(MetadataEntry("GIF.Comment[\(comment)]", text))
                }
            } else if marker == 0x2c {
                guard let descriptor = cursor.take(9) else { break }
                frame += 1
                let local = descriptor[8]
                let localColors = local & 0x80 == 0 ? 0 : 1 << (Int(local & 7) + 1)
                entries.append(MetadataEntry("GIF.Frame[\(frame)].Palette Entries", String(localColors == 0 ? globalColors : localColors)))
                entries.append(MetadataEntry("GIF.Frame[\(frame)].Palette Source", localColors == 0 ? "Global" : "Local"))
                entries.append(MetadataEntry("GIF.Frame[\(frame)].Interlaced", local & 0x40 == 0 ? "No" : "Yes"))
                guard cursor.skip(localColors * 3), let codeSize = cursor.byte() else { break }
                entries.append(MetadataEntry("GIF.Frame[\(frame)].LZW Minimum Code Size", String(codeSize)))
                guard cursor.subBlocks(capture: false) != nil else { break }
            } else { break }
        }
        return entries.values
    }

    private static func jpeg(_ data: Data) -> [MetadataEntry] {
        var entries = Entries([MetadataEntry("JPEG.Compression", "JPEG")])
        var offset = 2, comments = 0
        let frameMarkers: Set<UInt8> = [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]
        while offset + 1 < data.count, !entries.isFull {
            guard data[offset] == 0xff else { break }
            while offset < data.count, data[offset] == 0xff { offset += 1 }
            guard offset < data.count else { break }
            let marker = data[offset]; offset += 1
            if marker == 0xda || marker == 0xd9 { break }
            if marker == 0x01 || (0xd0...0xd8).contains(marker) { continue }
            guard offset + 1 < data.count else { break }
            let length = Int(data[offset]) * 256 + Int(data[offset + 1])
            guard length >= 2, length <= data.count - offset else { break }
            let start = offset + 2, end = offset + length
            if frameMarkers.contains(marker), length >= 8 {
                let modes: [UInt8: String] = [0xc0: "Baseline DCT", 0xc1: "Extended sequential DCT", 0xc2: "Progressive DCT", 0xc3: "Lossless"]
                entries.append(MetadataEntry("JPEG.Coding Mode", modes[marker] ?? String(format: "SOF 0x%02x", marker)))
                entries.append(MetadataEntry("JPEG.Sample Precision (bits)", String(data[start])))
                let components = Int(data[start + 5])
                entries.append(MetadataEntry("JPEG.Components", String(components)))
                if length >= 8 + components * 3 {
                    for index in 0..<components {
                        let position = start + 6 + index * 3, sampling = data[position + 1]
                        entries.append(MetadataEntry("JPEG.Component[\(data[position])].Sampling", "H=\(sampling >> 4), V=\(sampling & 15); quantization table \(data[position + 2])"))
                    }
                }
            } else if marker == 0xfe {
                comments += 1
                let bytes = data.subdata(in: start..<min(end, start + 65_536))
                entries.append(MetadataEntry("JPEG.Comment[\(comments)]", String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""))
            } else if marker == 0xdb {
                var position = start
                while position < end {
                    let header = data[position]; position += 1
                    let precision = Int(header >> 4)
                    guard precision <= 1 else { break }
                    let bytes = precision == 0 ? 64 : 128
                    guard bytes <= end - position else { break }
                    var values: [String] = []
                    for index in 0..<64 {
                        let value = precision == 0 ? Int(data[position + index]) : Int(data[position + index * 2]) * 256 + Int(data[position + index * 2 + 1])
                        values.append(String(value))
                    }
                    entries.append(MetadataEntry("JPEG.Quantization Table[\(header & 15)]", "\(precision == 0 ? 8 : 16)-bit; zigzag values: \(values.joined(separator: ", "))"))
                    position += bytes
                }
            }
            offset = end
        }
        return entries.values
    }

    private struct Entries {
        private var rows: [MetadataEntry] = []
        private var remaining = 4 * 1024 * 1024
        private(set) var isFull = false

        init(_ initial: [MetadataEntry]) { initial.forEach { append($0) } }

        mutating func append(_ entry: MetadataEntry) {
            let cost = entry.key.utf8.count + entry.value.utf8.count
            guard !isFull, rows.count < 10_000, cost <= remaining else { isFull = true; return }
            rows.append(entry)
            remaining -= cost
        }

        var values: [MetadataEntry] {
            rows + (isFull ? [MetadataEntry("Inspector.Container Limit", "Additional container fields exceed the display budget.")] : [])
        }
    }

    private struct Cursor {
        let data: Data
        var offset: Int
        mutating func byte() -> UInt8? {
            guard offset < data.count else { return nil }
            defer { offset += 1 }
            return data[offset]
        }
        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, count <= data.count - offset else { return false }
            offset += count
            return true
        }
        mutating func take(_ count: Int) -> Data? {
            let start = offset
            guard skip(count) else { return nil }
            return data.subdata(in: start..<offset)
        }
        mutating func subBlocks(capture: Bool) -> Data? {
            var collected = Data()
            while let length = byte() {
                guard !Task.isCancelled else { return nil }
                if length == 0 { return collected }
                if !capture || collected.count >= 65_536 {
                    guard skip(Int(length)) else { return nil }
                    continue
                }
                guard let bytes = take(Int(length)) else { return nil }
                if capture, collected.count < 65_536 {
                    collected.append(bytes.prefix(65_536 - collected.count))
                }
            }
            return nil
        }
    }
}
