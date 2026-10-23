import Foundation
import Testing
@testable import HLSPlaylist

@Suite("RFC 8216 and bis-22 observable constraints")
struct StandardsTests {
    private func media(_ tags: String, version: UInt64 = 13) -> String {
        "#EXTM3U\n#EXT-X-VERSION:\(version)\n#EXT-X-TARGETDURATION:6\n" + tags + "\n"
    }

    @Test(arguments: ["", "ad-a", "ad-a\tad-b"])
    func deltaRemovedDateRanges(_ ids: String) throws {
        let text = media("#EXT-X-SKIP:SKIPPED-SEGMENTS=2,RECENTLY-REMOVED-DATERANGES=\"\(ids)\"", version: 10)
        let parsed = try #require(try Playlist(text).media)
        #expect(parsed.recentlyRemovedDateRanges == ids)
        #expect(try Playlist(parsed.render()).media == parsed)
        #expect(try Playlist(text.replacingOccurrences(of: "\n", with: "\r\n")).media == parsed)
    }

    @Test func sharedURIOracles() throws {
        struct Oracle: Decodable {
            var base: String
            var reference: String
            var expected: String
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let cases = try JSONDecoder().decode([Oracle].self, from: Data(contentsOf:
            root.appendingPathComponent("Verification/corpus/uri-oracles.json")))
        #expect(cases.count >= 54)
        for row in cases {
            let base = try #require(URL(string: row.base))
            let media = MediaPlaylist(targetDuration: 1, segments: [Segment(uri: row.reference, duration: 1)])
            #expect(media.resolvingURIs(against: base).segments[0].uri == row.expected)
            #expect(media.segmentURLs(relativeTo: base).map(\.absoluteString) == [row.expected])
            #expect(Playlist.media(media).resolvingURIs(against: base).media?.segments[0].uri == row.expected)
        }
    }

    @Test(arguments: [
        "#EXT-X-SKIP:SKIPPED-SEGMENTS=2,RECENTLY-REMOVED-DATERANGES=\"a\tb\",X-OTHER=\"c\td\"",
        "#EXT-X-SKIP:SKIPPED-SEGMENTS=2,\tRECENTLY-REMOVED-DATERANGES=\"a\tb\"",
        "#EXT-X-SKIP:SKIPPED-SEGMENTS=2,RECENTLY-REMOVED-DATERANGES=\"a\u{01}b\"",
        "#EXT-X-SESSION-DATA:DATA-ID=\"a\",VALUE=\"a\tb\""
    ])
    func deltaTabExceptionIsScoped(_ tags: String) {
        #expect(throws: PlaylistError.self) { try Playlist(media(tags)) }
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

    @Test func groupAndSteeringConstraintsAlsoApplyToConstructedModels() throws {
        var playlist = try #require(try Playlist("""
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English",LANGUAGE="en",CHANNELS="2",URI="a"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="b",NAME="English",LANGUAGE="en",CHANNELS="6",URI="b"
        """).multivariant)
        playlist.renditions[1].language = "fr"
        #expect(throws: PlaylistError.self) { try playlist.render() }
        playlist.renditions[1].language = "en"
        playlist.renditions[0].channels = "2//BINAURAL"
        #expect(throws: PlaylistError.self) { try playlist.render() }
        playlist.renditions[0].channels = "2/-/BINAURAL"
        _ = try playlist.render()
        playlist.contentSteering = ["SERVER-URI": .quoted("s"), "PATHWAY-ID": .quoted("missing")]
        #expect(throws: PlaylistError.self) { try playlist.render() }
    }

    @Test func sessionDataFormatForwardCompatibility() throws {
        let unknown = try Playlist("#EXTM3U\n#EXT-X-SESSION-DATA:DATA-ID=\"x\",URI=\"data\",FORMAT=NEW\n")
        #expect(unknown.multivariant?.sessionData.isEmpty == true)
        let ignored = try Playlist("#EXTM3U\n#EXT-X-SESSION-DATA:DATA-ID=\"x\",VALUE=\"v\",FORMAT=\"NEW\"\n")
        #expect(ignored.multivariant?.sessionData.count == 1)
    }

    @Test func interstitialRejectsInvalidConstructedAsset() throws {
        var playlist = try #require(try Playlist(media("""
        #EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00Z
        #EXT-X-DATERANGE:ID="a",CLASS="com.apple.hls.interstitial",START-DATE="2026-01-01T00:00:00Z",X-ASSET-LIST="ads.json"
        """)).media)
        playlist.trailingDateRanges[0].otherAttributes["X-ASSET-URI"] = .quoted("https://example.test/ad")
        #expect(throws: PlaylistError.self) { try playlist.render() }
    }

    @Test func effectiveKeyContextsCannotSerializeLossyOverrides() throws {
        let key = EncryptionKey(method: .aes128, uri: "k")
        let duplicate = MediaPlaylist(targetDuration: 1, segments: [Segment(uri: "s", duration: 1, keys: [key, key])])
        #expect(throws: PlaylistError.self) { try duplicate.render() }
        let none = MediaPlaylist(targetDuration: 1, segments: [Segment(uri: "s", duration: 1, keys: [EncryptionKey(method: .none)])])
        #expect(throws: PlaylistError.self) { try none.render() }
        // Repeated KEY tags in text legally replace a format's previous key.
        let parsed = try #require(try Playlist(media("""
        #EXT-X-KEY:METHOD=AES-128,URI="old"
        #EXT-X-KEY:METHOD=AES-128,URI="new"
        #EXTINF:1,
        s
        """)).media)
        #expect(parsed.segments[0].keys.map(\.uri) == ["new"])
        #expect(try Playlist(parsed.render()).media == parsed)
    }

    @Test func allVariantKindsPreserveExtensionTagsWhenRendered() throws {
        var variant = Variant(uri: "v", bandwidth: 1)
        variant.unknownTags = ["#EXT-X-FUTURE:payload"]
        var playlist = MultivariantPlaylist(variants: [variant])
        playlist.iFrameVariants = [variant]
        playlist.imageVariants = [variant]
        let text = try playlist.render()
        #expect(text.components(separatedBy: "#EXT-X-FUTURE:payload").count == 4)
    }

    @Test func consecutiveDiscontinuitiesPreserveSequenceMultiplicity() throws {
        let text = media("""
        #EXT-X-DISCONTINUITY-SEQUENCE:5
        #EXT-X-DISCONTINUITY
        #EXT-X-DISCONTINUITY
        #EXTINF:1,
        s
        #EXT-X-DISCONTINUITY
        #EXT-X-DISCONTINUITY
        """)
        var parsed = try #require(try Playlist(text).media)
        #expect(parsed.segments[0].discontinuityCount == 2)
        #expect(parsed.trailingDiscontinuityCount == 2)
        #expect(try Playlist(parsed.render()).media == parsed)
        parsed.segments[0].discontinuity = true
        #expect(parsed.segments[0].discontinuityCount == 2)
        parsed.segments[0].discontinuity = false
        #expect(parsed.segments[0].discontinuityCount == 0)
        #expect(throws: PlaylistError.self) {
            try Playlist(text.replacingOccurrences(of: "SEQUENCE:5", with: "SEQUENCE:18446744073709551612"))
        }
        var huge = MediaPlaylist(targetDuration: 1)
        huge.trailingDiscontinuityCount = .max
        #expect(throws: PlaylistError.self) { try huge.render() }
    }

    @Test(arguments: [
        ("g", "http://a/b/c/g"), ("./g", "http://a/b/c/g"),
        ("g/", "http://a/b/c/g/"), ("/g", "http://a/g"),
        ("//g", "http://g"), ("?y", "http://a/b/c/d;p?y"),
        ("g?y", "http://a/b/c/g?y"), ("#s", "http://a/b/c/d;p?q#s"),
        ("g#s", "http://a/b/c/g#s"), ("g?y#s", "http://a/b/c/g?y#s"),
        (";x", "http://a/b/c/;x"), ("g;x", "http://a/b/c/g;x"),
        (".", "http://a/b/c/"), ("..", "http://a/b/"),
        ("../g", "http://a/b/g"), ("../../g", "http://a/g"),
        ("../../../g", "http://a/g"), ("/./g", "http://a/g"),
        ("/../g", "http://a/g"), ("g/./h", "http://a/b/c/g/h"),
        ("g/../h", "http://a/b/c/h"), ("g?y/../x", "http://a/b/c/g?y/../x"),
        ("g#s/../x", "http://a/b/c/g#s/../x"),
        ("/a//b/../g", "http://a/a//g"), ("/a/.", "http://a/a/"),
        ("/%2E/g", "http://a/%2E/g"), ("/a/%2e%2E/g", "http://a/a/%2e%2E/g"),
        ("/a/./g?sig=a%2Fb+z#f/../g", "http://a/a/g?sig=a%2Fb+z#f/../g"),
        ("/b;p/./g", "http://a/b;p/g"),
        ("/%2e/%2E%2e/./g", "http://a/%2e/%2E%2e/g"),
        ("/a/%2F/../b;p", "http://a/a/b;p")
    ])
    func rfc3986ResolutionOracle(_ reference: String, _ expected: String) throws {
        // Fragment-only URI references belong in attributes: a playlist line
        // starting with '#' is a comment/tag under HLS §4.1.
        let playlist = try Playlist(media("#EXT-X-MAP:URI=\"\(reference)\"\n#EXTINF:1,\ns"))
        let base = URL(string: "http://a/b/c/d;p?q")!
        let resolved = playlist.resolvingURIs(against: base)
        #expect(resolved.media?.segments[0].map?.uri == expected)
        let segments = MediaPlaylist(targetDuration: 1, segments: [Segment(uri: reference, duration: 1)])
        #expect(segments.segmentURLs(relativeTo: base).first?.absoluteString == expected)
    }

    @Test(arguments: [
        ("/./g", "/g"), ("/../g", "/g"), ("/a/b/../../../../g", "/g"),
        ("mid/content=5/../6", "mid/6"), ("../g", "g"), ("./g", "g"),
        ("/a//b/../g", "/a//g"), ("/a/.", "/a/"), ("/a/..", "/"),
        ("/.%2e/g", "/.%2e/g"), ("/a/%2e%2E/g", "/a/%2e%2E/g"),
        ("/a/%2F/../g", "/a/g"), ("", ""), (".", ""), ("..", ""),
        ("a/../../g", "/g"), ("a//./b/../c", "a//c")
    ])
    func rfc3986EncodedPathOracle(_ path: String, _ expected: String) {
        // Exercise legacy normalization directly even when the host Foundation
        // has already removed dot segments before the public resolver sees them.
        #expect(removingDotSegments(path) == expected)
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
