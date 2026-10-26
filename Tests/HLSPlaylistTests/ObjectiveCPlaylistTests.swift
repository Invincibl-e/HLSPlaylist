import Foundation
import Testing
@testable import HLSPlaylist

#if canImport(ObjectiveC)
@Suite("Objective-C playlist API")
struct ObjectiveCPlaylistTests {
    @Test func rewritingRetainsSharedRangesAndRawKeys() throws {
        let text = """
        #EXTM3U
        #EXT-X-VERSION:5
        #EXT-X-TARGETDURATION:1
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://host/;key",KEYFORMAT="com.apple.streamingkeydelivery"
        #EXT-X-BYTERANGE:10@0
        #EXTINF:1,title\ttext
        s.ts
        #EXT-X-BYTERANGE:10
        #EXTINF:1,
        s.ts
        """
        let document = try HLSPlaylist(text: text)
        let resources = document.resources
        #expect(resources.filter { $0.role == .segment }.count == 2)
        #expect(resources.filter { $0.role == .key }.map(\.uri) == ["skd://host/;key"])
        let output = try document.render(replacements: resources.map {
            $0.role == .key ? $0.uri : "/route/segment.ts"
        })
        let parsed = try Playlist(output).media!
        #expect(parsed.segments.map(\.uri) == ["/route/segment.ts", "/route/segment.ts"])
        #expect(output.contains("skd://host/;key"))
        #expect(output.contains("title\ttext"))
        #expect(output.contains("#EXT-X-BYTERANGE:10\n"))
        #expect(throws: NSError.self) { try document.render(replacements: []) }
        #expect(throws: NSError.self) { try document.render(replacements: resources.map(\.uri) + ["extra"]) }
        #expect(try Playlist(document.render(replacements: resources.map(\.uri))) == Playlist(text))
    }

    @Test func nativeURIComponentsRetainEncodingAndRejectNUL() throws {
        let uri = try #require(URIReference("https://user@host:99999/a%2Fb;p?sig=%41+%2f#"))
        #expect(uri.path == "/a%2Fb;p")
        #expect(uri.query == "sig=%41+%2f")
        #expect(uri.fragment == "")
        #expect(uri.userInfo == "user")
        #expect(uri.port == "99999")
        #expect(URIReference("a\0b") == nil)
        #expect(URIReference("\0") == nil)
        #expect(try HLSPlaylist.attributeNames("VALUE=\"a,URL=x\",X-URI=\"s\"") == ["VALUE", "X-URI"])
    }
}
#endif
