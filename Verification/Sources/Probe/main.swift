import Foundation
import HLSPlaylist

private struct ProbeInput: Decodable {
    var name: String?
    var text: String
    var textUTF8: Data?
    var url: String?
    var imports: [String: String]?
    var resolve: Bool?
    var rewrite: Bool?
    var proxy: String?
    var liveOffset: Bool?
}

// One JSON object per line; a hostile input can be isolated in its own process.
while let line = readLine() {
    var row: [String: Any] = [:]
    do {
        // Base64 UTF-8 avoids Foundation JSON string BOM normalization across
        // OS versions and exercises the library's exact-byte Data entry point.
        let input = try JSONDecoder().decode(ProbeInput.self, from: Data(line.utf8))
        row["name"] = input.name
        let url = URL(string: input.url ?? "https://fixture.test/path/master.m3u8")!
        let options = ParseOptions(importedVariables: input.imports ?? [:], playlistURL: url)
        row["stage"] = "parse"
        let parsed = try PlaylistParser(options: options).parse(input.textUTF8 ?? Data(input.text.utf8))
        row["parseAccepted"] = true
        var playlist = parsed.playlist
        row["stage"] = "render"
        let rendered = try playlist.render()
        row["rendered"] = rendered
        row["stage"] = "round-trip"
        row["idempotent"] = try Playlist(rendered, options: options).render() == rendered
        if input.resolve == true || input.rewrite == true {
            playlist = playlist.resolvingURIs(against: url)
        }
        var roles: [String] = []
        if input.rewrite == true {
            playlist = playlist.mapURIs { uri, role in
                roles.append(String(describing: role))
                // Preserve opaque key schemes for FairPlay/data keys.
                guard let resolved = URL(string: uri, relativeTo: url)?.absoluteURL,
                      ["http", "https"].contains(resolved.scheme) else { return uri }
                var proxy = input.proxy ?? "https://routed.test/resource"
                if role == .renditionReport, let components = URLComponents(string: proxy) {
                    // Report URIs must stay relative even in a proxy playlist.
                    proxy = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
                }
                return proxy + "?url=" +
                    resolved.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            }
        }
        row["stage"] = "rewrite-render"
        row["text"] = try playlist.render()
        row["roles"] = roles
        if let media = parsed.playlist.media {
            row["segments"] = media.segments.count
            row["durations"] = media.segments.map { $0.duration.isFinite ? String($0.duration) : "nonfinite" }
            row["discontinuityCounts"] = media.segments.map { String($0.discontinuityCount) }
            row["trailingDiscontinuityCount"] = String(media.trailingDiscontinuityCount)
            if input.liveOffset == true {
                row["liveOffset"] = String(media.recommendedLiveOffset)
            }
        }
        row["status"] = "accepted"
        row["stage"] = "complete"
    } catch {
        row["status"] = "rejected"
        row["error"] = String(describing: error)
    }
    let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
