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
- **[RELEASE_NOTES_BUILD_8.md](RELEASE_NOTES_BUILD_8.md)** — TestFlight release notes for build 8.
- **[archive/](archive/)** — superseded planning documents, each carrying an archive banner.
  Historical record; they do not describe the app as it stands.

The current development guide is [../claude.md](../claude.md) in the repo root.

---

## Repo-agnostic meta-tooling

These three are not about GFPriceChecker. They describe how to write and maintain a CLAUDE.md in
*any* repo, and they are parked here only because this is where they were first written:

- **[CLAUDE_MD_TEMPLATE.md](CLAUDE_MD_TEMPLATE.md)** — standard structure for a CLAUDE.md
- **[CLAUDE_MD_CHECKLIST.md](CLAUDE_MD_CHECKLIST.md)** — maintenance checklist
- **[check-claude-md.sh](check-claude-md.sh)** — health check script

```bash
# Run from repo root
./docs/check-claude-md.sh
```

**They are slated to move to a shared documentation home** so that a second, third and fourth repo
reference one copy instead of each carrying its own drifting fork — see issue #47. Until that home
exists, treat the copies here as the source and resist duplicating them into other repos.

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
