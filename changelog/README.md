# Release notes, authored here and published at release

One file per release: `ios-<version>.json`. The file is written
alongside the code that changed, so it lands in the same PR and gets reviewed
with it. It is **published separately**, when the version actually reaches users — the
publishing script lives in `WellSpent-backend`:

```bash
../WellSpent-backend/scripts/changelog.sh publish changelog/ios-1.36.0.json
```

Authoring and publishing are deliberately separate steps. At the moment a
feature is written nothing is released yet — the PR is still open — so
publishing then would show readers notes for a build they do not have, and
there is no undo: rows are never deleted.

The database is the source of truth for everything clients display. These files
are only the authoring format, the same way a migration is written in the repo
and applied separately.

## Format

```json
{
  "component": "ios",
  "version": "1.36.0",
  "releasedAt": "2026-08-25T12:00:00Z",
  "items": [
    { "changeType": "added", "summaryEn": "…", "summaryEs": "…" },
    { "changeType": "fixed", "summaryEn": "…" }
  ]
}
```

- `component` — `ios` here; `web` and `server` live in their own repos
- `version` — must match `MARKETING_VERSION`, **not** the build number. A
  changelog entry describes a release a reader was given; the build number moves
  every feature while the marketing version deliberately does not, so notes
  accumulate into the next marketing version you cut
- `releasedAt` — optional, defaults to now
- `changeType` — `added`, `fixed` or `changed`
- `summaryEs` — optional; Spanish readers fall back to the English text
- Write for a **user**, not a reviewer: what they can now do, not which
  view model changed

## When MARKETING_VERSION is frozen

This repo deliberately leaves `MARKETING_VERSION` alone for long stretches (see
`CLAUDE.md`), so several features can land before there is a version to attach
notes to. Keep adding items to the file named for the version you intend to
cut next, and rename it if that changes. Publishing happens once, when that
version actually goes to TestFlight.

A version can only be published once — `(component, version)` is unique, so a
second attempt fails loudly rather than listing the release twice.

See `docs/features/changelog.md` in the workspace root for the full spec.
