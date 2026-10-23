# Runtime requirements and executable evidence

This complements the paragraph inventory and fixed syntax oracles. Rows name
the behavior actually asserted; they do not turn an entire section into a
certification claim. The baseline is bis-22, not a future draft.

| Requirement | Independent assertion or real execution |
|---|---|
| §3 continuous encoded timestamps | `cmaf.prepare`: all 600 `tfdt` values equal `index * 7680`; ffprobe packet counts and keyframe flags |
| §3.2 independent PARTs and parent media identity | CMAF four-part concatenation; ffprobe 15-frame GOP; official validator consumes actual samples |
| §4.4.3.2 / §6.2.2 media sequence slides without changing resource identity | `ll_validate.assertions`: exact eight expected parent URIs; later sequence advances |
| §4.4.3.7–8 PART target and hold-back | Fixed standards oracles; actual 0.5s PARTs, 1.5s PART hold-back, 6s parent hold-back |
| §4.4.5.1 retain ranges while mapped | Dynamic full playlists retain the range ending at the leading PDT; Apple cross-refresh validation |
| §4.4.5.2 removed IDs may be empty | `StandardsTests.deltaRemovedDateRanges`, `delta-v2-empty` oracle; parse and render preserve empty field |
| §4.4.5.2 TAB separates removed IDs | Same Swift test, `delta-v2-tab-delimited` oracle; exact ID list in dynamic v2 responses |
| §4.1 TAB exception must remain scoped | `deltaTabExceptionIsScoped`, `delta-v2-tab-outside-field`: other attributes/control bytes still rejected |
| §4.4.5.3 / §6.2.6 hint is available to request before publication | Preload HTTP request blocks and returns bytes identical to generated part; no premature partial response |
| §4.4.5.4 report describes another rendition | Exact relative rendition path and counters; two variants consumed by Apple's validator |
| §6.2.5.1 delta YES keeps date ranges | Exactly six retained parents but all nine active/leading date ranges |
| §6.2.5.1 delta v2 reports recently removed IDs | Exact expected IDs derived independently from sequence/window age; real AVPlayer v2 reloads |
| §6.2.5.2 MSN+PART blocking | Future PART request measurably waits and contains requested part |
| §6.2.5.2 MSN-only blocking | Response contains completed requested parent |
| §6.2.5.2 beyond-final PART rolls over | Request for part index 4 returns next parent's part index 0 |
| §6.2.5.2 old MSN returns whole playlist | Immediate successful reload, with full sliding window |
| §6.2.5.2 PART without MSN is 400 | Real HTTP/2 400 response, all three modes |
| §6.2.5.2 unreasonable future directives | Real HTTP/2 400 response; advance PART limit is 3 / 0.5 = 6 |
| §6.2.5.2 source blocked beyond three targets | Freeze source publication and require 503 after six seconds |
| LL HTTP/2 transport | curl negotiates protocol 2; Apple mandatory findings gate exit; AVPlayer request log requires HTTP/2 and delivery directives |
| HTTP byte ranges | Exact bytes and 206; out-of-bounds 416; separate real range playback and seek |
| Cancellation and shutdown | Cancel active future PART request; unrelated request still succeeds; origin stop event releases outstanding waits |
| AES key/IV rotation | Independently generated encrypted fixtures; device must play/seek and fetch at least two distinct key URIs |
| FairPlay decryption | Public original stream obtains certificate/license, renders and advances; invalid original text remains rejected on strict path |
| Rendition media selection | Real device chooses two audio and two subtitle options, verifies selection and continued progression |
| Recovery | One controlled 503 must occur and AVPlayer must subsequently render, advance and seek |
| Platform parity | Same library/Probe sources run on iOS and macOS; all ordered output objects must match |
| Fail-closed runner | Process crashes/count mismatch/empty or missing cases/wrong device/incomplete playback fail the run |
| Temporary trust lifecycle | `DeviceTrust.m`: add one scoped certificate, verify localhost trust, remove exact certificate, verify no remaining trust |

Apple `must_auth` exit gating includes mandatory authoring findings; it does
not discard level 6. SHOULD/advisory messages remain in reports. An iOS ECN
recommendation on the SSH loopback transport is not relabeled as an HTTP/2
failure or suppressed. iOS 15.5's observed empty-v2-list playback issue is
preserved in failed attempt evidence; the library follows the standard's
explicit permission for empty strings. A generated stream with actual rolling
date ranges exercises successful v2 playback without weakening that rule.

Out-of-library requirements remain explicit: media formats/codecs absent from
these fixtures, steering-server JSON/scheduling, SCTE-35 payload semantics,
optional extension player behavior, and untested OS/decoder implementations.
No finite suite proves every possible stream or grants an Apple certificate.
