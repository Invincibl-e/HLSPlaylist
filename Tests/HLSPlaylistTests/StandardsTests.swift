import Foundation
import Testing
@testable import HLSPlaylist

@Suite("RFC 8216 and bis-22 observable constraints")
struct StandardsTests {
    private func media(_ tags: String, version: UInt64 = 13) -> String {
        "#EXTM3U\n#EXT-X-VERSION:\(version)\n#EXT-X-TARGETDURATION:6\n" + tags + "\n"
    }

    @Test(arguments: [
        "+1", "-1", "1e3", " 1", "1 ", "１２", "18446744073709551616",
        "000000000000000000000", ""
    ])
    func rejectsIllegalInteger(_ number: String) {
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-MEDIA-SEQUENCE:" + number)) }
    }

    @Test func fullUnsignedIntegerRange() throws {
        let maximum = UInt64.max
        let master = try #require(try Playlist("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=\(maximum),RESOLUTION=\(maximum)x1\nv\n").multivariant)
        #expect(master.variants[0].bandwidth == maximum)
        #expect(master.variants[0].resolution?.width == maximum)
        #expect(try Playlist(master.render()).multivariant == master)
        let playlist = try #require(try Playlist(media("#EXT-X-MEDIA-SEQUENCE:\(maximum)\n#EXTINF:6,\ns")).media)
        #expect(playlist.mediaSequence(ofSegmentAt: 0) == maximum)
        #expect(playlist.mediaSequence(ofSegmentAt: 1) == nil)
        #expect(playlist.segments.count == 1)
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-MEDIA-SEQUENCE:\(maximum)\n#EXTINF:6,\ns\n#EXTINF:6,\nt")) }
        #expect(EncryptionKey(method: .aes128).initializationVector(forMediaSequence: maximum).suffix(8) == Array(repeating: 255, count: 8))
    }

    @Test(arguments: ["+1", "-1", "1e0", "NaN", "inf", "1..0", "１.０", " 1"])
    func rejectsIllegalDecimal(_ number: String) {
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXTINF:\(number),\ns")) }
    }

