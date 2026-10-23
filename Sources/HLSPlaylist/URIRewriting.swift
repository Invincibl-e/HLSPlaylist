import Foundation

/// The role of a URI inside a playlist, passed to URI transforms.
public enum URIRole: Sendable, Hashable {
    case variant
    case iFrameVariant
    case imageVariant
    case rendition
    case segment
    case partialSegment
    case initializationSection
    case key
    case sessionData
    case preloadHint
    case renditionReport
    case contentSteering
    case interstitialAsset
    case interstitialAssetList
}

extension MultivariantPlaylist {
    /// Returns a copy with every URI transformed, e.g. to route requests
    /// through a local proxy or to append authentication tokens.
    public func mapURIs(_ transform: (String, URIRole) throws -> String) rethrows -> MultivariantPlaylist {
        var copy = self
        for index in copy.variants.indices {
            copy.variants[index].uri = try transform(copy.variants[index].uri, .variant)
        }
        for index in copy.iFrameVariants.indices {
            copy.iFrameVariants[index].uri = try transform(copy.iFrameVariants[index].uri, .iFrameVariant)
        }
        for index in copy.imageVariants.indices {
            copy.imageVariants[index].uri = try transform(copy.imageVariants[index].uri, .imageVariant)
        }
        for index in copy.renditions.indices {
            if let uri = copy.renditions[index].uri { copy.renditions[index].uri = try transform(uri, .rendition) }
        }
        for index in copy.sessionData.indices {
            if let uri = copy.sessionData[index].uri { copy.sessionData[index].uri = try transform(uri, .sessionData) }
        }
        for index in copy.sessionKeys.indices {
            if let uri = copy.sessionKeys[index].uri { copy.sessionKeys[index].uri = try transform(uri, .key) }
        }
        if let uri = copy.contentSteering?["SERVER-URI"]?.rawValue {
            copy.contentSteering?["SERVER-URI"] = .quoted(try transform(uri, .contentSteering))
        }
        return copy
    }

    /// Returns a copy with relative URIs made absolute against `baseURL`.
    public func resolvingURIs(against baseURL: URL) -> MultivariantPlaylist {
        mapURIs { uri, _ in resolve(uri, against: baseURL) }
    }
}

extension MediaPlaylist {
    /// Returns a copy with every URI transformed, e.g. to route requests
    /// through a local proxy or to append authentication tokens.
    public func mapURIs(_ transform: (String, URIRole) throws -> String) rethrows -> MediaPlaylist {
        var copy = self
        // Keys and maps are shared by many segments; transform each distinct value once.
        var keyCache: [EncryptionKey: EncryptionKey] = [:]
        var mapCache: [MediaInitializationSection: MediaInitializationSection] = [:]
        func mapKey(_ key: EncryptionKey) throws -> EncryptionKey {
            if let cached = keyCache[key] { return cached }
            var mapped = key
            if let uri = key.uri { mapped.uri = try transform(uri, .key) }
            keyCache[key] = mapped
            return mapped
        }
        func mapMap(_ section: MediaInitializationSection) throws -> MediaInitializationSection {
            if let cached = mapCache[section] { return cached }
            var mapped = section
            mapped.uri = try transform(section.uri, .initializationSection)
            mapped.keys = try section.keys.map(mapKey)
            mapCache[section] = mapped
            return mapped
        }
        func mapParts(_ parts: [PartialSegment]) throws -> [PartialSegment] {
            try parts.map { part in
                var part = part
                part.uri = try transform(part.uri, .partialSegment)
                return part
            }
        }
        func mapDateRanges(_ ranges: [DateRange]) throws -> [DateRange] {
            try ranges.map { range in
                var range = range
                if range.classIdentifier == "com.apple.hls.interstitial" {
                    for (attribute, role) in [("X-ASSET-URI", URIRole.interstitialAsset), ("X-ASSET-LIST", .interstitialAssetList)] {
                        if let uri = range.otherAttributes[attribute]?.rawValue {
                            range.otherAttributes[attribute] = .quoted(try transform(uri, role))
                        }
                    }
                }
                return range
            }
        }

        for index in copy.segments.indices {
            var segment = copy.segments[index]
            segment.uri = try transform(segment.uri, .segment)
            segment.keys = try segment.keys.map(mapKey)
            segment.map = try segment.map.map(mapMap)
            segment.parts = try mapParts(segment.parts)
            segment.dateRanges = try mapDateRanges(segment.dateRanges)
            copy.segments[index] = segment
        }
        copy.trailingParts = try mapParts(copy.trailingParts)
        copy.trailingKeys = try copy.trailingKeys.map(mapKey)
        copy.trailingMap = try copy.trailingMap.map(mapMap)
        copy.trailingDateRanges = try mapDateRanges(copy.trailingDateRanges)
        for index in copy.preloadHints.indices {
            copy.preloadHints[index].uri = try transform(copy.preloadHints[index].uri, .preloadHint)
        }
        for index in copy.renditionReports.indices {
            copy.renditionReports[index].uri = try transform(copy.renditionReports[index].uri, .renditionReport)
        }
        return copy
    }

