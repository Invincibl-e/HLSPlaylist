# Playback compatibility — 2026-10-25

This follow-up closes the 14 public-manifest rejections recorded in the title
compatibility audit: 13 Apple WebVTT playlists exceed their declared target
duration, and one castLabs master references an undeclared AUDIO group.
Gcore's archived live playlists also place PDT after the first PART.

Preserve the actual duration and target, preserve unresolved AUDIO references
without inventing tracks, and associate late PDT with its parent segment.
All 193 pinned public manifests must parse, render, rewrite and restore their
semantics. All five archived Gcore child playlists join the acceptance floor.
The 22 device scenarios now all require playback; parser/network failures do
not satisfy any of those scenarios.

Informative EXTINF title compatibility remains unchanged: non-NUL controls and
non-NFC text are retained; title CR/LF and NUL remain invalid. This is an
AVPlayer compatibility contract, not a claim that these inputs meet every
authoring requirement.

Full run identity: `suite-20261024T200655.268802Z`.
All 17 full-profile steps passed. Swift ASan/Release each passed 85 tests;
248 fixed oracles, 928 generated combinations, 193 public manifests and
2,000 generated VODs passed. Mac, iOS simulator and iOS 15.5 device each passed
2,058 independent URI cases. All 3,840 extended device results exactly matched
Mac, including negative inputs.

Apple static checks passed 15 positive and 3 HTTP/2 PART cases. Dynamic HTTP/2
passed 78 assertions; original/render/rewrite Apple LL checks exited zero with
SHOULD diagnostic 242528 retained. All 22 AVPlayer device scenarios passed,
including Gcore rewrite, original/rewritten FairPlay, track switching and
recovery. DRMtoday rewrite retained all 181 source TAB bytes. Device cleanup
reported no errors; temporary device trust was removed.

The run recorded 333 source/test/corpus hashes, all matching the final tree.
The evidence finalization file maps these hashes to the final library commit.
Evidence is retained in the sibling player repository under
`verification/hlsplaylist-compatibility-20261025/`, including prior failures.
