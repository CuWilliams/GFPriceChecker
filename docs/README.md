# Documentation Guide

This folder contains templates and tools for maintaining optimal CLAUDE.md files across all repositories.

---

## Files in This Directory

### 📚 Documentation Archives
- **[DEVELOPMENT_HISTORY.md](DEVELOPMENT_HISTORY.md)** - Complete session-by-session implementation log (Sessions 1-27) for GFPriceChecker

### 📋 Templates & Guides
- **[CLAUDE_MD_TEMPLATE.md](CLAUDE_MD_TEMPLATE.md)** - Standard structure and best practices for CLAUDE.md files
- **[CLAUDE_MD_CHECKLIST.md](CLAUDE_MD_CHECKLIST.md)** - Maintenance checklist for keeping CLAUDE.md healthy

### 🔧 Tools
- **[check-claude-md.sh](check-claude-md.sh)** - Automated health check script for CLAUDE.md

---

## Quick Start

### For New Projects

1. Copy `CLAUDE_MD_TEMPLATE.md` to your new repo root and rename to `CLAUDE.md`
2. Fill in project-specific sections (see template comments)
3. Create a `docs/` folder
4. Start `docs/DEVELOPMENT_HISTORY.md` for detailed session logs
5. Copy `check-claude-md.sh` to `docs/` and run periodically

### For Existing Projects

1. Run health check:
   ```bash
   ./docs/check-claude-md.sh
   ```

2. If score < 80%, refactor:
   - Review [CLAUDE_MD_TEMPLATE.md](CLAUDE_MD_TEMPLATE.md)
   - Use [CLAUDE_MD_CHECKLIST.md](CLAUDE_MD_CHECKLIST.md)
   - Archive session logs to `docs/DEVELOPMENT_HISTORY.md`

3. After refactoring, verify:
   ```bash
   ./docs/check-claude-md.sh
   ```

---

## Maintenance Schedule

### ✅ After Every Major Feature
- [ ] Extract pattern if solution is reusable
- [ ] Update "Key Features" section
- [ ] Archive session log to DEVELOPMENT_HISTORY.md
- [ ] Run `./docs/check-claude-md.sh`

### 📅 Monthly (for Active Projects)
- [ ] Review [CLAUDE_MD_CHECKLIST.md](CLAUDE_MD_CHECKLIST.md)
- [ ] Archive old session logs
- [ ] Update "Current Status" section
- [ ] Verify code examples still compile

### 🎯 Before Major Milestones
- [ ] Complete documentation audit
- [ ] Ensure all patterns documented
- [ ] Create DEVELOPMENT_HISTORY.md snapshot
- [ ] Run `./docs/check-claude-md.sh`

---

## The Golden Rules

1. **Size matters**: Keep CLAUDE.md under 500 lines
2. **Focus on patterns**: Not step-by-step history
3. **Archive religiously**: Move detailed logs to docs/ folder
4. **Update after features**: Keep current, not historical
5. **Think onboarding**: "If I joined today, what do I need?"
6. **Code examples over paragraphs**: Show, don't tell
7. **Review monthly**: Documentation rots fast

---

## Health Check Script Usage

```bash
# Make executable (first time only)
chmod +x docs/check-claude-md.sh

# Run from repo root
./docs/check-claude-md.sh
```

**Output:**
- ✓ Green = Healthy
- ⚠ Yellow = Needs attention
- ✗ Red = Immediate action required

**Score:**
- 80%+ = Healthy
- 50-79% = Needs attention
- <50% = Refactor now

---

## What Goes Where?

### CLAUDE.md (Main Guide)
- ✅ Project overview and tech stack
- ✅ Established patterns (3-6 max)
- ✅ Development guidelines
- ✅ Feature summary
- ✅ Known limitations

### docs/DEVELOPMENT_HISTORY.md
- ✅ Session-by-session logs
- ✅ Technical decisions
- ✅ Implementation details
- ✅ Commit hashes
- ✅ Debugging sessions

### docs/ARCHITECTURE.md (Optional)
- ✅ Detailed system design
- ✅ Database schema
- ✅ API documentation
- ✅ Data flow diagrams

### docs/SETUP.md (Optional)
- ✅ Installation instructions
- ✅ Environment setup
- ✅ Troubleshooting

---

## Copy These Files to Other Repos

To replicate this setup in another project:

```bash
# From GFPriceChecker repo
cp docs/CLAUDE_MD_TEMPLATE.md /path/to/other/repo/CLAUDE.md
cp docs/CLAUDE_MD_CHECKLIST.md /path/to/other/repo/docs/
cp docs/check-claude-md.sh /path/to/other/repo/docs/
chmod +x /path/to/other/repo/docs/check-claude-md.sh
```

Then customize CLAUDE.md for the new project.

---

## Questions?

Refer to:
- **Structure questions**: [CLAUDE_MD_TEMPLATE.md](CLAUDE_MD_TEMPLATE.md)
- **Maintenance questions**: [CLAUDE_MD_CHECKLIST.md](CLAUDE_MD_CHECKLIST.md)
- **Example**: [../CLAUDE.md](../CLAUDE.md) (this repo)

---

*These templates are based on the GFPriceChecker documentation refactoring (January 2025)*
