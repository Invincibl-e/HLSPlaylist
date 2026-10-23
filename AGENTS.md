# HLSPlaylist verification

Read `Verification/TESTING.md` before changing or running tests. It is the shared
maintainer/AI procedure and states the official-tool/device prerequisites,
certificate setup, required evidence, cleanup, and compliance boundaries.

- Use `Verification/suite.py` for recorded runs; full requires `--profile full`.
- Never run certificate `install`/`remove` during routine testing. Reuse the
  pre-provisioned localhost identity and fail if its read-only check fails.
- Do not weaken parser checks, omit cases, disable TLS validation, or count
  arbitrary network failures as expected strict rejections to obtain a pass.
- Keep old failed evidence; report the tested revision and actual scope.
- Passing tests is not proof of 100% HLS/LL-HLS compliance or Apple certification.
- Follow `MAINTENANCE.md`; do not sync implementation with upstream by default.
