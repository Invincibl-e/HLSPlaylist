import Foundation
import Testing
@testable import HLSPlaylist

@Suite("Transport URI boundaries")
struct TransportURITests {
    @Test func largeAttributeListRejectsLateDuplicateWithoutQuadraticLookup() throws {
        let text = (0..<20_000).map { "X-\($0)=\"v,\($0)\"" }.joined(separator: ",")
        let parsed = try AttributeList.parse(Substring(text))
        #expect(parsed.entries.count == 20_000)
        #expect(parsed["X-19999"] == .quoted("v,19999"))
        #expect(throws: PlaylistError.self) {
            try AttributeList.parse(Substring(text + ",X-19999=\"again\""))
        }
    }

    @Test func publicResolverRetainsRequestIdentity() {
        let base = URL(string: "https://a.test/b/list.m3u8?old#discard")!
        for (reference, expected) in [
            ("%2e%2e/key?sig=%2f%41+z", "https://a.test/b/%2e%2e/key?sig=%2f%41+z"),
            ("../other.m3u8?", "https://a.test/other.m3u8?"),
            ("//b.test:8443/a/../b;p", "https://b.test:8443/b;p"),
            ("skd://asset/key?token=%2f", "skd://asset/key?token=%2f"),
            ("data:text/plain;base64,QQ==", "data:text/plain;base64,QQ=="),
            ("#f", "https://a.test/b/list.m3u8?old#f"),
            ("", "https://a.test/b/list.m3u8?old"),
        ] {
            #expect(resolveURI(reference, against: base) == expected)
        }
    }

    @Test func reportFetchResolutionDoesNotChangePlaylistGrammar() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:1
        #EXTINF:1,
        s.ts
        #EXT-X-RENDITION-REPORT:URI="../other.m3u8?sig=%2f",LAST-MSN=0
        """
        let base = URL(string: "https://a.test/b/list.m3u8")!
        let parsed = try Playlist(text)
        let relative = parsed.media!.renditionReports[0].uri
        #expect(resolveURI(relative, against: base) == "https://a.test/other.m3u8?sig=%2f")
        #expect(parsed.resolvingURIs(against: base).media!.renditionReports[0].uri == relative)
        let local = parsed.mapURIs { _, role in
            role == .renditionReport ? "/route/report.m3u8" : "/route/segment.ts"
        }
        #expect(try Playlist(local.render()).media!.renditionReports[0].uri == "/route/report.m3u8")
    }
}
