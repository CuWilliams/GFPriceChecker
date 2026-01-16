# CLAUDE.md Template & Maintenance Guide

## Purpose
This template provides a standard structure for CLAUDE.md files across all projects to ensure they remain lean, actionable, and token-efficient for Claude Code sessions.

---

## Optimal Size: 200-500 lines

**Warning Signs You Need to Refactor:**
- File exceeds 800 lines
- More than 50% of content is historical logs
- Detailed implementation steps instead of patterns
- Hard to find current guidelines when scrolling

---

## Standard CLAUDE.md Structure

```markdown
# [Project Name] - Development Guide

**[One-sentence project description]**

---

## Project Overview

[2-3 paragraphs describing:]
- What the project does
- Who it's for
- Key features/value proposition

**Current Status:** [e.g., "Production-ready MVP" / "Active development" / "Prototype"]

---

## Tech Stack

- **Language:** [e.g., Swift 6.0]
- **Framework:** [e.g., SwiftUI]
- **Platform:** [e.g., iOS 26.0+]
- **Database:** [e.g., SwiftData / PostgreSQL / MongoDB]
- **Key Dependencies:** [List critical dependencies]
- **Architecture:** [e.g., MVVM / MVC / Clean Architecture]

---

## Project Structure

```
[ProjectName]/
├── [folder]/           # Description
├── [folder]/           # Description
└── [folder]/           # Description
```

[Brief description of key architectural decisions]

---

## Core Concepts

### [Concept 1: e.g., Data Models]
**File:** `path/to/file.ext`

[Brief explanation of key design decisions]

**Key Properties/Methods:**
- Property 1: Purpose
- Property 2: Purpose

### [Concept 2: e.g., Business Logic]
[Same structure]

---

## Established Patterns & Best Practices

### 1. [Pattern Name - e.g., "Error Handling"]

**Problem:** [What problem this solves]

**Solution:**
```[language]
// Code example showing the pattern
```

**When to Use:**
- Scenario 1
- Scenario 2

**Examples in Codebase:**
- `path/to/file.ext`
- `path/to/another/file.ext`

**Rule:** [One-sentence guideline]

---

[Repeat for each established pattern - aim for 3-6 patterns max]

---

## Key Features

### ✅ Implemented

**[Feature Category 1]**
- Feature A
- Feature B

**[Feature Category 2]**
- Feature C
- Feature D

---

### ⏸️ Deferred / Planned

**[Deferred Feature]**
- Brief explanation of what and why deferred
- Planned for: [e.g., "Post-MVP" / "Q2 2025"]

---

## Development Guidelines

### [Technology/Framework] Best Practices
- Guideline 1
- Guideline 2
- Guideline 3

### Code Quality Standards
- Standard 1
- Standard 2

### Testing Strategy
- How to test
- What to test

---

## Known Limitations

1. **[Limitation Category]:**
   - Specific limitation
   - Why it exists
   - Workaround (if applicable)

2. **[Another Category]:**
   - ...

---

## Git Workflow

**Main Branch:** `main`
**Feature Branches:** `[your-pattern]`

**Commit Message Style:**
- [Your style preference]

**Pull Request Workflow:**
1. Step 1
2. Step 2
3. Step 3

---

## Reference Documentation

**Detailed Implementation History:** See `docs/DEVELOPMENT_HISTORY.md`

**Other Resources:**
- Link to external docs
- Link to design docs

---

*This documentation is maintained by Claude Code to guide ongoing development and session work.*
```

---

## What to Include ✅

### Essential (Always Include)
1. **Project overview** - What, why, who
2. **Current tech stack** - Versions matter!
3. **Project structure** - Folder organization with descriptions
4. **Core data models** - Key entities and relationships
5. **Established patterns** (3-6 max) - Reusable solutions with code examples
6. **Key features summary** - What's done vs. what's planned
7. **Development guidelines** - Framework-specific best practices
8. **Known limitations** - Honest assessment of constraints
9. **Git workflow** - Your branching/commit strategy

### Helpful (Include If Applicable)
- Common commands/scripts
- Environment setup requirements
- Deployment process
- Testing approach
- API endpoints/routes
- Database schema overview

---

## What to Archive 🗄️

### Move to docs/DEVELOPMENT_HISTORY.md
- Session-by-session implementation logs
- Detailed technical decisions for each feature
- Step-by-step task completion logs
- Commit hashes and line counts
- Debugging sessions and issue resolutions
- User modification notes
- "How we built X" narratives

### Move to docs/ARCHITECTURE.md
- Detailed system design diagrams
- Database schema with all tables/columns
- API documentation
- Data flow diagrams

### Move to docs/SETUP.md
- Detailed installation instructions
- Environment configuration steps
- Dependency installation guides
- Troubleshooting common setup issues

---

## Maintenance Schedule

### After Every Major Feature (Recommended)
Run this checklist:

- [ ] Is CLAUDE.md > 800 lines?
- [ ] Are there session logs in CLAUDE.md?
- [ ] Are established patterns still accurate?
- [ ] Are deferred features still deferred?
- [ ] Do code examples still compile?
- [ ] Are new patterns documented?

