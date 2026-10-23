# Full verification completion work

User authorization: run a local HTTP/2 origin, fill mandatory missing tests,
use the connected device, and make the work reproducible in CI. No deployment
or player business-source changes. Final evidence and scope: FULL_REPORT.md.

- [x] Official static PART original/render/rewrite all pass over actual HTTP/2;
      remove the 551002 exception, preserve official JSON/HTML and transport log.
- [x] Generate actual CMAF media with multiple short PARTs per parent and
      continuous timestamps; validate with ffprobe and Apple's tools.
- [x] Serve dynamic LL renditions and test blocking playlist reload, malformed
      and future directives, delta YES/v2, sliding sequences, preload waiting,
      rendition reports, range requests, cancellation and cleanup.
- [x] Independent assertions on input and transformed responses; validate
      timing and HTTP semantics separately from parse/render round-trip.
- [x] Use a connected iOS device for LL playback and full relevant AVPlayer
      playback/seek/pause/resume, key rotation, FairPlay, tracks and recovery.
      Public invalid playlists remain negative controls, never normalized and
      mislabeled as original sources.
- [x] Automate device provisioning/build/install/start/results/stop and remove
      temporary uploads/tunnels. Reject empty case selection/incomplete results.
- [x] CI one-command full profile requires official tools and connected device;
      missing prerequisites fail. Hosted offline profile remains distinct.
- [x] Add regression tests for findings, clause-to-test links for mandatory
      playlist behaviors and explicit out-of-library obligations.
- [x] Run final ASan, Release, independent oracles, official media/dynamic,
      platform probe and device suite on unchanged source hashes.
- [x] Archive actual evidence/report under player/verification; update docs and
      commit locally. Remove temporary TLS trust and all task-owned services.
