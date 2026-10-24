import Foundation

/// A single attribute value from an HLS attribute list.
///
/// HLS distinguishes quoted strings from unquoted values (integers, floats,
/// hexadecimal sequences, resolutions and enumerated strings). The
/// distinction is preserved so playlists re-serialize faithfully.
public enum AttributeValue: Sendable, Hashable, CustomStringConvertible {
    case quoted(String)
    case unquoted(String)

    /// The raw text without quotes.
    public var rawValue: String {
        switch self {
        case .quoted(let value), .unquoted(let value): value
        }
    }

    public var description: String {
        switch self {
        case .quoted(let value): "\"\(value)\""
        case .unquoted(let value): value
        }
    }

    public var integer: UInt64? {
        guard case .unquoted = self else { return nil }
        return HLSNumber.integer(rawValue)
    }
    public var double: Double? {
        guard case .unquoted = self else { return nil }
        return HLSNumber.decimal(rawValue, signed: true)
    }

    /// A `0x`-prefixed hexadecimal sequence as bytes.
    public var hexBytes: [UInt8]? {
        guard case .unquoted = self else { return nil }
        var text = rawValue
        guard text.hasPrefix("0x") || text.hasPrefix("0X") else { return nil }
        text.removeFirst(2)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { return nil }
        if text.count % 2 == 1 { text = "0" + text }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// A `WIDTHxHEIGHT` resolution.
    public var resolution: Resolution? {
        guard case .unquoted = self else { return nil }
        return Resolution(rawValue)
    }
}

/// An ordered list of `KEY=VALUE` attributes.
public struct AttributeList: Sendable, Hashable, Sequence, ExpressibleByDictionaryLiteral {
    public private(set) var entries: [(key: String, value: AttributeValue)]

    public init() { entries = [] }

    public init(_ entries: [(String, AttributeValue)]) {
        self.entries = entries.map { (key: $0.0, value: $0.1) }
    }

    public init(dictionaryLiteral elements: (String, AttributeValue)...) {
        self.init(elements)
    }

