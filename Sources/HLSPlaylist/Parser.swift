import Foundation

/// Errors thrown while parsing a playlist.
public enum PlaylistError: Error, Sendable, Equatable, LocalizedError {
    /// The text does not start with `#EXTM3U`.
    case missingHeader
    /// The playlist contains both multivariant and media tags.
    case ambiguousPlaylistType
    /// An undefined variable reference.
    case undefinedVariable(name: String, line: Int)
    /// A tag violates the playlist grammar or its defined constraints.
    case invalidTag(String, line: Int)
    /// The data is not valid UTF-8.
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .missingHeader: "The playlist does not begin with #EXTM3U."
        case .ambiguousPlaylistType: "The playlist mixes multivariant and media playlist tags."
        case .undefinedVariable(let name, let line): "Undefined variable \"\(name)\" on line \(line)."
        case .invalidTag(let tag, let line): "Invalid tag \"\(tag)\" on line \(line)."
        case .invalidEncoding: "The playlist is not valid UTF-8."
        }
    }
}

/// Configures playlist parsing.
public struct ParseOptions: Sendable {
    /// Values available to `EXT-X-DEFINE:IMPORT` (from the multivariant playlist).
    public var importedVariables: [String: String] = [:]
    /// The playlist's URL, used for `EXT-X-DEFINE:QUERYPARAM`.
    public var playlistURL: URL?

    public init(importedVariables: [String: String] = [:], playlistURL: URL? = nil) {
        self.importedVariables = importedVariables
        self.playlistURL = playlistURL
    }
}

/// The parsed playlist and its variable definitions.
public struct ParseResult: Sendable {
    public var playlist: Playlist
    /// Variables defined by the playlist (for passing to child playlists).
    public var variables: [String: String]
}

extension Playlist {
    /// Parses playlist text.
    public init(_ text: String, options: ParseOptions = ParseOptions()) throws {
        self = try PlaylistParser(options: options).parse(text).playlist
    }

    /// Parses UTF-8 playlist data.
    public init(data: Data, options: ParseOptions = ParseOptions()) throws {
        self = try PlaylistParser(options: options).parse(data).playlist
    }
}

/// Parses HLS playlists (RFC 8216 and draft-pantos-hls-rfc8216bis).
public struct PlaylistParser: Sendable {
    public var options: ParseOptions

    public init(options: ParseOptions = ParseOptions()) {
        self.options = options
    }

    public func parse(_ data: Data) throws -> ParseResult {
        try HLSStandard.require(!data.starts(with: [0xEF, 0xBB, 0xBF]), "Playlist must be NFC without BOM")
        guard let text = String(data: data, encoding: .utf8) else { throw PlaylistError.invalidEncoding }
        return try parse(text)
    }

    public func parse(_ text: String) throws -> ParseResult {
        var state = ParserState(options: options)
        // RFC 8216 §4 / bis §4.1, with the documented informative-title
        // compatibility exception in HLSStandard.text.
        try HLSStandard.text(text)
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        var lineNumber = 0
        guard lines.next() == "#EXTM3U" else { throw PlaylistError.missingHeader }
        lineNumber = 1

        while let raw = lines.next() {
            lineNumber += 1
            let line = String(raw)
            if line.isEmpty { continue }
            try state.consume(line, lineNumber: lineNumber)
        }
        return try state.finish()
    }
}

// MARK: - Parser state machine

private struct ParserState {
    let options: ParseOptions
    var variables: [String: String] = [:]
    var definitions: [VariableDefinition] = []
    var seen: Set<String> = []
    var minimumVersion: UInt64 = 1
    var ignoredStreamURI = false
    var sawDiscontinuity = false

    // Common header
    var version: UInt64?
    var independentSegments = false
    var start: StartPoint?
    var headerUnknown: [String] = []

    // Multivariant
    var isMultivariant = false
    var variants: [Variant] = []
    var iFrameVariants: [Variant] = []
    var imageVariants: [Variant] = []
    var renditions: [Rendition] = []
    var sessionData: [SessionData] = []
    var sessionKeys: [EncryptionKey] = []
    var contentSteering: AttributeList?
    var pendingStreamInf: AttributeList?

    // Media
    var isMedia = false
    var media = MediaPlaylist(targetDuration: 0)
    var pendingInf: (duration: Double, title: String?)?
    var pendingByteRange: ByteRange?
    var pendingDiscontinuityCount: UInt64 = 0
    var pendingProgramDateTime: Date?
    var pendingDateRanges: [DateRange] = []
    var pendingGap = false
    var pendingParts: [PartialSegment] = []
    var pendingUnknown: [String] = []
    var currentKeys: [EncryptionKey] = []
    var currentMap: MediaInitializationSection?
    var currentBitrate: UInt64?
    var targetDurationLine: Int?

