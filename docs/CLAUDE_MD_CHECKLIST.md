# CLAUDE.md Maintenance Checklist

Use this checklist after completing major features or monthly for active projects.

---

## Quick Health Check (2 minutes)

- [ ] **Line count** < 500 lines (run: `wc -l CLAUDE.md`)
- [ ] **No session logs** in main file (search for "## Session")
- [ ] **No commit hashes** sprinkled throughout (search for SHA patterns)
- [ ] **Current status** section is up-to-date
- [ ] **Tech stack versions** are current (Swift, iOS, dependencies)

**If any boxes unchecked:** Schedule refactor session

---

## Monthly Review (15 minutes)

### Content Audit
- [ ] All **Established Patterns** still accurate and compile
- [ ] **Key Features** section matches actual codebase state
- [ ] **Known Limitations** section is current
- [ ] **Deferred Features** list is still relevant
- [ ] No more than **6 patterns** documented (consolidate if needed)

### Housekeeping
- [ ] Move any session logs to `docs/DEVELOPMENT_HISTORY.md`
- [ ] Move any detailed architecture to `docs/ARCHITECTURE.md`
- [ ] Update "Reference Documentation" links
- [ ] Verify code examples still work (copy-paste test)

### Quality Check
- [ ] Someone new could understand project in 10 minutes
- [ ] Guidelines are actionable (not descriptive history)
- [ ] Examples show best practices (not legacy approaches)

---

## Refactor Decision Tree

**Is CLAUDE.md > 800 lines?**
- YES → **Refactor now** (see CLAUDE_MD_TEMPLATE.md)
- NO → Continue below

**Does it contain session-by-session logs?**
- YES → **Archive to DEVELOPMENT_HISTORY.md**
- NO → Continue below

**Are there > 10 "Implementation Details" sections?**
- YES → **Extract patterns, archive details**
- NO → You're good! ✅

---

## New Project Setup (Use Template)

When starting a new repo:

1. [ ] Copy `docs/CLAUDE_MD_TEMPLATE.md` to new repo
2. [ ] Rename to `CLAUDE.md`
3. [ ] Fill in project-specific sections:
   - Project name and description
   - Tech stack
   - Project structure
   - Initial core concepts
4. [ ] Create `docs/` folder
5. [ ] Start `docs/DEVELOPMENT_HISTORY.md` with Session 1
6. [ ] Add template reminder to repo README:
   ```markdown
   ## Documentation
   - See [CLAUDE.md](CLAUDE.md) for development guide
   - See [docs/DEVELOPMENT_HISTORY.md](docs/DEVELOPMENT_HISTORY.md) for detailed session history
   ```

---

## After Major Feature Implementation

- [ ] **Extract pattern** if solution is reusable
- [ ] **Update "Key Features"** section (move from ⏸️ to ✅)
- [ ] **Add to guidelines** if there's a new best practice
- [ ] **Document limitation** if you discovered a constraint
- [ ] **Archive session log** to DEVELOPMENT_HISTORY.md
- [ ] **Check line count** (should stay under 500)

---

## Before Git Push (Optional)

Quick validation:

```bash
# Check size
wc -l CLAUDE.md

# Look for common problems
grep -i "session [0-9]" CLAUDE.md
grep -E "[a-f0-9]{7,40}" CLAUDE.md | head -5  # Commit hashes
grep -i "tasks completed" CLAUDE.md

# If any hits, consider refactoring before pushing
```

---

## Emergency Refactor (When CLAUDE.md > 1000 lines)

### Step 1: Backup (1 minute)
```bash
cp CLAUDE.md CLAUDE.md.backup
```

### Step 2: Extract Sessions (5 minutes)
1. Find all `## Session N:` sections
2. Cut and paste to `docs/DEVELOPMENT_HISTORY.md`
3. Organize by phase/milestone

### Step 3: Extract Patterns (10 minutes)
1. Find recurring code solutions
2. Create pattern template for each
3. Include: Problem, Solution (code), When to Use, Rule

### Step 4: Rewrite Core Sections (15 minutes)
Using template, focus on:
- Current state (not how you got here)
- Reusable patterns (not one-time fixes)
- Guidelines (not historical logs)

### Step 5: Verify (5 minutes)
- [ ] Line count < 500
- [ ] All patterns have code examples
- [ ] Cross-references to archived docs work
- [ ] Current Status section accurate

**Total time:** ~35 minutes

---

## Red Flags 🚩

Immediate refactor needed if you see:

- 🚩 File > 1000 lines
- 🚩 Phrases "Session 1", "Session 2", "Session 3"...
- 🚩 Commit hashes in documentation
- 🚩 "Implementation Details" every 50 lines
- 🚩 More than 10 patterns documented
- 🚩 "Fixed bug X" debugging logs
- 🚩 Takes > 30 seconds to scroll through
- 🚩 Can't find guidelines without searching

---

## Success Metrics ✅

Your CLAUDE.md is healthy if:

- ✅ 200-500 lines total
- ✅ Can read cover-to-cover in 10 minutes
- ✅ 3-6 well-documented patterns
- ✅ Code examples for all patterns
- ✅ New team member could onboard from it
- ✅ Guidelines are actionable
- ✅ No historical narratives
- ✅ Links to detailed history archive

---

*Based on GFPriceChecker refactoring best practices (2024-2025)*
