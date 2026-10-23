import Foundation

extension Playlist {
    /// Renders the playlist as M3U8 text.
    public func render() throws -> String {
        switch self {
        case .multivariant(let playlist): try playlist.render()
        case .media(let playlist): try playlist.render()
        }
    }
}

extension MultivariantPlaylist {
    /// Renders the playlist as M3U8 text.
    public func render() throws -> String {
        let minimum = try HLSStandard.validate(self)
        var out = M3U8Writer()
        out.line("#EXTM3U")
        if version != nil || minimum > 1 { out.tag("EXT-X-VERSION", String(max(version ?? 1, minimum))) }
        if independentSegments { out.line("#EXT-X-INDEPENDENT-SEGMENTS") }
        if let start { out.tag("EXT-X-START", start.attributes) }
        for definition in definitions { out.tag("EXT-X-DEFINE", definition.attributes) }
        for tag in unknownTags { out.line(tag) }
        if let contentSteering { out.tag("EXT-X-CONTENT-STEERING", contentSteering) }
        for data in sessionData { out.tag("EXT-X-SESSION-DATA", data.attributes) }
        for key in sessionKeys { out.tag("EXT-X-SESSION-KEY", key.attributes) }
        if !renditions.isEmpty { out.blank() }
        for rendition in renditions { out.tag("EXT-X-MEDIA", rendition.attributes) }
        if !variants.isEmpty { out.blank() }
        for variant in variants {
            for tag in variant.unknownTags { out.line(tag) }
            out.tag("EXT-X-STREAM-INF", variant.attributes(includeURI: false))
            out.line(variant.uri)
        }
        if !iFrameVariants.isEmpty { out.blank() }
        for variant in iFrameVariants {
            out.tag("EXT-X-I-FRAME-STREAM-INF", variant.attributes(includeURI: true))
        }
        if !imageVariants.isEmpty { out.blank() }
        for variant in imageVariants {
            out.tag("EXT-X-IMAGE-STREAM-INF", variant.attributes(includeURI: true))
        }
        try HLSStandard.text(out.text)
        return out.text
    }
}

extension MediaPlaylist {
    /// Renders the playlist as M3U8 text.
    public func render() throws -> String {
        let minimum = try HLSStandard.validate(self)
        var out = M3U8Writer()
        out.line("#EXTM3U")
        if version != nil || minimum > 1 { out.tag("EXT-X-VERSION", String(max(version ?? 1, minimum))) }
        out.tag("EXT-X-TARGETDURATION", String(targetDuration))
        out.tag("EXT-X-MEDIA-SEQUENCE", String(mediaSequence))
        if discontinuitySequence != 0 { out.tag("EXT-X-DISCONTINUITY-SEQUENCE", String(discontinuitySequence)) }
        if let playlistType { out.tag("EXT-X-PLAYLIST-TYPE", playlistType.rawValue) }
        if iFramesOnly { out.line("#EXT-X-I-FRAMES-ONLY") }
        if independentSegments { out.line("#EXT-X-INDEPENDENT-SEGMENTS") }
        if let start { out.tag("EXT-X-START", start.attributes) }
        for definition in definitions { out.tag("EXT-X-DEFINE", definition.attributes) }
        if let serverControl { out.tag("EXT-X-SERVER-CONTROL", serverControl.attributes) }
        if let partTarget {
            var a = AttributeList()
            a.set("PART-TARGET", double: partTarget)
            out.tag("EXT-X-PART-INF", a)
        }
        for tag in unknownTags { out.line(tag) }
        if let skippedSegments {
            var a = AttributeList()
            a.set("SKIPPED-SEGMENTS", int: skippedSegments)
            a.set("RECENTLY-REMOVED-DATERANGES", quoted: recentlyRemovedDateRanges)
            out.tag("EXT-X-SKIP", a)
        }

        var keys: [EncryptionKey] = []
        var map: MediaInitializationSection?
        var bitrate: UInt64?
        for segment in segments {
            for tag in segment.unknownTags { out.line(tag) }
            for range in segment.dateRanges { out.tag("EXT-X-DATERANGE", range.attributes) }
            if segment.discontinuity { out.line("#EXT-X-DISCONTINUITY") }
            if segment.map != map, let newMap = segment.map {
                out.keys(newMap.keys, current: &keys)
                out.tag("EXT-X-MAP", newMap.attributes)
            }
            out.keys(segment.keys, current: &keys)
            map = segment.map
            if let date = segment.programDateTime { out.tag("EXT-X-PROGRAM-DATE-TIME", HLSDate.format(date)) }
            if segment.bitrate != bitrate, let value = segment.bitrate { out.tag("EXT-X-BITRATE", String(value)) }
            bitrate = segment.bitrate
            if segment.gap { out.line("#EXT-X-GAP") }
            for part in segment.parts { out.tag("EXT-X-PART", part.attributes) }
            if let byteRange = segment.byteRange { out.tag("EXT-X-BYTERANGE", byteRange.description) }
            out.tag("EXTINF", formatDecimal(segment.duration) + "," + (segment.title ?? ""))
            out.line(segment.uri)
        }

        for range in trailingDateRanges { out.tag("EXT-X-DATERANGE", range.attributes) }
        if trailingDiscontinuity { out.line("#EXT-X-DISCONTINUITY") }
        if trailingMap != map, let section = trailingMap {
            out.keys(section.keys, current: &keys)
            out.tag("EXT-X-MAP", section.attributes)
        }
        out.keys(trailingKeys, current: &keys)
        if let date = trailingProgramDateTime { out.tag("EXT-X-PROGRAM-DATE-TIME", HLSDate.format(date)) }
        for part in trailingParts { out.tag("EXT-X-PART", part.attributes) }
        for tag in trailingUnknownTags { out.line(tag) }
        for hint in preloadHints { out.tag("EXT-X-PRELOAD-HINT", hint.attributes) }
        for report in renditionReports { out.tag("EXT-X-RENDITION-REPORT", report.attributes) }
        if hasEndList { out.line("#EXT-X-ENDLIST") }
        try HLSStandard.text(out.text)
        return out.text
    }
}

private struct M3U8Writer {
    var text = ""

    mutating func line(_ line: String) {
        text += line
        text += "\n"
    }

    mutating func blank() {
        if !text.hasSuffix("\n\n") { text += "\n" }
    }

    mutating func tag(_ name: String, _ value: String) {
        line("#\(name):\(value)")
    }

    mutating func tag(_ name: String, _ attributes: AttributeList) {
        line("#\(name):\(attributes.serialized)")
    }

    mutating func keys(_ next: [EncryptionKey], current: inout [EncryptionKey]) {
        guard next != current else { return }
        let formats = Set(next.map { $0.keyFormat ?? "identity" })
        if next.isEmpty || current.contains(where: { !formats.contains($0.keyFormat ?? "identity") }) {
            tag("EXT-X-KEY", ["METHOD": .unquoted("NONE")])
        }
        for key in next { tag("EXT-X-KEY", key.attributes) }
        current = next
    }
}
