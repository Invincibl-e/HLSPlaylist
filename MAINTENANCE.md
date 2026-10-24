# Independent maintenance

This repository is maintained as an independent fork. Upstream HLSPlaylist is
not a synchronization target: changes are reviewed against the pinned HLS
specifications, this fork's API, and its regression suite. There is no automatic
upstream merge or rebase policy.

The original MIT license and attribution remain in LICENSE. Third-party test
sources retain their licenses, source URLs, revisions, and hashes under
Verification/corpus. Using those sources as regression inputs does not imply
matching their permissive parsing behavior.

The current specification baseline is RFC 8216 and
draft-pantos-hls-rfc8216bis-22 (protocol version 13). A later specification
revision requires an explicit standards audit and regression update.

Playback compatibility has one deliberately scoped exception: EXTINF text after
the first comma is informative UTF-8. Preserve its scalar bytes (including TAB,
other non-NUL controls and non-NFC text); continue rejecting NUL and title CR/LF.
This follows recorded AVPlayer/Apple-tool observations, not a normative exception
or an EXT-X-VERSION threshold. Duration, tag, URI and attribute syntax retain
their validation. The production TODO records the remaining older-OS character
matrix; no finite sample proves every Unicode sequence or future OS.

The default suite includes 193 public provider manifest snapshots with URLs and
SHA-256, an acceptance floor for the existing archive/external corpus, and
generated grammar/feature combinations. Each accepted manifest must parse,
render, rewrite, reparse and restore its pre-rewrite semantics. Expected public
rejections are explicit known compatibility boundaries, not successful playback.
Never refresh acceptance expectations automatically from the implementation.

Run `python3 Verification/suite.py` before accepting parser, model, serializer,
or URI changes. CI runs this same offline entry point and uploads its evidence.
Apple tooling is a separate explicit run:

```sh
HLS_APPLE_BIN=/usr/local/bin python3 Verification/suite.py \
  --apple --fixtures /path/to/prepared/playback-fixtures
```

Apple tools are proprietary and are not redistributed here. Every invocation
creates a fresh evidence directory. Missing tools, crashes, timeouts, mismatched
probe output and failed expectations must fail the run.

This library handles playlist data. It is not a media decoder, HTTP server,
DRM client, adaptive player, Content Steering client, or interstitial scheduler.
Coverage and official-tool limitations must remain explicit; passing tests must
not be described as certification of all HLS/LL-HLS implementations.