    /// Returns a copy with relative URIs made absolute against `baseURL`.
    public func resolvingURIs(against baseURL: URL) -> MediaPlaylist {
        mapURIs { uri, role in role == .renditionReport ? uri : resolve(uri, against: baseURL) }
    }

    /// Absolute URLs of every segment, resolved against `baseURL`.
    public func segmentURLs(relativeTo baseURL: URL) -> [URL] {
        segments.compactMap { URL(string: resolve($0.uri, against: baseURL)) }
    }
}

extension Playlist {
    /// Returns a copy with every URI transformed.
    public func mapURIs(_ transform: (String, URIRole) throws -> String) rethrows -> Playlist {
        switch self {
        case .multivariant(let playlist): .multivariant(try playlist.mapURIs(transform))
        case .media(let playlist): .media(try playlist.mapURIs(transform))
        }
    }

    /// Returns a copy with relative URIs made absolute against `baseURL`.
    public func resolvingURIs(against baseURL: URL) -> Playlist {
        mapURIs { uri, role in role == .renditionReport ? uri : resolve(uri, against: baseURL) }
    }
}

private func resolve(_ uri: String, against baseURL: URL) -> String {
    // RFC 3986 §5.2.2: an empty reference inherits path/query, never fragment.
    // Some Foundation releases return nil for URL(string: "", relativeTo:).
    if uri.isEmpty {
        var components = URLComponents(url: baseURL.absoluteURL, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? uri
    }
    // Encode only characters outside RFC 3986, retaining existing escapes and
    // delimiters. Foundation's implicit encoding differs across OS versions.
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    guard let encoded = uri.addingPercentEncoding(withAllowedCharacters: allowed) else { return uri }
    guard let absolute = URL(string: encoded, relativeTo: baseURL)?.absoluteURL,
          var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else { return uri }
    let path = components.percentEncodedPath
    let normalized = removingDotSegments(path)
    guard normalized != path else { return absolute.absoluteString }
    components.percentEncodedPath = normalized
    return components.string ?? absolute.absoluteString
}

/// RFC 3986 §5.2.4. Older Foundation leaves absolute /./ and /../ paths intact.
/// Operate on encoded path bytes: escaped dots, slashes, queries and fragments
/// must not acquire path-navigation semantics.
func removingDotSegments(_ path: String) -> String {
    var input = path[...]
    var output = ""
    func removeLastSegment() {
        if let slash = output.lastIndex(of: "/") {
            output.removeSubrange(slash...)
        } else {
            output.removeAll(keepingCapacity: true)
        }
    }
    while !input.isEmpty {
        if input.hasPrefix("../") {
            input = input.dropFirst(3)
        } else if input.hasPrefix("./") {
            input = input.dropFirst(2)
        } else if input.hasPrefix("/./") {
            input = input.dropFirst(2)
        } else if input == "/." {
            input = "/"
        } else if input.hasPrefix("/../") {
            input = input.dropFirst(3)
            removeLastSegment()
        } else if input == "/.." {
            input = "/"
            removeLastSegment()
        } else if input == "." || input == ".." {
            input = ""
        } else {
            let start = input.hasPrefix("/") ? input.index(after: input.startIndex) : input.startIndex
            let end = input[start...].firstIndex(of: "/") ?? input.endIndex
            output.append(contentsOf: input[..<end])
            input = input[end...]
        }
    }
    return output
}
