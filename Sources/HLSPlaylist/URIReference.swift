import Foundation
#if SWIFT_PACKAGE
import CURIParser
#endif

/// An RFC 3986 reference. Retains original encoded bytes; parsing never uses URL.
#if canImport(ObjectiveC)
@objc(URIReference)
#endif
public final class URIReference: NSObject {
    private let input: UnsafeMutablePointer<CChar>
    private var parsed = UriUriA()
    private let original: String

    #if canImport(ObjectiveC)
    @objc(initWithString:)
    #endif
    public init?(_ string: String) {
        let bytes = string.utf8CString
        let input = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
        input.initialize(from: Array(bytes), count: bytes.count)
        self.input = input
        original = string
        super.init()
        guard uriParseSingleUriExA(&parsed, input, input + string.utf8.count, nil) == 0 else {
            return nil
        }
    }

    deinit {
        uriFreeUriMembersA(&parsed)
        input.deallocate()
    }

    private func text(_ range: UriTextRangeA) -> String? {
        guard let first = range.first, let end = range.afterLast else { return nil }
        return String(decoding: UnsafeBufferPointer(start: first, count: end - first).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var scheme: String? { text(parsed.scheme) }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var host: String? { text(parsed.hostText) }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var userInfo: String? { text(parsed.userInfo) }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var port: String? { text(parsed.portText) }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var path: String {
        var segments: [String] = []
        var node = parsed.pathHead
        while let current = node {
            segments.append(text(current.pointee.text) ?? "")
            node = current.pointee.next
        }
        return ((parsed.absolutePath != 0 || (host != nil && !segments.isEmpty)) ? "/" : "")
            + segments.joined(separator: "/")
    }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var query: String? { text(parsed.query) }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var fragment: String? { text(parsed.fragment) }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public var string: String { original }

    func valid(relative: Bool = false) -> Bool { !relative || scheme == nil }

    // Encode non-URI characters for the legacy resolver API. HLS parsing itself
    // remains strict. This Foundation String operation does not recompose a URL.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?#[]%"
        )) ?? value
    }

    #if canImport(ObjectiveC)
    @objc
    #endif
    public func resolving(against base: String) -> String? {
        guard let base = URIReference(base), base.scheme != nil else { return nil }
        defer { withExtendedLifetime(base) {} }
        var result = UriUriA()
        defer { uriFreeUriMembersA(&result) }
        guard uriAddBaseUriA(&result, &parsed, &base.parsed) == 0 else { return nil }
        // uriparser normally expands IPv6 when rendering. Its IPvFuture branch
        // writes the raw bracketed host, allowing us to retain the parsed spelling.
        // Restore ownership fields before releasing the result.
        let hostData = result.hostData
        if hostData.ip6 != nil {
            result.hostData.ip6 = nil
            result.hostData.ipFuture = result.hostText
        }
        defer { result.hostData = hostData }
        var count: Int32 = 0
        guard uriToStringCharsRequiredA(&result, &count) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(count) + 1)
        guard uriToStringA(&buffer, &result, count + 1, nil) == 0 else { return nil }
        return String(decoding: buffer.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func queryValue(named name: String) -> String? {
        guard parsed.query.first != nil else { return nil }
        var list: UnsafeMutablePointer<UriQueryListA>?
        guard uriDissectQueryMallocExA(&list, nil, parsed.query.first, parsed.query.afterLast,
                                      0, URI_BR_DONT_TOUCH) == 0 else { return nil }
        defer { uriFreeQueryListA(list) }
        var node = list
        while let current = node {
            if let key = current.pointee.key, String(validatingCString: key) == name {
                return current.pointee.value.flatMap { String(validatingCString: $0) }
            }
            node = current.pointee.next
        }
        return nil
    }
}
