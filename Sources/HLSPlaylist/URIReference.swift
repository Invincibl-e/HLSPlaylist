import Foundation

/// RFC 3986 component boundaries and grammar on the original ASCII URI bytes.
/// Parsing, validation and percent decoding do not use Foundation URL APIs.
struct URIReference {
    static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    static let subdelims = Set("!$&'()*+,;=".utf8)
    static let pchar = unreserved.union(subdelims).union([58, 64])
    static let uriCharacters = pchar.union(Set("/?#[]%".utf8))
    var scheme: String?
    var authority: String?
    var path: String
    var query: String?
    var fragment: String?

    init?(_ string: String) {
        var rest = string[...]
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        if let question = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: question)...])
            rest = rest[..<question]
        }
        if let colon = rest.firstIndex(of: ":"), !rest[..<colon].contains("/") {
            let candidate = String(rest[..<colon])
            if Self.validScheme(candidate) {
                scheme = candidate
                rest = rest[rest.index(after: colon)...]
            }
        }
        if rest.hasPrefix("//") {
            rest = rest.dropFirst(2)
            let slash = rest.firstIndex(of: "/") ?? rest.endIndex
            authority = String(rest[..<slash])
            rest = rest[slash...]
        }
        path = String(rest)
    }

    var string: String {
        (scheme.map { $0 + ":" } ?? "") + (authority.map { "//" + $0 } ?? "") + path
            + (query.map { "?" + $0 } ?? "") + (fragment.map { "#" + $0 } ?? "")
    }

    func valid(relative: Bool = false) -> Bool {
        if relative && scheme != nil { return false }
        if let authority, !Self.validAuthority(authority) { return false }
        if authority != nil && !path.isEmpty && !path.hasPrefix("/") { return false }
        if authority == nil && path.hasPrefix("//") { return false }
        if scheme == nil && authority == nil && !path.hasPrefix("/"),
           path.prefix(while: { $0 != "/" }).contains(":") { return false }
        return Self.validComponent(path, allowed: Self.pchar.union([47]))
            && query.map { Self.validComponent($0, allowed: Self.pchar.union([47, 63])) } != false
            && fragment.map { Self.validComponent($0, allowed: Self.pchar.union([47, 63])) } != false
    }

    static func validScheme(_ value: String) -> Bool {
        let letters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
        guard let first = value.utf8.first, letters.contains(first) else { return false }
        return value.utf8.allSatisfy { letters.contains($0) || (48...57).contains($0) || [43, 45, 46].contains($0) }
    }

    static func validComponent(_ value: String, allowed: Set<UInt8>) -> Bool {
        let bytes = Array(value.utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 37 {
                guard i + 2 < bytes.count, hex(bytes[i + 1]) != nil, hex(bytes[i + 2]) != nil else { return false }
                i += 3
            } else {
                guard allowed.contains(bytes[i]) else { return false }
                i += 1
            }
        }
        return true
    }

    private static func validAuthority(_ value: String) -> Bool {
        var hostPort = value[...]
        if let at = hostPort.firstIndex(of: "@") {
            guard validComponent(String(hostPort[..<at]), allowed: unreserved.union(subdelims).union([58])) else { return false }
            hostPort = hostPort[hostPort.index(after: at)...]
        }
        if hostPort.hasPrefix("[") {
            guard let closing = hostPort.firstIndex(of: "]") else { return false }
            let literal = String(hostPort[hostPort.index(after: hostPort.startIndex)..<closing])
            let suffix = hostPort[hostPort.index(after: closing)...]
            guard suffix.isEmpty || (suffix.hasPrefix(":") && suffix.dropFirst().utf8.allSatisfy({ (48...57).contains($0) })) else { return false }
            return validIPLiteral(literal)
        }
        let colon = hostPort.firstIndex(of: ":") ?? hostPort.endIndex
        guard validComponent(String(hostPort[..<colon]), allowed: unreserved.union(subdelims)) else { return false }
        return colon == hostPort.endIndex || hostPort[hostPort.index(after: colon)...].utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validIPLiteral(_ value: String) -> Bool {
        // IPvFuture: "v" 1*HEXDIG "." 1*(unreserved / sub-delims / ":").
        if value.first == "v" || value.first == "V" {
            guard let dot = value.firstIndex(of: ".") else { return false }
            let version = value[value.index(after: value.startIndex)..<dot]
            let address = value[value.index(after: dot)...]
            return !version.isEmpty && version.utf8.allSatisfy({ hex($0) != nil })
                && !address.isEmpty && address.utf8.allSatisfy { unreserved.contains($0) || subdelims.contains($0) || $0 == 58 }
        }
        // IPv6: eight h16 units, at most one "::", optional final IPv4 (two units).
        let halves = value.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        var units = 0
        for (halfIndex, half) in halves.enumerated() {
            if half.isEmpty {
                guard halves.count == 2 else { return false }
                continue
            }
            let groups = half.split(separator: ":", omittingEmptySubsequences: false)
            for (index, group) in groups.enumerated() {
                if group.contains(".") {
                    guard halfIndex == halves.count - 1, index == groups.count - 1,
                          !(halves.count == 2 && halves[1].isEmpty), validIPv4(group) else { return false }
                    units += 2
                } else {
                    guard (1...4).contains(group.utf8.count), group.utf8.allSatisfy({ hex($0) != nil }) else { return false }
                    units += 1
                }
            }
        }
        return halves.count == 2 ? units < 8 : units == 8
    }

    private static func validIPv4(_ value: Substring) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) })
                && ($0.count == 1 || $0.first != "0") && (Int($0).map { $0 <= 255 } ?? false)
        }
    }

    static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    static func encode(_ value: String) -> String {
        let hexDigits = Array("0123456789ABCDEF".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if uriCharacters.contains(byte) {
                output.append(byte)
            } else {
                output.append(contentsOf: [37, hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 15)]])
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func decode(_ value: Substring) -> String? {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 37 {
                guard i + 2 < bytes.count, let high = hex(bytes[i + 1]), let low = hex(bytes[i + 2]) else { return nil }
                output.append(high * 16 + low)
                i += 3
            } else {
                output.append(bytes[i])
                i += 1
            }
        }
        return String(bytes: output, encoding: .utf8)
    }

    func queryValue(named name: String) -> String? {
        guard let query else { return nil }
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            let equal = pair.firstIndex(of: "=") ?? pair.endIndex
            if Self.decode(pair[..<equal]) == name {
                return equal == pair.endIndex ? nil : Self.decode(pair[pair.index(after: equal)...])
            }
        }
        return nil
    }
}