    @Test func decimalGrammarAndSignedStart() throws {
        for value in [".5", "0.5", "5.", "5"] {
            #expect(try Playlist(media("#EXTINF:\(value),\ns")).media?.segments[0].duration == Double(value))
        }
        #expect(try Playlist(media("#EXT-X-START:TIME-OFFSET=-1.5,PRECISE=YES")).media?.start?.timeOffset == -1.5)
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-START:TIME-OFFSET=\"1\"")) }
    }

    @Test(arguments: [
        "#EXT-X-TARGETDURATION:6",
        "#EXT-X-ENDLIST:YES",
        "#EXT-X-MEDIA-SEQUENCE:1\n#EXT-X-MEDIA-SEQUENCE:2",
        "#EXTINF:1,\n#EXTINF:2,\ns",
        "#EXT-X-MAP:URI=\"init\",BYTERANGE=\"10\"",
        "#EXT-X-KEY:URI=\"key\"",
        "#EXT-X-KEY:METHOD=NONE,URI=\"key\"",
        "#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI=\"key\",IV=0x1",
        "#EXT-X-KEY:METHOD=AES-256-GCM,URI=\"key\",IV=0x1",
        "#EXT-X-KEY:METHOD=AES-128,URI=\"key\",IV=0xabcdef",
        "#EXT-X-KEY:METHOD=AES-128,URI=\"key\",IV=0x100000000000000000000000000000000",
        "#EXT-X-KEY:METHOD=AES-128,URI=\"key\",KEYFORMATVERSIONS=\"1/0\"",
        "#EXT-X-BYTERANGE:10\n#EXTINF:1,\ns",
        "#EXTINF:1,\ns\n#EXT-X-MEDIA-SEQUENCE:1",
        "#EXT-X-DISCONTINUITY\n#EXT-X-DISCONTINUITY-SEQUENCE:1",
        "#EXT-X-SERVER-CONTROL:HOLD-BACK=17.999",
        "#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=35.999",
        "#EXT-X-SERVER-CONTROL:CAN-SKIP-DATERANGES=YES",
        "#EXT-X-PART-INF:PART-TARGET=1",
        "#EXT-X-PART:DURATION=1,URI=\"p\"",
        "#EXT-X-PRELOAD-HINT:TYPE=PART,URI=\"p\"\n#EXT-X-ENDLIST",
        "#EXT-X-RENDITION-REPORT:URI=\"https://x/r\"",
        "#EXT-X-DEFINE:NAME=\"x\"",
        "#EXT-X-DEFINE:NAME=\"x\",VALUE=\"v\",IMPORT=\"x\"",
        "#EXT-X-DEFINE:NAME=\"x\",VALUE=\"v\"\n#EXT-X-DEFINE:NAME=\"x\",VALUE=\"w\"",
        "#EXT-X-DATERANGE:ID=\"x\",START-DATE=\"2026-01-01T00:00:00Z\"",
        "#EXT-X-PROGRAM-DATE-TIME:2026-02-30T00:00:00Z",
        "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00+25:00"
    ])
    func rejectsKnownTagViolations(_ tags: String) {
        #expect(throws: PlaylistError.self) { try Playlist(media(tags)) }
    }

    @Test(arguments: [
        "#EXT-X-STREAM-INF:BANDWIDTH=\"1\"\nv",
        "#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1X1\nv",
        "#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO=\"missing\"\nv",
        "#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=1,URI=\"v\",FRAME-RATE=30",
        "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"g\"",
        "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"g\",NAME=\"n\"",
        "#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID=\"g\",NAME=\"n\",URI=\"v\",INSTREAM-ID=\"CC1\"",
        "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"g\",NAME=\"n\",FORCED=NO",
        "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"g\",NAME=\"n\",DEFAULT=YES,AUTOSELECT=NO",
        "#EXT-X-SESSION-DATA:DATA-ID=\"id\",VALUE=\"v\",URI=\"v\"",
        "#EXT-X-SESSION-KEY:METHOD=NONE",
        "#EXT-X-DEFINE:IMPORT=\"x\""
    ])
    func rejectsMasterViolations(_ tags: String) {
        #expect(throws: PlaylistError.self) { try Playlist("#EXTM3U\n#EXT-X-VERSION:13\n" + tags + "\n") }
    }

    @Test func forwardCompatibilityIgnoresTagsAndStreamURI() throws {
        let master = try #require(try Playlist("""
        #EXTM3U
        #EXT-X-VERSION:12
        #EXT-X-STREAM-INF:BANDWIDTH=1,REQ-NEW="x"
        ignored
        #EXT-X-STREAM-INF:BANDWIDTH=2,VIDEO-RANGE=NEW
        ignored-too
        #EXT-X-STREAM-INF:BANDWIDTH=3,REQ-VIDEO-LAYOUT="CH-NEW"
        ignored-layout
        #EXT-X-STREAM-INF:BANDWIDTH=4,X-NEW="keep"
        kept
        """).multivariant)
        #expect(master.variants.map(\.uri) == ["kept"])
        #expect(master.variants[0].otherAttributes["X-NEW"] == .quoted("keep"))
        let playlist = try #require(try Playlist(media("#EXT-X-PRELOAD-HINT:TYPE=KEY,URI=\"k\"\n#EXT-X-KEY:METHOD=NEW,URI=\"k\"\n#EXTINF:1,\ns")).media)
        #expect(playlist.preloadHints.isEmpty)
        #expect(playlist.segments[0].keys.isEmpty)
    }

    @Test func variableScopeAndHexSubstitution() throws {
        let text = media("""
        #EXT-X-DEFINE:NAME="iv",VALUE="1A"
        #EXT-X-KEY:METHOD=AES-128,URI="key",IV=0x{$iv}
        #EXTINF:1,{$undefined}
        s
        """)
        let playlist = try #require(try Playlist(text).media)
        #expect(playlist.segments[0].title == "{$undefined}")
        #expect(playlist.segments[0].keys[0].iv == Array(repeating: 0, count: 15) + [0x1A])
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-DEFINE:NAME=\"n\",VALUE=\"1\"\n#EXTINF:{$n},\ns")) }
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-DEFINE:NAME=\"n\",VALUE=\"1\"\n#EXT-X-STREAM-INF:BANDWIDTH={$n}\nv")) }
    }

    @Test func validImplicitRangesAndDateRangeUpdates() throws {
        let text = media("""
        #EXT-X-PROGRAM-DATE-TIME:2024-02-29T00:00:00
        #EXT-X-DATERANGE:ID="x",START-DATE="2024-02-29T00:00:00Z"
        #EXT-X-BYTERANGE:10@0
        #EXTINF:1,
        s
        #EXT-X-DATERANGE:ID="x",DURATION=2,END-DATE="2024-02-29T00:00:02Z"
        #EXT-X-BYTERANGE:20
        #EXTINF:1,
        s
        """)
        let playlist = try Playlist(text)
        #expect(try Playlist(playlist.render()) == playlist)
        #expect(throws: PlaylistError.self) { try Playlist(text.replacingOccurrences(of: "DURATION=2", with: "DURATION=3")) }
        #expect(throws: PlaylistError.self) { try Playlist(text.replacingOccurrences(of: "#EXT-X-BYTERANGE:20", with: "#EXT-X-BYTERANGE:20@")) }
    }

    @Test func lowLatencyBoundsAndTrailingContext() throws {
        let text = media("""
        #EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=36,HOLD-BACK=18,PART-HOLD-BACK=2
        #EXT-X-PART-INF:PART-TARGET=1
        #EXTINF:6,
        old
        #EXT-X-DISCONTINUITY
        #EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x1
        #EXT-X-MAP:URI="init"
        #EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:06Z
        #EXT-X-PART:DURATION=0.1,URI="p0",INDEPENDENT=YES
        #EXT-X-PART:DURATION=0.85,URI="p1"
        #EXT-X-PRELOAD-HINT:TYPE=PART,URI="p2",BYTERANGE-LENGTH=10
        #EXT-X-RENDITION-REPORT:URI="../r"
        """)
        let playlist = try Playlist(text)
        #expect(try Playlist(playlist.render()) == playlist)
        let mapped = playlist.mapURIs { uri, role in role == .renditionReport ? "/routed/report" : "https://cdn.test/" + uri }
        #expect(try Playlist(mapped.render()) == mapped)
        #expect(mapped.media?.trailingKeys[0].uri == "https://cdn.test/k")
        #expect(mapped.media?.trailingMap?.uri == "https://cdn.test/init")
        #expect(throws: PlaylistError.self) { try Playlist(text.replacingOccurrences(of: "DURATION=0.85", with: "DURATION=0.84")) }
        #expect(throws: PlaylistError.self) { try Playlist(text + "\n#EXT-X-KEY:METHOD=NONE\n") }
        #expect(throws: PlaylistError.self) { try Playlist(text.replacingOccurrences(of: "PART-HOLD-BACK=2", with: "PART-HOLD-BACK=1.999")) }
        #expect(throws: PlaylistError.self) { try Playlist(text.replacingOccurrences(of: "DURATION=0.85", with: "DURATION=1.001")) }
    }

    @Test func mapEncryptionUsesDeclarationContext() throws {
        let unencryptedMap = media("#EXT-X-MAP:URI=\"init\"\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXTINF:1,\ns")
        let playlist = try Playlist(unencryptedMap)
        #expect(try Playlist(playlist.render()) == playlist)
        let encryptedMap = media("#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXT-X-MAP:URI=\"init\"\n#EXTINF:1,\ns")
        #expect(throws: PlaylistError.self) { try Playlist(encryptedMap) }
    }

    @Test func requiredVersionsAndDurationSemantics() throws {
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXTINF:1.0,\ns", version: 1)) }
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-MAP:URI=\"init\"\n#EXTINF:1,\ns", version: 5)) }
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXT-X-SKIP:SKIPPED-SEGMENTS=1", version: 8)) }
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXTINF:6.1,\ns", version: 5)) }
        #expect(try Playlist(media("#EXTINF:6.1,\ns", version: 6)).media?.segments[0].duration == 6.1)
        #expect(throws: PlaylistError.self) { try Playlist(media("#EXTINF:6.5,\ns", version: 6)) }
        let constructed = MediaPlaylist(targetDuration: 6, segments: [Segment(uri: "s", duration: 0.123456789)])
        #expect(try constructed.render().contains("#EXT-X-VERSION:3"))
    }

    @Test func invalidConstructedModelsThrow() {
        #expect(throws: PlaylistError.self) { try MediaPlaylist(targetDuration: 0).render() }
        #expect(throws: PlaylistError.self) { try MediaPlaylist(targetDuration: 1, segments: [Segment(uri: "s", duration: .nan)]).render() }
        #expect(throws: PlaylistError.self) { try MultivariantPlaylist(variants: [Variant(uri: "bad uri", bandwidth: 1)]).render() }
        var playlist = MediaPlaylist(targetDuration: 1)
        playlist.renditionReports = [RenditionReport(uri: "https://x/r")]
        #expect(throws: PlaylistError.self) { try playlist.render() }
    }

    @Test func dataInputPreservesBOMRejection() {
        let data = Data(("\u{FEFF}" + media("")).utf8)
        #expect(throws: PlaylistError.self) { try Playlist(data: data) }
        #expect(throws: PlaylistError.self) { try PlaylistParser().parse(data) }
        #expect(throws: PlaylistError.invalidEncoding) { try Playlist(data: Data([0xFF])) }
    }

    @Test func opaqueURIsFollowRFC3986() throws {
        for uri in ["data:text/plain;base64,YQo=", "data:text/plain;charset=UTF-16;base64,UAIA", "skd:asset?id=1#key"] {
            #expect(HLSStandard.uri(uri))
            _ = try Playlist(media("#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"\(uri)\"\n#EXTINF:1,\ns"))
        }
        for uri in ["data:text/[plain]", "1data:value", "data:value#one#two", "data:value%Q0"] {
            #expect(!HLSStandard.uri(uri))
        }
    }

    @Test func datesPreserveStoredSubmillisecondPrecision() throws {
        for fraction in ["123456789", "0000005", "9999999"] {
            let playlist = try Playlist(media("#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00.\(fraction)Z\n#EXTINF:1,\ns"))
            #expect(try Playlist(playlist.render()).media?.segments[0].programDateTime == playlist.media?.segments[0].programDateTime)
        }
    }

    @Test(arguments: [
        "\n#EXTM3U\n", "#EXTM3U \n", "#EXTM3U\n#EXTM3U\n", "#EXTM3U\r#EXT-X-TARGETDURATION:1",
        "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nbad uri\n",
        "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\ns%Q0\n",
        "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\ns\t\n",
        "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,e\u{301}\ns\n"
    ])
    func rejectsInvalidText(_ text: String) {
        #expect(throws: PlaylistError.self) { try Playlist(text) }
    }
}
