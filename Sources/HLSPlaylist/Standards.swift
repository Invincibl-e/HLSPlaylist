import Foundation

/// Checks only constraints observable in a playlist. Media encoding, server
/// refresh behavior and cross-rendition timing require separate validation.
enum HLSStandard {
    static let attributeTags: Set<String> = [
        "#EXT-X-START", "#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-IMAGE-STREAM-INF",
        "#EXT-X-MEDIA", "#EXT-X-SESSION-DATA", "#EXT-X-SESSION-KEY", "#EXT-X-CONTENT-STEERING",
        "#EXT-X-KEY", "#EXT-X-MAP", "#EXT-X-DATERANGE", "#EXT-X-PART", "#EXT-X-PART-INF",
        "#EXT-X-SERVER-CONTROL", "#EXT-X-SKIP", "#EXT-X-PRELOAD-HINT", "#EXT-X-RENDITION-REPORT", "#EXT-X-DEFINE"
    ]
    static let flags: Set<String> = ["#EXT-X-INDEPENDENT-SEGMENTS", "#EXT-X-I-FRAMES-ONLY", "#EXT-X-ENDLIST", "#EXT-X-DISCONTINUITY", "#EXT-X-GAP"]
    static let singletons = flags.subtracting(["#EXT-X-DISCONTINUITY", "#EXT-X-GAP"]).union([
        "#EXT-X-VERSION", "#EXT-X-START", "#EXT-X-TARGETDURATION", "#EXT-X-MEDIA-SEQUENCE",
        "#EXT-X-DISCONTINUITY-SEQUENCE", "#EXT-X-PLAYLIST-TYPE", "#EXT-X-PART-INF", "#EXT-X-SERVER-CONTROL", "#EXT-X-SKIP",
        "#EXT-X-CONTENT-STEERING"
    ])
    static let parameterTags = singletons.subtracting(flags).union([
        "#EXTINF", "#EXT-X-BYTERANGE", "#EXT-X-PROGRAM-DATE-TIME", "#EXT-X-BITRATE"
    ])
    static let recognizedTags = attributeTags.union(flags).union(parameterTags).union(["#EXTM3U"])

    static func unknown(_ tags: [String]) throws {
        for tag in tags {
            let name = String(tag.prefix { $0 != ":" })
            try require(tag.hasPrefix("#EXT") && !tag.contains("\n") && !tag.contains("\r") && !recognizedTags.contains(name), "Invalid unknown-tag model entry")
        }
    }
    static func text(_ text: String) throws {
        try require(!text.hasPrefix("\u{FEFF}"), "Playlist must be NFC without BOM")
        try require(!text.replacingOccurrences(of: "\r\n", with: "\n").contains("\r"), "Isolated CR line ending")
        let controls = try text.components(separatedBy: "\n").map { line in
            if line.hasPrefix("#EXTINF:"), let comma = line.unicodeScalars.firstIndex(of: ",") {
                // AVPlayer compatibility: the informative title is opaque UTF-8,
                // not a URI or attribute list. Preserve it, including TAB and
                // non-NFC text; never exempt duration, tag, URI or other fields.
                // TODO: Extend the recorded iOS 26.5 C0/C1/Unicode matrix to
                // older OS versions; this is observed behavior, not an RFC exception.
                try require(!line[comma...].contains("\0"), "NUL in EXTINF title")
                return String(line[..<comma])
            }
            // bis §4.4.5.2 explicitly permits TAB delimiters in this field.
            // Validate the full attribute list before exempting its TABs.
            guard line.hasPrefix("#EXT-X-SKIP:"), line.contains("\t") else { return line }
            let attributes = try AttributeList.parse(Substring(line.dropFirst("#EXT-X-SKIP:".count).trimmingCharacters(in: .newlines)))
            guard case .quoted(let value)? = attributes["RECENTLY-REMOVED-DATERANGES"] else { return line }
            return line.replacingOccurrences(of: "RECENTLY-REMOVED-DATERANGES=\"\(value)\"",
                                            with: "RECENTLY-REMOVED-DATERANGES=\"\(value.replacingOccurrences(of: "\t", with: ""))\"")
        }.joined(separator: "\n")
        try require(controls.utf8.elementsEqual(controls.precomposedStringWithCanonicalMapping.utf8), "Playlist must be NFC without BOM")
        try require(controls.unicodeScalars.allSatisfy {
            $0.value == 10 || $0.value == 13 || !((0...31).contains($0.value) || (127...159).contains($0.value))
        }, "Control character in playlist")
    }
    static func require(_ condition: Bool, _ message: String, line: Int = 0) throws {
        guard condition else { throw PlaylistError.invalidTag(message, line: line) }
    }

