# Documentation Guide

What lives in this folder, and where each thing's boundary is.

---

## GFPriceChecker documentation

- **[DEVELOPMENT_HISTORY.md](DEVELOPMENT_HISTORY.md)** — session-by-session implementation log.
  **Covers Sessions 1-27 only, December 2025 through January 2026.** Work after January 2026 is
  not in it; that record lives in the git log, in pull requests, and in GitHub Issues.
- **[SCRIPTED_DEMO_PIPELINE.md](SCRIPTED_DEMO_PIPELINE.md)** — the plan and feasibility audit for
  generating the website's instructional videos from scripts the app plays against itself. Read it
  before touching the capture flows, `DocumentScannerView`, or navigation structure.
- **[SHARED_CORE.md](SHARED_CORE.md)** — the plan and audit for moving the domain logic into
  the Foundation-only `GFCore` package, for sharing with a future Android app (Track F). Read it
  before touching `ProductPair`'s arithmetic, reporting, exports, receipt parsing or validation.
- **`RELEASE_NOTES_BUILD_<n>.md`** — TestFlight release notes, one file per uploaded build,
  written for testers and pasted into TestFlight at upload. Currently
  [8](RELEASE_NOTES_BUILD_8.md), [9](RELEASE_NOTES_BUILD_9.md) and
  [10](RELEASE_NOTES_BUILD_10.md). The repo-facing counterpart is
  [../CHANGELOG.md](../CHANGELOG.md); neither replaces the other.
- **[archive/](archive/)** — superseded planning documents, each carrying an archive banner.
  Historical record; they do not describe the app as it stands.

The current development guide is [../claude.md](../claude.md) in the repo root.

---

## Moved out: CLAUDE.md meta-tooling

`CLAUDE_MD_TEMPLATE.md`, `CLAUDE_MD_CHECKLIST.md` and `check-claude-md.sh` used to live here.
They were never about GFPriceChecker — they describe how to write and maintain a CLAUDE.md in
*any* repo, and eleven repos need them.

**They now live in [CuWilliams/shared-docs](https://github.com/CuWilliams/shared-docs), under
`meta/`.** Link to them; do not copy them back.

```bash
# Health-check this repo's claude.md, from the repo root:
/path/to/shared-docs/meta/check-claude-md.sh
```

It finds the guide file whatever its casing, so it works on this repo's lowercase `claude.md`.

The same repo also holds the GFPriceChecker documentation shared with the website and any future
Android app, under `gfpricechecker/` — see **Content Conventions** in [../claude.md](../claude.md).

---

## What goes where

### claude.md (repo root)
- Project overview and tech stack
- Established patterns
- Development guidelines and content conventions
- Feature summary
- Known limitations

### docs/DEVELOPMENT_HISTORY.md
- Session-by-session logs, technical decisions, implementation details, commit hashes

### docs/archive/
- Planning documents that have been overtaken. Add the archive banner when you move one here;
  `archive/EXECUTION_PLAN.md` is the model.

---

## The golden rules

1. **Size matters**: keep claude.md focused; archive detail to `docs/`
2. **Focus on patterns**, not step-by-step history
3. **Update after features**: keep it current, not historical
4. **Think onboarding**: "if I joined today, what do I need?"
5. **Code examples over paragraphs**: show, don't tell
6. **Never let a document look more current than it is** — a partial record that reads as complete
   is worse than one that states where it stops
