import Foundation

#if canImport(ObjectiveC)
/// A URI occurrence and its semantic role, in mapURIs traversal order.
@objc(HLSURI)
public final class HLSURI: NSObject {
    @objc public let uri: String
    @objc public let role: URIRole

    init(uri: String, role: URIRole) {
        self.uri = uri
        self.role = role
        super.init()
    }
}

/// Objective-C access to the same parser and serializer as the Swift Playlist API.
/// Callers own transport policies and supply replacements in resources order.
@objc(HLSPlaylist)
public final class HLSPlaylist: NSObject {
    private let playlist: Playlist

    @objc
    public init(text: String) throws {
        playlist = try Playlist(text)
        super.init()
    }

    @objc public var resources: [HLSURI] {
        var resources: [HLSURI] = []
        _ = playlist.mapURIs { uri, role in
            resources.append(HLSURI(uri: uri, role: role))
            return uri
        }
        return resources
    }

    @objc
    public func render(replacements: [String]) throws -> String {
        var index = 0
        let mapped = try playlist.mapURIs { _, _ in
            guard index < replacements.count else { throw replacementCountError }
            defer { index += 1 }
            return replacements[index]
        }
        guard index == replacements.count else { throw replacementCountError }
        return try mapped.render()
    }

    /// Parse names without interpreting extension attributes as transport policy.
    @objc
    public static func attributeNames(_ value: String) throws -> [String] {
        try AttributeList.parse(Substring(value)).entries.map(\.key)
    }

    private var replacementCountError: NSError {
        NSError(domain: "HLSPlaylist", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Replacement count must match URI occurrences"
        ])
    }
}
#endif
