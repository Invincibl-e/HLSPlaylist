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
