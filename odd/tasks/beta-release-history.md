# Beta release history portal

Created: 2026-10-05. Status: IN PROGRESS.

## Goal

Expose a complete, safe-to-render history of GitHub Releases on the public Giramesa Beta portal at `https://alfonsoautomatiza.github.io/giramesa-beta/`.

## Scope

- [x] T1 — Add an accessible portal navigation target and a release-history section with loading, empty, and unavailable states.
- [x] T2 — Fetch and render paginated public GitHub releases safely, preserving plain text and safe repository-bound release links only.
- [ ] T3 — Add focused browserless tests or structural validation, verify the static portal, and commit after explicit authorization.

## Constraints

- Public data only; no tokens, cookies, analytics, or private API calls.
- Do not render GitHub release bodies as HTML.
- Bound release history pagination and tolerate GitHub rate limits/network failure.
- Keep the existing latest-release download cards working.

## Progress

- Source lives on the `portal` branch of `alfonsoautomatiza/giramesa-beta`, under `docs/`.
- Existing portal reads the latest release from the public GitHub API in `docs/app.js`; the new history will extend that safely rather than duplicate release configuration.
- 2026-10-05: T1/T2 implemented in `docs/` (nav link `#historial`, section with loading/empty/unavailable/rate-limit states; up to 4 pages x 30 releases, 100 shown, dedup by id, drafts excluded, plain-text rendering, links bound to `/<repo>/releases/tag/`). Verified with an ad-hoc browserless Node/vm check (not committed). T3 remains open: no persistent test file was in scope, and no commit has been made.
- 2026-10-05: Verifier follow-ups fixed in `docs/app.js`: `safeReleasePageUrl` now rejects any explicit port; a 403/429 after at least one collected page keeps and renders the collected releases with a `partial` rate-limit status, while a first-page 403/429 still uses the unavailable/rate-limit state. Verified RED then GREEN with an ephemeral Node/vm harness (not committed). T3 remains open: no persistent test file and no commit yet.
