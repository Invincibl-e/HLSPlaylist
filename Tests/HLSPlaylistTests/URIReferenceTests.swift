import Foundation
import Testing
@testable import HLSPlaylist

@Suite("RFC 3986 raw URI grammar")
struct URIReferenceTests {
    @Test(arguments: [
        "skd://fps.ezdrm.com/;key", "skd://host/%3Bkey", "data:text/plain;base64,AA==",
        "urn:example:animal:ferret:nose", "mailto:a@example.com", "http://host:65536/",
        "http://user:password@host:/a;b?x=+%2F%3b#fragment",
        "http://[::1]/", "http://[2001:db8::1]:443/", "http://[::ffff:192.0.2.1]/",
        "http://[1:2:3:4:5:6:192.0.2.1]/", "http://[vF.a:b!]/", "//host/a",
        "a;b.ts", "../%2e/%2F/file", "?x=a/b?c", "#a/b?c", "/", ""
    ])
    func acceptsRFCReferences(_ text: String) throws {
        let reference = try #require(URIReference(text))
        #expect(reference.valid())
        #expect(reference.string.utf8.elementsEqual(text.utf8))
        #expect(HLSStandard.uri(text) == !text.isEmpty)
    }

    @Test(arguments: [
        "1:bad", "a b", "http://host/%", "http://host/%GG", "http://host/%0",
        "http://host/path[bad]", "http://host/path?x=[bad]", "http://host/path#a#b",
        "http://a@b@host/", "http://host:abc/", "http://host:80:90/",
        "http://[::1", "http://[::1]bad/", "http://[1:2:3:4:5:6:7]/",
        "http://[1:2:3:4:5:6:7:8:9]/", "http://[1::2::3]/", "http://[:::]/",
        "http://[1:2:3:4:5:6:7:8::]/", "http://[::ffff:192.168.0.256]/",
        "http://[::ffff:192.168.00.1]/", "http://[192.168.0.1::]/", "http://[v.a]/",
        "http://[v1.]/", "http://[v1.a%20]/", "http://[fe80::1%25en0]/"
    ])
    func rejectsInvalidGrammar(_ text: String) {
        #expect(!HLSStandard.uri(text))
    }

    @Test func relativeContractAndQueryValues() throws {
        #expect(!HLSStandard.uri("skd://host/;key", relative: true))
        #expect(HLSStandard.uri("//host/;file", relative: true))
        #expect(HLSStandard.uri("dir/a:b", relative: true))
        let reference = try #require(URIReference("https://host/a;%3b?token=a%252Fb&plus=a+b&empty=&missing&dup&dup=second&na%6De=%E4%B8%AD%E6%96%87"))
        #expect(reference.queryValue(named: "token") == "a%2Fb")
        #expect(reference.queryValue(named: "plus") == "a+b")
        #expect(reference.queryValue(named: "empty") == "")
        #expect(reference.queryValue(named: "missing") == nil)
        #expect(reference.queryValue(named: "dup") == nil)
        #expect(reference.queryValue(named: "name") == "中文")
        #expect(URIReference("https://host/?token=%FF")?.queryValue(named: "token") == nil)
    }

    @Test func encodedResolutionNeverDecodesReservedCharacters() {
        #expect(resolveURI("../a;%3b?q=a%2Fb#f", against: "https://host/root/dir/file?old") ==
                "https://host/root/a;%3b?q=a%2Fb#f")
        #expect(resolveURI("", against: "https://host/root/;file?query#old") ==
                "https://host/root/;file?query")
        #expect(resolveURI("skd://host/;id?x=%3b", against: "https://host/base") ==
                "skd://host/;id?x=%3b")
        #expect(resolveURI("中文 空格", against: "https://host/dir/file") ==
                "https://host/dir/%E4%B8%AD%E6%96%87%20%E7%A9%BA%E6%A0%BC")
    }
}
