import Foundation
import Testing
import HLSPlaylist

/// Parses Apple's public example streams. Run with `HLS_LIVE_TESTS=1 swift test`.
@Suite("Live streams", .enabled(if: ProcessInfo.processInfo.environment["HLS_LIVE_TESTS"] == "1"))
struct LiveStreamTests {
    static let masters = [
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8",
    ]

    @Test(arguments: masters)
    func parsesAndRoundTripsAppleExamples(_ address: String) async throws {
        let url = try #require(URL(string: address))
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let result = try PlaylistParser(options: ParseOptions(playlistURL: url)).parse(data)
        let master = try #require(result.playlist.multivariant)
        #expect(!master.variants.isEmpty)
        #expect(try Playlist(master.render()).multivariant == master)

        // Fetch every distinct media playlist referenced by the master.
        let resolved = master.resolvingURIs(against: url)
        let uris = Set(resolved.variants.map(\.uri) + resolved.renditions.compactMap(\.uri) + resolved.iFrameVariants.map(\.uri))
        for uri in uris.sorted() {
            let mediaURL = try #require(URL(string: uri))
            let (mediaData, response) = try await URLSession.shared.data(from: mediaURL)
            #expect((response as? HTTPURLResponse)?.statusCode == 200, "\(uri)")
            // Apple's current sample bodies contain TAB in EXTINF titles.
            // RFC 8216 §4 and bis §4.1 prohibit it. Keep raw bytes; do not trim.
            let text = try #require(String(data: mediaData, encoding: .utf8))
            if text.unicodeScalars.contains(where: {
                ($0.value < 32 && $0.value != 10 && $0.value != 13) || (127...159).contains($0.value)
            }) {
                #expect(throws: PlaylistError.invalidTag("Control character in playlist", line: 0)) {
                    try PlaylistParser(options: ParseOptions(playlistURL: mediaURL)).parse(mediaData)
                }
                continue
            }
            let parsed = try PlaylistParser(options: ParseOptions(playlistURL: mediaURL)).parse(mediaData)
            let media = try #require(parsed.playlist.media, "\(uri)")
            #expect(!media.segments.isEmpty, "\(uri)")
            #expect(try Playlist(media.render()).media == media, "\(uri)")
        }
    }
}
