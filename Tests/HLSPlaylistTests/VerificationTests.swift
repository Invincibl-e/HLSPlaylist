import Foundation
import Testing
import HLSPlaylist

/// Independent fixtures from hls.js/Shaka; exact revisions and licenses are in
/// Verification/corpus/provenance.json.
@Suite("External regression and preservation contracts")
struct VerificationTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func acceptedArchivedInputsRoundTrip() throws {
        let directory = root.appendingPathComponent("Verification/corpus/archive")
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
        var count = 0
        for case let url as URL in files where url.pathExtension == "m3u8" {
            count += 1
            // Archived packager output includes nonconforming inputs. Acceptance
            // is audited separately; this test checks preservation when accepted.
            guard let parsed = try? PlaylistParser().parse(Data(contentsOf: url)) else { continue }
            #expect(try Playlist(parsed.playlist.render()).render() == parsed.playlist.render(), "\(url.lastPathComponent)")
        }
        #expect(count == 73)
    }

    @Test func externalStaticFixtures() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Verification/corpus/external-inputs.json"))
        let rows = try JSONSerialization.jsonObject(with: data) as! [[String: String]]
        #expect(rows.count == 329)
        for row in rows {
            let text = row["text"]!
            let name = row["name"]!
            guard let playlist = try? Playlist(text) else { continue }
            let output = try playlist.render()
            let again = try Playlist(output).render()
            #expect(again == output, "\(name)")
        }
    }

    @Test func hlsJSOneVariantOracle() throws {
        // hls.js m3u8-parser.ts "parses manifest with one level".
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=836280,CODECS="mp4a.40.2,avc1.64001f",RESOLUTION=848x360,NAME="480"
        https://example.com/video.m3u8#cell=core
        """
        let master = try #require(try Playlist(text).multivariant)
        #expect(master.variants.count == 1)
        #expect(master.variants[0].bandwidth == 836280)
        #expect(master.variants[0].resolution == Resolution(width: 848, height: 360))
        #expect(master.variants[0].codecs == ["mp4a.40.2", "avc1.64001f"])
        #expect(master.variants[0].uri == "https://example.com/video.m3u8#cell=core")
    }

    @Test func shakaDurationAndByteRangeOracle() throws {
        // Shaka hls_parser_unit.js "parses manifest attributes".
        let text = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-TARGETDURATION:6
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-MAP:URI="init.mp4",BYTERANGE="616@0"
        #EXTINF:5,
        #EXT-X-BYTERANGE:121090@616
        main.mp4
        #EXT-X-ENDLIST
        """
        let media = try #require(try Playlist(text).media)
        #expect(media.segments.count == 1)
        #expect(media.segments[0].duration == 5)
        #expect(media.segments[0].byteRange?.length == 121090)
        #expect(media.segments[0].byteRange?.offset == 616)
        #expect(media.segments[0].map?.uri == "init.mp4")
    }

    @Test func imageURIIsRewritten() throws {
        let text = """
        #EXTM3U
        #EXT-X-IMAGE-STREAM-INF:BANDWIDTH=2000,URI="tiles.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=100000
        video.m3u8
        """
        let mapped = try Playlist(text).mapURIs { _, _ in "https://routed.test/" }.render()
        #expect(!mapped.contains("tiles.m3u8"))
    }

    @Test func unknownKeyPreloadIsIgnored() throws {
        // Shaka manifest_text_parser_unit.js "parses key preload hints as playlist tags".
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:5,
        uri
        #EXT-X-PRELOAD-HINT:TYPE=KEY,METHOD=AES-128,URI="next.key"
        """
        let output = try Playlist(text).render()
        #expect(!output.contains("METHOD=AES-128"))
        #expect(try Playlist(text).media?.preloadHints.isEmpty == true)
    }

    @Test func fractionalDurationIsLossless() throws {
        let text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXTINF:0.123456789,\ns.ts\n#EXT-X-ENDLIST\n"
        let media = try #require(try Playlist(text).media)
        let again = try #require(try Playlist(media.render()).media)
        #expect(again.segments[0].duration == media.segments[0].duration)
    }

    @Test func decimalExtremesRoundTrip() throws {
        for value in [Double.leastNonzeroMagnitude, 1e-100, 1e-7, 0.123456789,
                      29.97002997002997] {
            let media = MediaPlaylist(targetDuration: 30, segments: [Segment(uri: "s", duration: value)])
            let rendered = try media.render()
            #expect(!rendered.contains("e+"))
            #expect(!rendered.contains("e-"))
            #expect(try Playlist(rendered).media?.segments[0].duration == value)
        }
    }

    @Test func invalidTagsAlwaysThrow() throws {
        let base = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n"
        let tags = [
            "#EXTINF:NaN,\ns", "#EXTINF:inf,\ns", "#EXTINF:-1,\ns",
            "#EXT-X-TARGETDURATION:7", "#EXT-X-TARGETDURATION:6.5",
            "#EXT-X-KEY:METHOD=AES-128,URI=\"key",
            "#EXT-X-KEY:METHOD=AES-128,URI=\"a\",URI=\"b\"",
            "#EXT-X-MAP:URI=\"init\"junk", "#EXT-X-PART:DURATION=inf,URI=\"p\"",
            "#EXT-X-RENDITION-REPORT:LAST-MSN=-1",
            "#EXT-X-SKIP:SKIPPED-SEGMENTS=overflow"
        ]
        for tag in tags {
            let text = base + tag + "\n"
            #expect(throws: PlaylistError.self) { try Playlist(text) }
        }
        #expect(throws: PlaylistError.self) {
            try Playlist("#EXTM3U\n#EXTINF:6,\ns\n")
        }
    }

    @Test func extensionsSurviveRewriting() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-PRELOAD-HINT:TYPE=KEY,URI="k",METHOD=AES-128,X-NEW="keep"
        #EXT-X-RENDITION-REPORT:URI="r",LAST-MSN=1,X-NEW="keep"
        """
        let mapped = try Playlist(text).mapURIs { uri, _ in "proxy/" + uri }
        let again = try #require(try Playlist(mapped.render()).media)
        #expect(again.preloadHints.isEmpty)
        #expect(again.renditionReports[0].otherAttributes["X-NEW"]?.rawValue == "keep")
    }

    @Test func trailingInterstitialURIsAndImageOnlyMaster() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-PROGRAM-DATE-TIME:2026-10-23T00:00:00Z
        #EXTINF:6,
        s
        #EXT-X-DATERANGE:ID="ad",CLASS="com.apple.hls.interstitial",START-DATE="2026-10-23T00:00:00Z",X-ASSET-LIST="list"
        """
        var roles: [URIRole] = []
        let mapped = try Playlist(text).mapURIs { uri, role in
            roles.append(role)
            return "proxy/" + uri
        }
        #expect(roles == [.segment, .interstitialAssetList])
        #expect(try mapped.render().contains("X-ASSET-LIST=\"proxy/list\""))
        let image = try Playlist("#EXTM3U\n#EXT-X-IMAGE-STREAM-INF:BANDWIDTH=2000,URI=\"tiles\"\n")
        #expect(image.multivariant?.imageVariants.count == 1)
        #expect(try Playlist(image.render()).multivariant?.imageVariants[0].uri == "tiles")
    }

    @Test func variablesExpandInDefinitionOrder() throws {
        let text = """
        #EXTM3U
        #EXT-X-VERSION:8
        #EXT-X-DEFINE:NAME="foo",VALUE="ok"
        #EXT-X-DEFINE:NAME="bar",VALUE="{$foo}"
        #EXT-X-STREAM-INF:BANDWIDTH=1000
        {$bar}.m3u8
        """
        let result = try PlaylistParser().parse(text)
        #expect(result.variables["bar"] == "ok")
        #expect(result.playlist.multivariant?.variants[0].uri == "ok.m3u8")
        #expect(try Playlist(result.playlist.render()).render() == result.playlist.render())
        let forward = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:6,
        {$later}.ts
        #EXT-X-DEFINE:NAME="later",VALUE="changed"
        """
        #expect(throws: PlaylistError.undefinedVariable(name: "later", line: 4)) {
            try Playlist(forward)
        }
    }

    @Test func maximumTargetDoesNotOverflowLiveOffset() {
        #expect(MediaPlaylist(targetDuration: UInt64.max).recommendedLiveOffset == Double(UInt64.max) * 3)
    }

    @Test func frameRateUsesStandardPrecision() throws {
        for (value, expected) in [(29.97002997002997, "29.970"), (59.94005994005994, "59.940"),
                                  (23.976, "23.976"), (60.0, "60.000"), (29.9706, "29.971")] {
            let master = MultivariantPlaylist(variants: [
                Variant(uri: "video.m3u8", bandwidth: 100000, frameRate: value)
            ])
            let rendered = try master.render()
            #expect(rendered.contains("FRAME-RATE=\(expected)"))
            let again = try #require(try Playlist(rendered).multivariant)
            #expect(again.variants[0].frameRate == Double(expected))
            #expect(try again.render() == rendered)
        }
    }

    @Test func unicodeAttributesAndEscapedURIs() throws {
        let text = """
        #EXTM3U
        #EXT-X-IMAGE-STREAM-INF:BANDWIDTH=2000,URI="%E5%9B%BE%E7%89%87%20tiles.m3u8?token=a%2Fb%2B%3D",X-NAME="图片"
        """
        let master = try #require(try Playlist(text).multivariant)
        #expect(master.imageVariants[0].bandwidth == 2000)
        #expect(master.imageVariants[0].otherAttributes["X-NAME"]?.rawValue == "图片")
        let resolved = master.resolvingURIs(against: URL(string: "https://example.test/base/master.m3u8")!)
        #expect(resolved.imageVariants[0].uri == "https://example.test/base/%E5%9B%BE%E7%89%87%20tiles.m3u8?token=a%2Fb%2B%3D")
        #expect(resolved.resolvingURIs(against: URL(string: "https://other.test/")!).imageVariants == resolved.imageVariants)
    }
}
