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