    init(options: ParseOptions) {
        self.options = options
    }

    mutating func warn(_ message: String, _ line: Int) throws {
        throw PlaylistError.invalidTag(message, line: line)
    }

    mutating func consume(_ rawLine: String, lineNumber: Int) throws {
        if rawLine.hasPrefix("#EXT-X-DEFINE:") {
            let a = try parseAttributes(rawLine.dropFirst("#EXT-X-DEFINE:".count), tag: "#EXT-X-DEFINE", line: lineNumber)
            if a.keys.contains(where: { $0.hasPrefix("REQ-") }) { minimumVersion = max(minimumVersion, 12) }
            if !HLSStandard.ignored("#EXT-X-DEFINE", a) {
                try HLSStandard.attributes("#EXT-X-DEFINE", a, line: lineNumber)
                minimumVersion = max(minimumVersion, HLSStandard.attributeVersion("#EXT-X-DEFINE", a))
                try define(a, lineNumber)
            }
            return
        }
        let line = rawLine

        guard line.hasPrefix("#") else {
            if ignoredStreamURI { ignoredStreamURI = false; return }
            let expanded = try substitute(line, lineNumber)
            try HLSStandard.require(HLSStandard.uri(expanded), "Invalid URI", line: lineNumber)
            try uri(expanded, lineNumber)
            return
        }
        guard line.hasPrefix("#EXT") else { return } // comment

        let name: Substring
        let value: Substring
        if let colon = line.firstIndex(of: ":") {
            name = line[line.startIndex..<colon]
            value = line[line.index(after: colon)...]
        } else {
            name = Substring(line)
            value = ""
        }
        let tag = String(name)
        if tag == "#EXTM3U" { try warn("Duplicate EXTM3U", lineNumber) }
        let flags = HLSStandard.flags
        let singletons = HLSStandard.singletons
        if flags.contains(tag) {
            try HLSStandard.require(!line.contains(":"), "\(tag) cannot have a value", line: lineNumber)
        }
        if singletons.contains(tag) { try HLSStandard.require(seen.insert(tag).inserted, "Duplicate \(tag)", line: lineNumber) }
        if tag == "#EXT-X-STREAM-INF" {
            try HLSStandard.require(pendingStreamInf == nil && !ignoredStreamURI, "STREAM-INF without URI", line: lineNumber)
        }
        // Own the ASCII tag name before hashing: older Swift runtimes can hash
        // a Substring differently when its backing line contains Unicode.
        let attributeTags = HLSStandard.attributeTags
        let parsedAttributes = attributeTags.contains(String(name))
            ? try parseAttributes(value, tag: name, line: lineNumber) : AttributeList()
        if attributeTags.contains(tag) {
            if parsedAttributes.keys.contains(where: { $0.hasPrefix("REQ-") }) { minimumVersion = max(minimumVersion, 12) }
            if HLSStandard.ignored(tag, parsedAttributes) {
                if ["#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-IMAGE-STREAM-INF", "#EXT-X-MEDIA", "#EXT-X-SESSION-DATA", "#EXT-X-SESSION-KEY", "#EXT-X-CONTENT-STEERING"].contains(tag) { isMultivariant = true }
                else if tag != "#EXT-X-STREAM-INF" && tag != "#EXT-X-START" { isMedia = true }
                if tag == "#EXT-X-STREAM-INF" {
                    try HLSStandard.require(pendingStreamInf == nil && !ignoredStreamURI, "STREAM-INF without URI", line: lineNumber)
                    isMultivariant = true
                    ignoredStreamURI = true
                }
                return
            }
            try HLSStandard.attributes(tag, parsedAttributes, line: lineNumber)
            minimumVersion = max(minimumVersion, HLSStandard.attributeVersion(tag, parsedAttributes))
        }
        if HLSStandard.parameterTags.contains(tag) {
            try HLSStandard.require(line.contains(":"), "\(tag) requires a value", line: lineNumber)
        }
        // PDT annotates the parent segment even when emitted after its PARTs
        // (Gcore live playlists). KEY/MAP/discontinuity ordering remains binding.
        if ["#EXT-X-DISCONTINUITY", "#EXT-X-KEY", "#EXT-X-MAP"].contains(tag) {
            try HLSStandard.require(pendingParts.isEmpty, "\(tag) must precede first PART", line: lineNumber)
        }
        func integer(_ value: Substring) throws -> UInt64 {
            guard let number = HLSNumber.integer(String(value)) else { throw PlaylistError.invalidTag("Invalid \(tag) decimal-integer", line: lineNumber) }
            return number
        }
        let attributes = { parsedAttributes }

        switch name {
        // Basic / shared
        case "#EXT-X-VERSION":
            version = try integer(value)
            try HLSStandard.require(version! > 0, "Invalid VERSION", line: lineNumber)
        case "#EXT-X-INDEPENDENT-SEGMENTS": independentSegments = true
        case "#EXT-X-START":
            start = StartPoint(attributes: attributes())
            if start == nil { try warn("EXT-X-START without TIME-OFFSET", lineNumber) }

        // Multivariant
        case "#EXT-X-STREAM-INF":
            isMultivariant = true
            if pendingStreamInf != nil { try warn("EXT-X-STREAM-INF without URI", lineNumber) }
            pendingStreamInf = attributes()
        case "#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-IMAGE-STREAM-INF":
            isMultivariant = true
            let a = attributes()
            let variant = Variant(uri: a["URI"]?.rawValue ?? "", attributes: a)
            if name == "#EXT-X-IMAGE-STREAM-INF" { imageVariants.append(variant) }
            else { iFrameVariants.append(variant) }
        case "#EXT-X-MEDIA":
            isMultivariant = true
            renditions.append(Rendition(attributes: attributes()))
        case "#EXT-X-SESSION-DATA":
            isMultivariant = true
            sessionData.append(SessionData(attributes: attributes()))
        case "#EXT-X-SESSION-KEY":
            isMultivariant = true
            sessionKeys.append(EncryptionKey(attributes: attributes()))
        case "#EXT-X-CONTENT-STEERING":
            isMultivariant = true
            contentSteering = attributes()

        // Media
        case "#EXTINF":
            isMedia = true
            try HLSStandard.require(pendingInf == nil, "Duplicate EXTINF without URI", line: lineNumber)
            // A title may start with a combining scalar; Swift Character
            // splitting would then treat the comma and that scalar as one unit.
            guard let comma = value.unicodeScalars.firstIndex(of: ","),
                  let duration = HLSNumber.decimal(String(value[..<comma])),
                  duration.isFinite, duration >= 0 else {
                try warn("Invalid EXTINF duration", lineNumber)
                return
            }
            if value[..<comma].contains(".") { minimumVersion = max(minimumVersion, 3) }
            let title = String(value[value.unicodeScalars.index(after: comma)...])
            pendingInf = (duration, title.isEmpty ? nil : title)
        case "#EXT-X-TARGETDURATION":
            isMedia = true
            if targetDurationLine != nil { try warn("Duplicate EXT-X-TARGETDURATION", lineNumber) }
            targetDurationLine = lineNumber
            if let target = HLSNumber.integer(String(value)), target > 0 {
                media.targetDuration = target
            } else {
                try warn("Invalid EXT-X-TARGETDURATION", lineNumber)
            }
        case "#EXT-X-MEDIA-SEQUENCE":
            isMedia = true
            try HLSStandard.require(media.segments.isEmpty && pendingParts.isEmpty, "MEDIA-SEQUENCE after first segment", line: lineNumber)
            media.mediaSequence = try integer(value)
        case "#EXT-X-DISCONTINUITY-SEQUENCE":
            isMedia = true
            try HLSStandard.require(media.segments.isEmpty && pendingParts.isEmpty && !sawDiscontinuity, "DISCONTINUITY-SEQUENCE out of order", line: lineNumber)
            media.discontinuitySequence = try integer(value)
        case "#EXT-X-PLAYLIST-TYPE":
            isMedia = true
            try HLSStandard.require(!value.isEmpty && !value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "," }), "Invalid PLAYLIST-TYPE enumerated-string", line: lineNumber)
            media.playlistType = MediaPlaylist.PlaylistType(rawValue: String(value))
        case "#EXT-X-I-FRAMES-ONLY":
            isMedia = true
            media.iFramesOnly = true
            minimumVersion = max(minimumVersion, 4)
        case "#EXT-X-ENDLIST":
            isMedia = true
            media.hasEndList = true
        case "#EXT-X-BYTERANGE":
            isMedia = true
            try HLSStandard.require(pendingByteRange == nil, "Duplicate BYTERANGE without segment URI", line: lineNumber)
            pendingByteRange = ByteRange(String(value))
            if pendingByteRange == nil { try warn("Invalid EXT-X-BYTERANGE", lineNumber) }
            minimumVersion = max(minimumVersion, 4)
        case "#EXT-X-DISCONTINUITY":
            isMedia = true
            let (next, overflow) = pendingDiscontinuityCount.addingReportingOverflow(1)
            try HLSStandard.require(!overflow, "Discontinuity count overflow", line: lineNumber)
            pendingDiscontinuityCount = next
            sawDiscontinuity = true
        case "#EXT-X-KEY":
            isMedia = true
            let key = EncryptionKey(attributes: attributes())
            if key.method == .none {
                currentKeys = []
            } else {
                currentKeys.removeAll { ($0.keyFormat ?? "identity") == (key.keyFormat ?? "identity") }
                currentKeys.append(key)
            }
        case "#EXT-X-MAP":
            isMedia = true
            currentMap = MediaInitializationSection(attributes: attributes())
            currentMap?.keys = currentKeys
        case "#EXT-X-PROGRAM-DATE-TIME":
            isMedia = true
            pendingProgramDateTime = HLSDate.parse(String(value))
            if pendingProgramDateTime == nil { try warn("Invalid EXT-X-PROGRAM-DATE-TIME", lineNumber) }
        case "#EXT-X-DATERANGE":
            isMedia = true
            pendingDateRanges.append(DateRange(attributes: attributes()))
        case "#EXT-X-GAP":
            isMedia = true
            pendingGap = true
        case "#EXT-X-BITRATE":
            isMedia = true
            currentBitrate = try integer(value)
        case "#EXT-X-PART":
            isMedia = true
            pendingParts.append(PartialSegment(attributes: attributes()))
        case "#EXT-X-PART-INF":
            isMedia = true
            media.partTarget = attributes()["PART-TARGET"]?.double
        case "#EXT-X-SERVER-CONTROL":
            isMedia = true
            media.serverControl = ServerControl(attributes: attributes())
        case "#EXT-X-SKIP":
            isMedia = true
            try HLSStandard.require(media.segments.isEmpty && pendingParts.isEmpty, "SKIP after first segment", line: lineNumber)
            let a = attributes()
            media.skippedSegments = a["SKIPPED-SEGMENTS"]?.integer
            media.recentlyRemovedDateRanges = a["RECENTLY-REMOVED-DATERANGES"]?.rawValue
        case "#EXT-X-PRELOAD-HINT":
            isMedia = true
            media.preloadHints.append(PreloadHint(attributes: attributes()))
        case "#EXT-X-RENDITION-REPORT":
            isMedia = true
            media.renditionReports.append(RenditionReport(attributes: attributes()))
        default:
            if isMedia, !media.segments.isEmpty || pendingInf != nil || !pendingParts.isEmpty {
                pendingUnknown.append(line)
            } else if pendingStreamInf != nil || !variants.isEmpty {
                pendingUnknown.append(line)
            } else {
                headerUnknown.append(line)
            }
        }
    }

    mutating func parseAttributes(_ text: Substring, tag: Substring, line: Int) throws -> AttributeList {
        var a: AttributeList
        do { a = try AttributeList.parse(text) } catch let PlaylistError.invalidTag(message, _) {
            throw PlaylistError.invalidTag("\(tag): \(message)", line: line)
        }
        if HLSStandard.ignored(String(tag), a) { return a }
        // bis §4.3 also permits substitution in hexadecimal-sequence values.
        for (key, value) in a {
            if case .quoted(let raw) = value {
                a[key] = .quoted(try substitute(raw, line))
            } else if value.rawValue.hasPrefix("0x") || value.rawValue.hasPrefix("0X") ||
                        (key == "IV" && ["#EXT-X-KEY", "#EXT-X-SESSION-KEY"].contains(String(tag))) ||
                        (key.hasPrefix("SCTE35-") && tag == "#EXT-X-DATERANGE") {
                a[key] = .unquoted(try substitute(value.rawValue, line))
            }
        }
        return a
    }

    mutating func uri(_ line: String, _ lineNumber: Int) throws {
        if let streamInf = pendingStreamInf {
            var variant = Variant(uri: line, attributes: streamInf)
            variant.unknownTags = pendingUnknown
            pendingUnknown = []
            variants.append(variant)
            pendingStreamInf = nil
            return
        }
        guard let inf = pendingInf else {
            try warn("URI without EXTINF or EXT-X-STREAM-INF: \(line)", lineNumber)
            return
        }
        var segment = Segment(
            uri: line,
            duration: inf.duration,
            title: inf.title,
            byteRange: pendingByteRange,
            discontinuity: pendingDiscontinuityCount != 0,
            keys: currentKeys,
            map: currentMap,
            programDateTime: pendingProgramDateTime
        )
        segment.dateRanges = pendingDateRanges
        segment.discontinuityCount = pendingDiscontinuityCount
        segment.gap = pendingGap
        segment.bitrate = currentBitrate
        segment.parts = pendingParts
        segment.unknownTags = pendingUnknown
        media.segments.append(segment)

        pendingInf = nil
        pendingByteRange = nil
        pendingDiscontinuityCount = 0
        pendingProgramDateTime = nil
        pendingDateRanges = []
        pendingGap = false
        pendingParts = []
        pendingUnknown = []
    }

    mutating func define(_ attributes: AttributeList, _ lineNumber: Int) throws {
        guard var definition = VariableDefinition(attributes: attributes) else {
            try warn("EXT-X-DEFINE without NAME, IMPORT or QUERYPARAM", lineNumber)
            return
        }
        let name: String
        switch definition {
        case .value(let variable, _), .import(let variable), .queryParameter(let variable): name = variable
        }
        if variables[name] != nil { try warn("Duplicate variable \"\(name)\"", lineNumber) }
        switch definition {
        case .value(let name, let value):
            variables[name] = value
            definition = .value(name: name, value: value)
        case .import(let name):
            if let value = options.importedVariables[name] {
                try HLSStandard.require(!value.contains("\"") && value.unicodeScalars.allSatisfy { $0.value >= 32 && !((127...159).contains($0.value)) }, "Invalid imported variable value", line: lineNumber)
                variables[name] = value
            } else {
                try warn("Imported variable \"\(name)\" is not available", lineNumber)
            }
        case .queryParameter(let name):
            let value = options.playlistURL.flatMap { URIReference($0.absoluteString)?.queryValue(named: name) }
            if let value {
                try HLSStandard.require(!value.contains("\"") && value.unicodeScalars.allSatisfy { $0.value >= 32 && !((127...159).contains($0.value)) }, "Invalid query variable value", line: lineNumber)
                variables[name] = value
            } else {
                try warn("Query parameter \"\(name)\" is not available", lineNumber)
            }
        }
        definitions.append(definition)
    }

    mutating func substitute(_ line: String, _ lineNumber: Int) throws -> String {
        guard line.contains("{$") else { return line }
        minimumVersion = max(minimumVersion, 8)
        var output = ""
        var rest = Substring(line)
        while let open = rest.range(of: "{$") {
            output += rest[rest.startIndex..<open.lowerBound]
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else {
                output += rest[open.lowerBound...]
                return output
            }
            let name = String(rest[open.upperBound..<close])
            if !HLSStandard.variableName(name) {
                output += rest[open.lowerBound...close]
            } else if let value = variables[name] {
                output += value
            } else {
                throw PlaylistError.undefinedVariable(name: name, line: lineNumber)
            }
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }

    mutating func finish() throws -> ParseResult {
        if isMultivariant && isMedia { throw PlaylistError.ambiguousPlaylistType }
        if pendingStreamInf != nil || ignoredStreamURI { try warn("Trailing EXT-X-STREAM-INF without URI", 0) }

        if isMultivariant {
            var playlist = MultivariantPlaylist(version: version, independentSegments: independentSegments, variants: variants, renditions: renditions)
            playlist.start = start
            playlist.definitions = definitions
            playlist.iFrameVariants = iFrameVariants
            playlist.imageVariants = imageVariants
            playlist.sessionData = sessionData
            playlist.sessionKeys = sessionKeys
            playlist.contentSteering = contentSteering
            playlist.unknownTags = headerUnknown + pendingUnknown
            let required = max(minimumVersion, try HLSStandard.validate(playlist))
            try HLSStandard.require((version ?? 1) >= required, "VERSION below required \(required)")
            return ParseResult(playlist: .multivariant(playlist), variables: variables)
        }

        if pendingInf != nil { try warn("Trailing EXTINF without URI", 0) }
        if isMedia, targetDurationLine == nil { try warn("Missing EXT-X-TARGETDURATION", 0) }
        media.version = version
        media.independentSegments = independentSegments
        media.start = start
        media.definitions = definitions
        media.unknownTags = headerUnknown
        media.trailingParts = pendingParts
        media.trailingKeys = currentKeys
        media.trailingMap = currentMap
        media.trailingDiscontinuityCount = pendingDiscontinuityCount
        media.trailingProgramDateTime = pendingProgramDateTime
        media.trailingDateRanges = pendingDateRanges
        media.trailingUnknownTags = pendingUnknown
        let required = max(minimumVersion, try HLSStandard.validate(media))
        try HLSStandard.require((version ?? 1) >= required, "VERSION below required \(required)")
        return ParseResult(playlist: .media(media), variables: variables)
    }
}