    static func uri(_ text: String, relative: Bool = false) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%".utf8)
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.allSatisfy({ allowed.contains($0) }) else { return false }
        for i in bytes.indices where bytes[i] == 37 {
            guard i + 2 < bytes.count,
                  bytes[(i + 1)...(i + 2)].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return false }
        }
        // Older Foundation rejects valid opaque URIs such as data:text/plain;
        // validate their RFC 3986 path/query/fragment grammar directly.
        if let colon = text.firstIndex(of: ":"),
           !text[..<colon].contains(where: { "/?#".contains($0) }) {
            let scheme = text[..<colon]
            let letters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
            guard let first = scheme.utf8.first, letters.contains(first),
                  scheme.utf8.allSatisfy({ letters.contains($0) || (48...57).contains($0) || [43, 45, 46].contains($0) }),
                  !relative else { return false }
            let remainder = text[text.index(after: colon)...]
            if !remainder.hasPrefix("//") {
                let components = remainder.split(separator: "#", omittingEmptySubsequences: false)
                guard components.count <= 2 else { return false }
                let pathQuery = components[0].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
                let pchar = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@%".utf8)
                guard pathQuery[0].utf8.allSatisfy({ pchar.contains($0) || $0 == 47 }) else { return false }
                return (pathQuery.count == 1 || pathQuery[1].utf8.allSatisfy({ pchar.contains($0) || $0 == 47 || $0 == 63 }))
                    && (components.count == 1 || components[1].utf8.allSatisfy({ pchar.contains($0) || $0 == 47 || $0 == 63 }))
            }
        }
        guard let components = URLComponents(string: text),
              components.string?.utf8.elementsEqual(text.utf8) == true,
              URL(string: text) != nil else { return false }
        if relative && components.scheme != nil { return false }
        // A colon in the first path segment requires a valid URI scheme.
        if components.scheme == nil && !text.hasPrefix("/") {
            let first = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            if first.contains(":") { return false }
        }
        return true
    }

    static func variableName(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    /// Unknown enumerated-string values and unknown required attributes cause
    /// the entire tag to be ignored (bis §6.3.1).
    static func ignored(_ tag: String, _ a: AttributeList) -> Bool {
        if a.keys.contains(where: { $0.hasPrefix("REQ-") && !(["#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF"].contains(tag) && $0 == "REQ-VIDEO-LAYOUT") }) { return true }
        if ["#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF"].contains(tag),
           let layout = a["REQ-VIDEO-LAYOUT"]?.rawValue, !layout.contains("{$") {
            let known: Set<String> = ["CH-MONO", "CH-STEREO", "PROJ-RECT", "PROJ-EQUI", "PROJ-HEQU", "PROJ-PRIM"]
            if layout.split(separator: ",").flatMap({ $0.split(separator: "/") }).contains(where: { !known.contains(String($0)) }) { return true }
        }
        var enums: [String: Set<String>] = [:]
        switch tag {
        case "#EXT-X-MEDIA":
            enums = ["TYPE": ["AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS"],
                     "DEFAULT": ["YES", "NO"], "AUTOSELECT": ["YES", "NO"], "FORCED": ["YES", "NO"]]
        case "#EXT-X-KEY", "#EXT-X-SESSION-KEY":
            enums = ["METHOD": ["NONE", "AES-128", "SAMPLE-AES", "SAMPLE-AES-CTR", "AES-256-GCM"]]
        case "#EXT-X-PRELOAD-HINT": enums = ["TYPE": ["PART", "MAP"]]
        case "#EXT-X-PART": enums = ["INDEPENDENT": ["YES"], "GAP": ["YES"]]
        case "#EXT-X-SERVER-CONTROL":
            enums = ["CAN-BLOCK-RELOAD": ["YES"], "CAN-SKIP-DATERANGES": ["YES"]]
        case "#EXT-X-START": enums = ["PRECISE": ["YES", "NO"]]
        case "#EXT-X-SESSION-DATA":
            if a["URI"] != nil { enums = ["FORMAT": ["JSON", "RAW"]] }
        case "#EXT-X-DATERANGE": enums = ["END-ON-NEXT": ["YES"]]
        case "#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF":
            enums = ["HDCP-LEVEL": ["NONE", "TYPE-0", "TYPE-1"], "VIDEO-RANGE": ["SDR", "HLG", "PQ"]]
        default: break
        }
        return enums.contains { key, values in
            guard case .unquoted(let value)? = a[key] else { return false }
            return !values.contains(value)
        }
    }

    static func attributes(_ tag: String, _ a: AttributeList, line: Int = 0) throws {
        if !a.isEmpty { _ = try AttributeList.parse(Substring(a.serialized)) }
        try require(!ignored(tag, a), "Unrecognized enumerated value or required attribute in typed \(tag)", line: line)
        var quoted: Set<String> = []
        var integers: Set<String> = []
        var decimals: Set<String> = []
        var enums: Set<String> = []
        var required: Set<String> = []
        switch tag {
        case "#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-IMAGE-STREAM-INF":
            quoted = ["URI", "CODECS", "SUPPLEMENTAL-CODECS", "ALLOWED-CPC", "REQ-VIDEO-LAYOUT", "STABLE-VARIANT-ID", "AUDIO", "VIDEO", "SUBTITLES", "PATHWAY-ID"]
            integers = ["BANDWIDTH", "AVERAGE-BANDWIDTH", "PROGRAM-ID"]
            decimals = ["FRAME-RATE", "SCORE"]
            enums = ["HDCP-LEVEL", "VIDEO-RANGE"]
            required = tag == "#EXT-X-STREAM-INF" ? ["BANDWIDTH"] : ["BANDWIDTH", "URI"]
        case "#EXT-X-MEDIA":
            quoted = ["URI", "GROUP-ID", "NAME", "LANGUAGE", "ASSOC-LANGUAGE", "STABLE-RENDITION-ID", "INSTREAM-ID", "CHARACTERISTICS", "CHANNELS"]
            integers = ["BIT-DEPTH", "SAMPLE-RATE"]
            enums = ["TYPE", "DEFAULT", "AUTOSELECT", "FORCED"]
            required = ["TYPE", "GROUP-ID", "NAME"]
        case "#EXT-X-KEY", "#EXT-X-SESSION-KEY":
            quoted = ["URI", "KEYFORMAT", "KEYFORMATVERSIONS"]
            enums = ["METHOD"]
            required = a["METHOD"]?.rawValue == "NONE" ? ["METHOD"] : ["METHOD", "URI"]
        case "#EXT-X-MAP":
            quoted = ["URI", "BYTERANGE"]; required = ["URI"]
        case "#EXT-X-PART":
            quoted = ["URI", "BYTERANGE"]; decimals = ["DURATION"]; enums = ["INDEPENDENT", "GAP"]; required = ["URI", "DURATION"]
        case "#EXT-X-PART-INF": decimals = ["PART-TARGET"]; required = ["PART-TARGET"]
        case "#EXT-X-SERVER-CONTROL":
            decimals = ["CAN-SKIP-UNTIL", "HOLD-BACK", "PART-HOLD-BACK"]; enums = ["CAN-SKIP-DATERANGES", "CAN-BLOCK-RELOAD"]
        case "#EXT-X-PRELOAD-HINT":
            quoted = ["URI"]; enums = ["TYPE"]; integers = ["BYTERANGE-START", "BYTERANGE-LENGTH"]; required = ["TYPE", "URI"]
        case "#EXT-X-RENDITION-REPORT":
            quoted = ["URI"]; integers = ["LAST-MSN", "LAST-PART"]; required = ["URI"]
        case "#EXT-X-SKIP":
            integers = ["SKIPPED-SEGMENTS"]; quoted = ["RECENTLY-REMOVED-DATERANGES"]; required = ["SKIPPED-SEGMENTS"]
        case "#EXT-X-START": decimals = ["TIME-OFFSET"]; enums = ["PRECISE"]; required = ["TIME-OFFSET"]
        case "#EXT-X-DEFINE": quoted = ["NAME", "VALUE", "IMPORT", "QUERYPARAM"]
        case "#EXT-X-SESSION-DATA":
            quoted = ["DATA-ID", "VALUE", "URI", "LANGUAGE"]; required = ["DATA-ID"]
            if a["URI"] != nil { enums = ["FORMAT"] }
        case "#EXT-X-CONTENT-STEERING":
            quoted = ["SERVER-URI", "PATHWAY-ID"]; required = ["SERVER-URI"]
        case "#EXT-X-DATERANGE":
            quoted = ["ID", "CLASS", "START-DATE", "END-DATE", "CUE"]
            decimals = ["DURATION", "PLANNED-DURATION"]; enums = ["END-ON-NEXT"]; required = ["ID"]
        default: break
        }
        for key in required { try require(a[key] != nil, "\(tag) without \(key)", line: line) }
        for (key, value) in a {
            if quoted.contains(key) {
                guard case .quoted = value else { throw PlaylistError.invalidTag("\(tag): \(key) must be quoted", line: line) }
            }
            if enums.contains(key) {
                guard case .unquoted = value else { throw PlaylistError.invalidTag("\(tag): \(key) must be unquoted", line: line) }
            }
            if integers.contains(key) { try require(value.integer != nil, "\(tag): Invalid decimal-integer \(key)", line: line) }
            if decimals.contains(key) {
                guard case .unquoted(let raw) = value else { throw PlaylistError.invalidTag("\(tag): \(key) must be unquoted", line: line) }
                try require(HLSNumber.decimal(raw, signed: key == "TIME-OFFSET") != nil, "\(tag): Invalid decimal \(key)", line: line)
            }
            if quoted.contains(key) && ["URI", "SERVER-URI"].contains(key) {
                try require(uri(value.rawValue, relative: tag == "#EXT-X-RENDITION-REPORT"), "\(tag): Invalid URI", line: line)
            }
        }
        if ["#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-IMAGE-STREAM-INF"].contains(tag) {
            if let score = a["SCORE"]?.double { try require(score > 0, "SCORE must be positive", line: line) }
            if let rate = a["FRAME-RATE"]?.rawValue, let point = rate.firstIndex(of: ".") {
                try require(rate[rate.index(after: point)...].dropFirst(3).allSatisfy { $0 == "0" }, "FRAME-RATE must be rounded to three decimal places", line: line)
            }
            if let id = a["STABLE-VARIANT-ID"]?.rawValue {
                try require(id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || "+/=.-_".utf8.contains($0) }, "Invalid STABLE-VARIANT-ID", line: line)
            }
            if let layout = a["REQ-VIDEO-LAYOUT"]?.rawValue {
                for entry in layout.split(separator: ",", omittingEmptySubsequences: false) {
                    let specifiers = entry.split(separator: "/", omittingEmptySubsequences: false)
                    try require(!entry.isEmpty && specifiers.allSatisfy { !$0.isEmpty }, "Empty video layout entry", line: line)
                    let kinds = specifiers.map { String($0.prefix { $0 != "-" }) }
                    try require(Set(kinds).count == kinds.count, "Repeated video layout specifier", line: line)
                }
            }
            if let v = a["RESOLUTION"] {
                guard case .unquoted = v else { throw PlaylistError.invalidTag("Quoted RESOLUTION", line: line) }
                try require(v.resolution != nil, "Invalid RESOLUTION", line: line)
            }
            if let v = a["CLOSED-CAPTIONS"] {
                if case .unquoted("NONE") = v {} else {
                    guard case .quoted = v else { throw PlaylistError.invalidTag("Invalid CLOSED-CAPTIONS", line: line) }
                }
            }
            if tag == "#EXT-X-I-FRAME-STREAM-INF" {
                try require(["FRAME-RATE", "AUDIO", "SUBTITLES", "CLOSED-CAPTIONS"].allSatisfy { a[$0] == nil }, "Forbidden I-FRAME attribute", line: line)
            }
        }
        if tag == "#EXT-X-MEDIA" {
            for key in ["STABLE-RENDITION-ID"] {
                if let value = a[key]?.rawValue {
                    try require(value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || "+/=.-_".utf8.contains($0) }, "Invalid \(key)", line: line)
                }
            }
            let type = a["TYPE"]?.rawValue
            if type == "SUBTITLES" { try require(a["URI"] != nil, "SUBTITLES without URI", line: line) }
            if type == "CLOSED-CAPTIONS" {
                try require(a["URI"] == nil && a["INSTREAM-ID"] != nil, "Invalid CLOSED-CAPTIONS rendition", line: line)
                let id = a["INSTREAM-ID"]!.rawValue
                let service = id.hasPrefix("SERVICE") ? HLSNumber.integer(String(id.dropFirst(7))) : nil
                try require(["CC1", "CC2", "CC3", "CC4"].contains(id) || service.map { (1...63).contains($0) } == true, "Invalid INSTREAM-ID", line: line)
            } else if let id = a["INSTREAM-ID"]?.rawValue {
                try require(id.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 46 }, "Invalid INSTREAM-ID", line: line)
            }
            try require(type == "SUBTITLES" || a["FORCED"] == nil, "FORCED requires SUBTITLES", line: line)
            try require(type == "AUDIO" || (a["BIT-DEPTH"] == nil && a["SAMPLE-RATE"] == nil && a["CHANNELS"] == nil), "Audio attribute on non-audio rendition", line: line)
            if let channels = a["CHANNELS"]?.rawValue {
                let parameters = channels.split(separator: "/", omittingEmptySubsequences: false)
                try require(HLSNumber.integer(String(parameters[0])) != nil, "Invalid CHANNELS count", line: line)
                for parameter in parameters.dropFirst() {
                    try require(parameter.split(separator: ",", omittingEmptySubsequences: false).allSatisfy {
                        !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 45 }
                    }, "Invalid CHANNELS identifier", line: line)
                }
            }
            try require(a["DEFAULT"]?.rawValue != "YES" || a["AUTOSELECT"] == nil || a["AUTOSELECT"]?.rawValue == "YES", "DEFAULT requires AUTOSELECT=YES when present", line: line)
        }
        if ["#EXT-X-KEY", "#EXT-X-SESSION-KEY"].contains(tag) {
            let method = a["METHOD"]?.rawValue
            try require(method != "NONE" || (a.entries.count == 1 && tag != "#EXT-X-SESSION-KEY"), "Invalid METHOD=NONE", line: line)
            try require(!["SAMPLE-AES-CTR", "AES-256-GCM"].contains(method ?? "") || a["IV"] == nil, "IV forbidden for \(method ?? "")", line: line)
            if let iv = a["IV"] { try require(iv.hexBytes != nil && iv.rawValue.count <= 34, "Invalid 128-bit IV", line: line) }
            if let versions = a["KEYFORMATVERSIONS"] {
                try require(versions.rawValue.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { HLSNumber.integer(String($0)).map { $0 > 0 } == true }, "Invalid KEYFORMATVERSIONS", line: line)
            }
        }
        if let range = a["BYTERANGE"], ["#EXT-X-MAP", "#EXT-X-PART"].contains(tag) {
            try require(ByteRange(range.rawValue) != nil, "Invalid BYTERANGE", line: line)
            if tag == "#EXT-X-MAP" { try require(ByteRange(range.rawValue)?.offset != nil, "MAP BYTERANGE requires offset", line: line) }
        }
        if tag == "#EXT-X-SESSION-DATA" {
            try require((a["VALUE"] != nil) != (a["URI"] != nil), "SESSION-DATA needs exactly one of VALUE and URI", line: line)
        }
        if tag == "#EXT-X-DEFINE" {
            let declarations = ["NAME", "IMPORT", "QUERYPARAM"].filter { a[$0] != nil }
            try require(declarations.count == 1, "DEFINE needs exactly one declaration", line: line)
            if let key = declarations.first {
                try require(variableName(a[key]!.rawValue), "Invalid variable name", line: line)
                try require((key == "NAME") == (a["VALUE"] != nil), "Invalid DEFINE VALUE", line: line)
            }
        }
        if tag == "#EXT-X-DATERANGE" {
            for key in ["START-DATE", "END-DATE"] {
                if let value = a[key] { try require(HLSDate.parse(value.rawValue) != nil, "Invalid \(key)", line: line) }
            }
            for (key, value) in a where key.hasPrefix("SCTE35-") {
                try require(value.hexBytes != nil, "Invalid \(key)", line: line)
            }
            for (key, value) in a where key.hasPrefix("X-") {
                if case .quoted = value {} else {
                    try require(value.hexBytes != nil || HLSNumber.decimal(value.rawValue, signed: true) != nil, "Invalid client attribute \(key)", line: line)
                }
            }
            if a["END-ON-NEXT"]?.rawValue == "YES" {
                try require(a["CLASS"] != nil && a["END-DATE"] == nil && a["DURATION"] == nil, "Invalid END-ON-NEXT", line: line)
            }
            if let cue = a["CUE"]?.rawValue {
                try require(cue.split(separator: ",", omittingEmptySubsequences: false).allSatisfy {
                    !$0.isEmpty && !$0.contains(where: \.isWhitespace)
                }, "Invalid CUE enumerated-string-list", line: line)
            }
            let cues = Set((a["CUE"]?.rawValue ?? "").split(separator: ",").map(String.init))
            try require(!cues.contains("PRE") || !cues.contains("POST"), "Conflicting CUE", line: line)
        }
    }

    static func attributeVersion(_ tag: String, _ a: AttributeList) -> UInt64 {
        var v: UInt64 = 1
        if ["#EXT-X-KEY", "#EXT-X-SESSION-KEY"].contains(tag), a["IV"] != nil { v = max(v, 2) }
        if ["#EXT-X-KEY", "#EXT-X-SESSION-KEY"].contains(tag),
           a["KEYFORMAT"] != nil || a["KEYFORMATVERSIONS"] != nil || a["METHOD"]?.rawValue == "SAMPLE-AES" { v = max(v, 5) }
        if tag == "#EXT-X-MAP" { v = max(v, 5) }
        if tag == "#EXT-X-DEFINE" {
            v = max(v, a["QUERYPARAM"] != nil ? 11 : 1)
        }
        if tag == "#EXT-X-SKIP" { v = max(v, a["RECENTLY-REMOVED-DATERANGES"] != nil ? 10 : 9) }
        if a.keys.contains(where: { $0.hasPrefix("REQ-") }) { v = max(v, 12) }
        if tag == "#EXT-X-MEDIA", let id = a["INSTREAM-ID"]?.rawValue {
            v = max(v, a["TYPE"]?.rawValue == "CLOSED-CAPTIONS" ? (id.hasPrefix("SERVICE") ? 7 : 1) : 13)
        }
        return v
    }

    static func keyContext(_ keys: [EncryptionKey]) throws {
        var formats: Set<String> = []
        for key in keys {
            try require(key.method != .none, "Effective key context cannot contain METHOD=NONE")
            try require(formats.insert(key.keyFormat ?? "identity").inserted, "Duplicate effective KEYFORMAT")
            try require(key.iv == nil || key.iv!.count == 16, "IV must contain 16 bytes")
            try attributes("#EXT-X-KEY", key.attributes)
        }
    }

    static func common(_ version: UInt64?, _ start: StartPoint?, _ definitions: [VariableDefinition]) throws -> UInt64 {
        try require(version == nil || version! > 0, "Invalid VERSION")
        if let start { try attributes("#EXT-X-START", start.attributes) }
        var minimum: UInt64 = 1
        var names: Set<String> = []
        for definition in definitions {
            let a = definition.attributes
            try attributes("#EXT-X-DEFINE", a)
            let name = a["NAME"]?.rawValue ?? a["IMPORT"]?.rawValue ?? a["QUERYPARAM"]!.rawValue
            try require(names.insert(name).inserted, "Duplicate variable")
            minimum = max(minimum, attributeVersion("#EXT-X-DEFINE", a))
        }
        return minimum
    }

    static func validate(_ playlist: MultivariantPlaylist) throws -> UInt64 {
        try unknown(playlist.unknownTags + (playlist.variants + playlist.iFrameVariants + playlist.imageVariants).flatMap(\.unknownTags))
        var minimum = try common(playlist.version, playlist.start, playlist.definitions)
        try require(!playlist.definitions.contains { if case .import = $0 { return true }; return false }, "IMPORT only allowed in media playlists")
        var names: Set<String> = []
        var defaults: Set<String> = []
        for rendition in playlist.renditions {
            let a = rendition.attributes
            try attributes("#EXT-X-MEDIA", a)
            let group = rendition.type.description + "\u{0}" + rendition.groupID
            try require(names.insert(group + "\u{0}" + rendition.name).inserted, "Duplicate rendition NAME")
            if rendition.isDefault { try require(defaults.insert(group).inserted, "Multiple DEFAULT renditions in group") }
            minimum = max(minimum, attributeVersion("#EXT-X-MEDIA", a))
        }
        // GROUP-ID identifies the group itself and is not a member attribute.
        let varying: Set<String> = ["GROUP-ID", "URI", "CHANNELS", "BIT-DEPTH", "STABLE-RENDITION-ID", "INSTREAM-ID", "SAMPLE-RATE"]
        for type in Set(playlist.renditions.map(\.type)) {
            let groups = Dictionary(grouping: playlist.renditions.filter { $0.type == type }, by: \.groupID)
            var reference: [String: [String: AttributeValue]]?
            for members in groups.values {
                let values = Dictionary(uniqueKeysWithValues: members.map { member in
                    (member.name, Dictionary(uniqueKeysWithValues: member.attributes.filter { !varying.contains($0.key) }.map { ($0.key, $0.value) }))
                })
                if let reference { try require(values == reference, "Inconsistent members across rendition groups of the same TYPE") }
                else { reference = values }
            }
        }
        for (tag, variants) in [("#EXT-X-STREAM-INF", playlist.variants), ("#EXT-X-I-FRAME-STREAM-INF", playlist.iFrameVariants), ("#EXT-X-IMAGE-STREAM-INF", playlist.imageVariants)] {
            for variant in variants {
                let a = variant.attributes(includeURI: tag != "#EXT-X-STREAM-INF")
                try attributes(tag, a)
                try require(uri(variant.uri), "Invalid variant URI")
                // Validate the stored value before FRAME-RATE serialization rounds it.
                try require(variant.frameRate == nil || (variant.frameRate!.isFinite && variant.frameRate! >= 0), "Invalid FRAME-RATE")
                for (id, type) in [(variant.audioGroupID, Rendition.MediaType.audio), (variant.videoGroupID, .video), (variant.subtitlesGroupID, .subtitles), (variant.closedCaptionsGroupID, .closedCaptions)] {
                    if let id { try require(playlist.renditions.contains { $0.groupID == id && $0.type == type }, "Missing rendition group \(id)") }
                }
                minimum = max(minimum, attributeVersion(tag, a))
            }
        }
        if playlist.variants.contains(where: \.closedCaptionsNone) {
            try require(playlist.variants.allSatisfy(\.closedCaptionsNone), "CLOSED-CAPTIONS=NONE must apply to all variants")
        }
        var dataIDs: Set<String> = []
        for data in playlist.sessionData {
            try attributes("#EXT-X-SESSION-DATA", data.attributes)
            try require(dataIDs.insert(data.dataID + "\u{0}" + (data.language ?? "")).inserted, "Duplicate SESSION-DATA")
        }
        var keys: Set<String> = []
        for key in playlist.sessionKeys {
            try attributes("#EXT-X-SESSION-KEY", key.attributes)
            let identity = [key.method.description, key.uri ?? "", key.iv.map { $0.map(String.init).joined(separator: ".") } ?? "",
                            key.keyFormat ?? "identity", key.keyFormatVersions ?? "1"].joined(separator: "\u{0}")
            try require(keys.insert(identity).inserted, "Duplicate SESSION-KEY")
            minimum = max(minimum, attributeVersion("#EXT-X-SESSION-KEY", key.attributes))
        }
        if let a = playlist.contentSteering {
            try attributes("#EXT-X-CONTENT-STEERING", a)
            if let pathway = a["PATHWAY-ID"]?.rawValue {
                try require(playlist.variants.contains { $0.pathwayID == pathway }, "CONTENT-STEERING references missing pathway")
            }
        }
        return minimum
    }

    static func validate(_ playlist: MediaPlaylist) throws -> UInt64 {
        try unknown(playlist.unknownTags + playlist.trailingUnknownTags + playlist.segments.flatMap(\.unknownTags))
        var minimum = try common(playlist.version, playlist.start, playlist.definitions)
        try require(playlist.targetDuration > 0, "Missing or invalid TARGETDURATION")
        if playlist.iFramesOnly { minimum = max(minimum, 4) }
        let parents = playlist.segments.map { ($0.parts, true) } + [(playlist.trailingParts, false)]
        if parents.contains(where: { !$0.0.isEmpty }) { try require(playlist.partTarget != nil, "PART requires PART-INF") }
        if let target = playlist.partTarget {
            try require(target.isFinite && target > 0, "Invalid PART-TARGET")
            try require(playlist.serverControl?.partHoldBack.map { $0 >= 2 * target } == true, "PART-INF requires PART-HOLD-BACK >= 2 x PART-TARGET")
            for (parts, complete) in parents {
                for (index, part) in parts.enumerated() {
                    try attributes("#EXT-X-PART", part.attributes)
                    try require(part.duration <= target, "PART exceeds PART-TARGET")
                    let exception = part.independent || part.gap || (index + 1 < parts.count && parts[index + 1].gap) || (complete && index == parts.count - 1)
                    try require(exception || part.duration >= target * 0.85, "PART below 85% of PART-TARGET")
                    if part.byteRange?.offset == nil, part.byteRange != nil {
                        try require(index > 0 && parts[index - 1].byteRange != nil && parts[index - 1].uri == part.uri, "Implicit PART range without same-resource predecessor")
                    }
                }
            }
        }
        if let control = playlist.serverControl {
            try attributes("#EXT-X-SERVER-CONTROL", control.attributes)
            if let skip = control.canSkipUntil { try require(skip >= 6 * Double(playlist.targetDuration), "CAN-SKIP-UNTIL below 6 x TARGETDURATION") }
            if let hold = control.holdBack { try require(hold >= 3 * Double(playlist.targetDuration), "HOLD-BACK below 3 x TARGETDURATION") }
            try require(!control.canSkipDateRanges || control.canSkipUntil != nil, "CAN-SKIP-DATERANGES requires CAN-SKIP-UNTIL")
        }
        if playlist.skippedSegments != nil { minimum = max(minimum, playlist.recentlyRemovedDateRanges == nil ? 9 : 10) }
        let lastIndex = playlist.segments.count - 1 + (playlist.trailingParts.isEmpty ? 0 : 1)
        if lastIndex >= 0 { try require(playlist.mediaSequence(ofSegmentAt: lastIndex) != nil, "Media sequence overflow") }
        var discontinuities = playlist.discontinuitySequence
        for (index, segment) in playlist.segments.enumerated() {
            try require(segment.title?.contains("\n") != true && segment.title?.contains("\r") != true, "Invalid EXTINF title")
            try require(segment.programDateTime?.timeIntervalSince1970.isFinite != false, "Invalid PROGRAM-DATE-TIME")
            if index > 0 {
                try require(playlist.segments[index - 1].map == nil || segment.map != nil, "MAP cannot be cleared")
                try require(playlist.segments[index - 1].bitrate == nil || segment.bitrate != nil, "BITRATE cannot be cleared")
            }
            try require(uri(segment.uri), "Invalid segment URI")
            try require(segment.duration.isFinite && segment.duration >= 0, "Invalid EXTINF duration")
            let bounded = (playlist.version ?? 1) >= 6 ? segment.duration.rounded() : segment.duration
            try require(bounded <= Double(playlist.targetDuration), "EXTINF exceeds TARGETDURATION")
            if segment.duration.rounded(.towardZero) != segment.duration { minimum = max(minimum, 3) }
            if segment.byteRange != nil {
                minimum = max(minimum, 4)
                if segment.byteRange?.offset == nil {
                    try require(index > 0 && playlist.segments[index - 1].byteRange != nil && playlist.segments[index - 1].uri == segment.uri, "Implicit BYTERANGE without same-resource predecessor")
                }
            }
            if segment.discontinuity {
                let (next, overflow) = discontinuities.addingReportingOverflow(segment.discontinuityCount)
                try require(!overflow, "Discontinuity sequence overflow")
                discontinuities = next
            }
        }
        let (_, trailingOverflow) = discontinuities.addingReportingOverflow(playlist.trailingDiscontinuityCount)
        try require(!trailingOverflow, "Discontinuity sequence overflow")
        try require(playlist.trailingProgramDateTime?.timeIntervalSince1970.isFinite != false, "Invalid PROGRAM-DATE-TIME")
        let contexts = playlist.segments.map { ($0.keys, $0.map) } + [(playlist.trailingKeys, playlist.trailingMap)]
        for (keys, map) in contexts {
            try keyContext(keys)
            for key in keys {
                minimum = max(minimum, attributeVersion("#EXT-X-KEY", key.attributes))
            }
            if let map {
                try attributes("#EXT-X-MAP", map.attributes)
                minimum = max(minimum, playlist.iFramesOnly ? 5 : 6)
                try keyContext(map.keys)
                for key in map.keys {
                    minimum = max(minimum, attributeVersion("#EXT-X-KEY", key.attributes))
                }
                try require(!map.keys.contains { $0.method == .aes128 && $0.iv == nil }, "AES-128 encrypted MAP requires explicit IV")
            }
        }
        try require(!playlist.hasEndList || playlist.preloadHints.isEmpty, "ENDLIST forbids PRELOAD-HINT")
        for hint in playlist.preloadHints {
            try attributes("#EXT-X-PRELOAD-HINT", hint.attributes)
        }
        for report in playlist.renditionReports { try attributes("#EXT-X-RENDITION-REPORT", report.attributes) }
        let ranges = playlist.segments.flatMap(\.dateRanges) + playlist.trailingDateRanges
        if !ranges.isEmpty { try require(playlist.trailingProgramDateTime != nil || playlist.segments.contains { $0.programDateTime != nil }, "DATERANGE requires PROGRAM-DATE-TIME") }
        var merged: [String: AttributeList] = [:]
        for range in ranges {
            try require(range.startDate?.timeIntervalSince1970.isFinite != false && range.endDate?.timeIntervalSince1970.isFinite != false, "Invalid DATERANGE date")
            let a = range.attributes
            try attributes("#EXT-X-DATERANGE", a)
            var combined = merged[range.id] ?? AttributeList()
            for (key, value) in a {
                if let old = combined[key] { try require(old == value, "Conflicting DATERANGE attribute \(key)") }
                combined[key] = value
            }
            try require(combined["START-DATE"] != nil, "First DATERANGE requires START-DATE")
            try attributes("#EXT-X-DATERANGE", combined)
            if combined["CLASS"]?.rawValue == "com.apple.hls.interstitial" {
                try require((combined["X-ASSET-URI"] != nil) != (combined["X-ASSET-LIST"] != nil), "Interstitial requires exactly one asset URI or asset list")
                for key in ["X-ASSET-URI", "X-ASSET-LIST"] {
                    if let value = combined[key] {
                        guard case .quoted(let value) = value else { throw PlaylistError.invalidTag("Interstitial URI must be quoted", line: 0) }
                        try require(uri(value), "Invalid interstitial URI")
                        if key == "X-ASSET-URI" {
                            try require(value.firstIndex(of: ":").map { !value[..<$0].contains(where: { "/?#".contains($0) }) } == true, "X-ASSET-URI must be absolute")
                        }
                    }
                }
            }
            let start = combined["START-DATE"].flatMap { HLSDate.parse($0.rawValue) }
            let end = combined["END-DATE"].flatMap { HLSDate.parse($0.rawValue) }
            if let start, let end {
                try require(end >= start, "DATERANGE ends before start")
                if let duration = combined["DURATION"]?.double {
                    let tolerance = max(start.timeIntervalSince1970.ulp, end.timeIntervalSince1970.ulp) * 2 + duration.ulp
                    try require(abs(end.timeIntervalSince(start) - duration) <= tolerance, "DATERANGE end/duration mismatch")
                }
            }
            merged[range.id] = combined
        }
        for a in merged.values where a["END-ON-NEXT"]?.rawValue == "YES" {
            let start = HLSDate.parse(a["START-DATE"]!.rawValue)!
            for other in merged.values where other["ID"] != a["ID"] && other["CLASS"] == a["CLASS"] {
                let otherStart = HLSDate.parse(other["START-DATE"]!.rawValue)!
                var otherEnd = other["END-DATE"].flatMap { HLSDate.parse($0.rawValue) }
                    ?? other["DURATION"]?.double.map { otherStart.addingTimeInterval($0) }
                if other["END-ON-NEXT"]?.rawValue == "YES" {
                    otherEnd = merged.values.filter { $0["CLASS"] == other["CLASS"] }
                        .compactMap { HLSDate.parse($0["START-DATE"]!.rawValue) }.filter { $0 > otherStart }.min()
                }
                try require(otherStart != start && !(otherStart < start && otherEnd.map { $0 > start } == true), "Overlapping END-ON-NEXT date ranges")
            }
        }
        return minimum
    }
}