    public subscript(key: String) -> AttributeValue? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
            } else if let newValue {
                entries.append((key: key, value: newValue))
            }
        }
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var keys: [String] { entries.map(\.key) }

    public func makeIterator() -> IndexingIterator<[(key: String, value: AttributeValue)]> {
        entries.makeIterator()
    }

    /// Removes and returns the attributes whose keys are not in `known`.
    func excluding(_ known: Set<String>) -> AttributeList {
        var copy = self
        copy.entries.removeAll { known.contains($0.key) }
        return copy
    }

    mutating func merge(_ other: AttributeList) {
        for (key, value) in other where self[key] == nil {
            entries.append((key: key, value: value))
        }
    }

    public static func == (lhs: AttributeList, rhs: AttributeList) -> Bool {
        lhs.entries.count == rhs.entries.count
            && zip(lhs.entries, rhs.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public func hash(into hasher: inout Hasher) {
        for (key, value) in entries {
            hasher.combine(key)
            hasher.combine(value)
        }
    }

    // MARK: Parsing & serialization

    /// Parses an attribute list such as `BANDWIDTH=1280000,CODECS="avc1.4d401f,mp4a.40.2"`.
    ///
    public static func parse(_ text: Substring) throws -> AttributeList {
        var list = AttributeList()
        var names: Set<String> = []
        var index = text.startIndex
        func fail(_ message: String) throws -> Never {
            throw PlaylistError.invalidTag(message, line: 0)
        }
        guard !text.isEmpty else { try fail("Empty attribute list") }
        while index < text.endIndex {
            let keyStart = index
            while index < text.endIndex, text[index] != "=", text[index] != "," { index = text.index(after: index) }
            let key = String(text[keyStart..<index])
            guard !key.isEmpty, key.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  index < text.endIndex, text[index] == "=" else { try fail("Invalid attribute name or separator: \(key)") }
            guard names.insert(key).inserted else { try fail("Duplicate attribute: \(key)") }
            index = text.index(after: index)
            let value: AttributeValue
            if index < text.endIndex, text[index] == "\"" {
                index = text.index(after: index)
                let valueStart = index
                while index < text.endIndex, text[index] != "\"" { index = text.index(after: index) }
                value = .quoted(String(text[valueStart..<index]))
                guard index < text.endIndex else { try fail("Unterminated quoted attribute: \(key)") }
                index = text.index(after: index)
                guard !value.rawValue.isEmpty || key == "VALUE" || key == "RECENTLY-REMOVED-DATERANGES" else { try fail("Empty quoted attribute: \(key)") }
                guard !value.rawValue.contains("\r"), !value.rawValue.contains("\n") else { try fail("Invalid quoted attribute: \(key)") }
                guard index == text.endIndex || text[index] == "," else { try fail("Junk after quoted attribute: \(key)") }
            } else {
                let valueStart = index
                while index < text.endIndex, text[index] != "," { index = text.index(after: index) }
                let raw = String(text[valueStart..<index])
                guard !raw.isEmpty, raw.utf8.allSatisfy({ $0 > 32 && $0 < 127 && $0 != 34 }) else { try fail("Invalid unquoted attribute: \(key)") }
                value = .unquoted(raw)
            }
            if index < text.endIndex {
                index = text.index(after: index)
                guard index < text.endIndex else { try fail("Trailing attribute separator") }
            }
            list.entries.append((key: key, value: value))
        }
        return list
    }

    public var serialized: String {
        entries.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}

// MARK: - Builders used by the typed models

extension AttributeList {
    mutating func set(_ key: String, quoted value: String?) {
        if let value { self[key] = .quoted(value) }
    }

    mutating func set(_ key: String, unquoted value: String?) {
        if let value { self[key] = .unquoted(value) }
    }

    mutating func set(_ key: String, int value: UInt64?) {
        if let value { self[key] = .unquoted(String(value)) }
    }

    mutating func set(_ key: String, double value: Double?) {
        if let value { self[key] = .unquoted(formatDecimal(value)) }
    }

    mutating func set(_ key: String, bool value: Bool?) {
        if let value { self[key] = .unquoted(value ? "YES" : "NO") }
    }

    func bool(_ key: String) -> Bool? {
        guard let raw = self[key]?.rawValue else { return nil }
        return raw == "YES"
    }
}

/// Formats a decimal without exponent notation or a trailing `.0` noise
/// beyond what is needed, preserving the shortest round-trip representation.
func formatDecimal(_ value: Double) -> String {
    guard value.isFinite else { return String(value) }
    if value == 0 { return "0" }
    let text = String(value)
    let parts = text.lowercased().split(separator: "e")
    guard parts.count == 2, let exponent = Int(parts[1]) else {
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
    let negative = parts[0].hasPrefix("-")
    let mantissa = negative ? parts[0].dropFirst() : parts[0]
    let components = mantissa.split(separator: ".")
    let digits = components.joined()
    let point = components[0].count + exponent
    let decimal: String
    if point <= 0 {
        decimal = "0." + String(repeating: "0", count: -point) + digits
    } else if point >= digits.count {
        decimal = digits + String(repeating: "0", count: point - digits.count)
    } else {
        let index = digits.index(digits.startIndex, offsetBy: point)
        decimal = digits[..<index] + "." + digits[index...]
    }
    return (negative ? "-" : "") + decimal
}

/// A video resolution, `WIDTHxHEIGHT`.
public struct Resolution: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var width: UInt64
    public var height: UInt64

    public init(width: UInt64, height: UInt64) {
        self.width = width
        self.height = height
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = HLSNumber.integer(String(parts[0])), let height = HLSNumber.integer(String(parts[1])) else { return nil }
        self.init(width: width, height: height)
    }

    /// `width × height`, saturating instead of overflowing on absurd values.
    public var pixelCount: UInt64 {
        let (product, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow ? UInt64.max : product
    }
    public var description: String { "\(width)x\(height)" }

    public static func < (lhs: Resolution, rhs: Resolution) -> Bool {
        let a = lhs.width.multipliedFullWidth(by: lhs.height)
        let b = rhs.width.multipliedFullWidth(by: rhs.height)
        return (a.high, a.low) < (b.high, b.low)
    }
}

enum HLSNumber {
    static func integer(_ text: String) -> UInt64? {
        guard (1...20).contains(text.utf8.count), text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return UInt64(text)
    }

    static func decimal(_ text: String, signed: Bool = false) -> Double? {
        let digits = signed && text.hasPrefix("-") ? String(text.dropFirst()) : text
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
