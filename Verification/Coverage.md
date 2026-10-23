# Standards coverage and verification boundaries

Baseline: RFC 8216 (2017) and draft-pantos-hls-rfc8216bis-22 (2026-05,
protocol version 13). The latter is a draft, not a published replacement RFC.

[NormativeInventory.json](NormativeInventory.json) inventories 428 bis-22 and
226 RFC 8216 paragraphs containing normative keywords, including SHOULD rules.
Each entry records source section, original line, text, source URL/hash, scope,
and matching independent oracle names. This is an inventory, **not 654 proved
compliance claims**. A section with tests does not establish every sentence in
that section. Regenerate it with `catalog.py` and the original plain-text
standards; do not use HTML copies whose navigation text pollutes the inventory.

The executable checks below apply to constraints observable in this library.
All fixed normative inputs and expected acceptance/rejection are authored
independently of Probe's decisions in [standards.py](standards.py).

| Area / bis-22 section | Executable checks | External obligations |
|---|---|---|
| Text, attributes, numbers, URI (§4.1–4.3) | Swift StandardsTests, AttributeList tests; fixed grammar/BOM/NFC/UTF-8/numeric oracles; 54 shared URI gold vectors (all 42 RFC 3986 §5.4 strict examples), 2,000 constructed properties, 4 deep paths; three public APIs checked independently on Mac/iOS simulator and full-profile iOS device; original 28 HLS attribute vectors and 12 direct dot-segment vectors retained | HTTP Content-Type, redirect URL passed by caller; untested OS versions and URI inputs |
| Basic/shared tags (§4.4.1–4.4.2) | Header, singleton flags, START, DEFINE scope, imports/query decoding, substitution | Matching START across parent/child responses |
| Media playlist tags (§4.4.3) | Required target, integer bounds, sequences/order/overflow, versions, LL target/control bounds | Across-refresh target stability, EVENT/VOD immutability |
| Segment tags (§4.4.4) | EXTINF precision/version/target; range predecessor; KEY/MAP declaration context; PDT/calendar; PART bounds/order/exceptions | Actual media duration, discontinuities, byte layout, BITRATE accuracy |
| DATERANGE (§4.4.5.1) | Required/merged attributes, date arithmetic, END-ON-NEXT overlap, CUE conflict, extension value types | SCTE-35 message semantics, date-to-media timing, ID reuse across refreshes |
| Delta/preload/report (§4.4.5.2–4.4.5.4) | SKIP versions/order; empty and TAB-delimited removed IDs; scoped TAB exception; ENDLIST/preload; relative report URI, counters, unknown TYPE ignore | Dynamic origin and device tests below exercise delta merge, hint future identity, blocking timing and rendition state |
| Renditions/variants (§4.4.6.1–4.4.6.3) | Required/typed attributes, group links, default/name uniqueness, same-type group equivalence, CHANNELS syntax, I-frame forbidden fields | Codec/sample correspondence, aggregate bandwidth, resolution and channel count |
| Session data/keys (§4.4.6.4–4.4.6.5) | VALUE/URI exclusivity/uniqueness; FORMAT syntax/unknown enum; key method/duplicate identity | External JSON/RAW contents; parent/child key agreement |
| Steering tag (§4.4.6.6) | URI syntax, uniqueness, initial pathway reference, URI rewrite | Steering Manifest protocol/JSON, cloning and network scheduling (§7) |
| Forward compatibility (§6.3.1, §6.3.9) | Unknown tags/attributes, unknown enum, REQ- handling, associated STREAM-INF URI ignore | Player stopping/decoder handling when no usable streams remain |
| Protocol versions (§8) | Minimum-version positive/negative pairs; parse never silently upgrades; model rendering emits required version | Client's supported playback versions |
| Interstitial playlist schema (Appendix D.2) | Exactly one asset source, absolute X-ASSET-URI, URI syntax; rewrite both placements | JSON ASSETS objects, playback restrictions, nested scheduling, live timeline |
| Other optional extensions (Appendices E–G) | Generic SESSION-DATA/DATERANGE fields preserved under core attribute grammar | Localization/UI selection, preload resource semantics and scheduling |

Additional checks: 73 archived manifests, 329 pinned external static manifests,
11 isolated boundaries, 2,000 deterministic valid VOD properties with six
independent assertions each, and 10,000 mutated-input iterations in Swift.
External corpora include deliberately invalid and incomplete fixtures. Accepted
round-trip counts are preservation evidence, not an independent validity oracle.

Probe records `stage` and `parseAccepted`: parse failures cannot be confused with
render, round-trip or rewrite failures. The harness requires exactly one ordered
response per input, validates statuses, and fails on process errors. Failure
injection for URI oracles rejects missing/wrong public API fields, reordered
identities, empty inputs and truncated/extra results. URI gold checks are
independent of cross-platform equality; `uri-oracles.py` never uses urljoin
or Probe results to construct expected URLs.
Failure
injection also rejects empty/incomplete/simulator device results, missing
progress, HTTP/2 fallback and unrelated network failures in negative cases.

Apple verification uses official mediastreamvalidator 2.0.284 and hlsreport.
Four positive media families (TS, fMP4, AES key rotation, fMP4 range) are checked
in original/render/rewrite modes. The PART fixture uses real fMP4 fragments:
each PART contains the parent's samples, so its media identity is independently
known. It is a static VOD metadata/media check, not a live LL origin.

The HTTP/2 transport uses Go's TLS server with actual ALPN negotiation. Static
PART checks no longer exempt 551002 or any other mandatory Apple finding.
`ll_validate.py` adds generated 0.5-second independent CMAF fragments (four per
parent) with ffprobe keyframe/timestamp checks, real-time blocking reload,
PART rollover, source timeout, delta YES/v2, removed date-range identities,
preload waiting, range responses, sliding sequences and request cancellation.
Original/render/rewrite each run independent HTTP/2 assertions and the official
validator, with original JSON/HTML and wire logs retained.

`device.py` builds, installs and runs the actual AVPlayer app and iOS library
probe. Its three local LL cases require actual HTTP/2 blocking delta requests,
first frame, progression, pause and resume. The rootless lab phone temporarily
trusts a generated localhost-only certificate through trustd APIs; removal and
negative trust re-evaluation are checked during cleanup. Public invalid
playlists remain negative controls, with server-side 422 and parser reasons;
network failures alone cannot satisfy those controls.

The full CI profile requires official tools and a connected provisioned device;
the hosted offline profile is named separately. AES reports explicitly state
that the validator does not decrypt that content; real AVPlayer playback is
the decryption evidence. hlsreport produces an official report, not a certificate.
Runtime obligations and exact executable links are in [RuntimeCoverage.md](RuntimeCoverage.md).

The suite's `passed` means its stated assertions passed. It does not mean that
all external obligations, optional clients, media formats, future standard
revisions, or every possible playlist have been verified.