### Monthly Review (For Active Projects)
- Archive old session logs to DEVELOPMENT_HISTORY.md
- Update "Current Status" section
- Review and update "Known Limitations"
- Ensure tech stack versions are current
- Check that examples match current codebase

### Before Major Milestones (v1.0, Production Launch, etc.)
- Complete documentation audit
- Ensure all patterns are documented
- Update feature lists (✅ vs. ⏸️)
- Create comprehensive DEVELOPMENT_HISTORY.md snapshot

---

## Quick Refactor Process

When your CLAUDE.md exceeds 800 lines:

### Step 1: Identify Content to Archive
```bash
# Count lines in CLAUDE.md
wc -l CLAUDE.md

# Look for session logs (usually start with "## Session N:")
grep "^## Session" CLAUDE.md

# Look for detailed step-by-step logs
grep -n "### Tasks Completed" CLAUDE.md
grep -n "### Implementation Details" CLAUDE.md
```

### Step 2: Create Archive File
```bash
mkdir -p docs
# Move session logs to archive
```

### Step 3: Extract Patterns
From detailed logs, extract:
- Recurring solutions → Patterns section
- Important decisions → Development Guidelines
- Code snippets that worked → Pattern examples

### Step 4: Rewrite CLAUDE.md
Use this template, focusing on:
- Current state (not history)
- Reusable patterns (not one-time solutions)
- Guidelines (not step-by-step logs)

### Step 5: Update Cross-References
Ensure CLAUDE.md links to archived docs:
```markdown
**Detailed Implementation History:** See `docs/DEVELOPMENT_HISTORY.md`
**Architecture Details:** See `docs/ARCHITECTURE.md`
```

---

## Tools to Help

### VS Code Extension: Word Count
Install to monitor CLAUDE.md size in real-time.

### Git Hook: Pre-commit Check
Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
if [ -f CLAUDE.md ]; then
    lines=$(wc -l < CLAUDE.md)
    if [ $lines -gt 800 ]; then
        echo "⚠️  WARNING: CLAUDE.md is $lines lines (recommended: <500)"
        echo "Consider refactoring to archive detailed logs."
    fi
fi
```

### Alias for Quick Check
Add to your `.zshrc` or `.bashrc`:
```bash
alias claude-size='wc -l CLAUDE.md && echo "Recommended: <500 lines"'
alias claude-patterns='grep -n "^### [0-9]" CLAUDE.md'
```

---

## Template Variations by Project Type

### iOS/Mobile App
Focus on:
- SwiftUI/UIKit patterns
- iOS version targeting
- App Store compliance notes
- Platform-specific limitations

### Backend API
Focus on:
- API endpoint structure
- Database schema overview
- Authentication patterns
- Deployment configuration

### Full-Stack Web App
Focus on:
- Frontend framework patterns
- Backend framework patterns
- API contract
- Database models

### Library/Package
Focus on:
- Public API surface
- Usage examples
- Installation instructions
- Breaking changes (if applicable)

---

## Red Flags: Time to Refactor

🚩 **File exceeds 1000 lines**
🚩 **Contains phrases like "Session 1", "Session 2"...**
🚩 **Has commit hashes sprinkled throughout**
🚩 **More than 10 "Implementation Details" sections**
🚩 **Contains debugging logs ("Fixed bug X", "Tried Y, didn't work")**
🚩 **Takes more than 30 seconds to scroll through**
🚩 **Hard to find current guidelines**

---

## Example: Good vs. Bad Content

### ❌ Bad (Archive This)
```markdown
## Session 15: Add User Authentication

**Date:** January 1, 2025
**Branch:** `feature/auth-XYZ123`

### Tasks Completed
- [x] Created AuthService.swift
- [x] Added login form
- [x] Integrated with Firebase
- [x] Tested on device
- [x] Fixed bug with password validation

### Implementation Details
First I tried using JWT but it didn't work with our setup.
Then I switched to Firebase Auth. Created the service file
at Services/AuthService.swift with 342 lines...

[Continues for 200 lines...]
```

### ✅ Good (Keep This)
```markdown
### 3. Authentication Pattern

**File:** `Services/AuthService.swift`

We use Firebase Authentication with email/password sign-in.

**Pattern:**
```swift
class AuthService {
    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }
}
```

**When to Use:**
- User sign-in/sign-up flows
- Protected routes requiring authentication

**Rule:** Always validate email format client-side before calling signIn().
```

---

## Summary: The Golden Rules

1. **Size matters**: Keep CLAUDE.md under 500 lines
2. **Focus on patterns**: Not step-by-step history
3. **Archive religiously**: Move detailed logs to docs/ folder
4. **Update after features**: Keep current, not historical
5. **Think: "If I joined today, what do I need?"**: Not "How did we build this?"
6. **Code examples over paragraphs**: Show, don't tell
7. **Review monthly**: Documentation rots fast
8. **Link to archives**: Make history accessible, not inline

---

*This template is based on the GFPriceChecker refactoring (Dec 2024 - Jan 2025)*
