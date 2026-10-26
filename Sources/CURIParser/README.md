# uriparser

C sources and public headers from uriparser 1.0.2:
https://github.com/uriparser/uriparser/tree/9b2bed92f5deecf740819f9bf27724bee2fe9c12

License: BSD-3-Clause, reproduced in LICENSE and the source headers.
SwiftPM compiles the narrow-character C API directly. The local UriConfig.h
supplies the release version; module.modulemap exposes its headers to Swift.
No CMake or system-installed library is required.

Local change in src/UriCommon.c: preserve the leading slash left when removing
the first `a/..` from a rootless absolute reference (RFC 3986 section 5.2.4).
The encoded-path regression oracle covers this independently.

Reviewed backports (the upstream release remains 1.0.2):

| Upstream PR | Reviewed head SHA | Change |
| --- | --- | --- |
| [311](https://github.com/uriparser/uriparser/pull/311) | cd1e43defb957656bcbef0f06782d03542c60b65 | Bound URI serialization delimiter and IP address lengths |
| [312](https://github.com/uriparser/uriparser/pull/312) | 763eefd0d4254f9df9774dd11a39876213cfb4c2 | Bound query item count |
| [313](https://github.com/uriparser/uriparser/pull/313) | 4bf74cf04db45dd0c67c4b1e45843ebe06691065 | Bound query item length (CVE-2026-48841) |
| [341](https://github.com/uriparser/uriparser/pull/341) | 7118c4f5355d9919fce270d050b4b2f51b70b294 | Preserve hostless paths after normalization; ownership-safe dot insertion |
| [344](https://github.com/uriparser/uriparser/pull/344) | cfcbcfaa628e4804c5d439d7afd9c065c89ac053 | Reset borrowed ranges after parse failure |

PRs 311–313 are merged upstream but absent from 1.0.2; 341 and 344 were
open at the 2026-10-27 audit. Local extensions bound the cumulative query
length across items and apply the authority ambiguity fix to every resolution
branch. The existing RFC 3986 leading-slash correction is retained: removing
`a/..` in `scheme:a/..///foo` leaves `///foo`, serialized unambiguously as
`scheme:/.///foo`, rather than dropping a slash.
Hostless roots are canonicalized to `absolutePath` with no path segments,
matching the parser's representation of `/` so structural round trips agree.

`Verification/native_uri.py`, included in the standard suite, compiles these
sources with AddressSanitizer and UndefinedBehaviorSanitizer. It covers integer
boundaries without allocating multi-gigabyte strings, parse failure and reuse,
owned/borrowed normalization, resolution, round trips and allocation failures.

Deferred upstream proposals: empty-port normalization (342), IPv6 compression
(336), query escaping API additions (337), Windows/packaging changes, and
host UTF-8 policy (223). These do not have an established need in this integration.
The glibc compatibility fix (320) does not apply on Apple platforms; public
symbol visibility fixes (328, 330) are unnecessary for this static C target.
Issue 8's null pathHead for `http:/` is consistent with the parser's root
representation; this integration preserves that representation.
Issue 348 references a nonpublic vulnerability without reproducer or patch;
this audit cannot establish its cause or claim to fix it.
