#!/bin/bash

# CLAUDE.md Health Check Script
# Usage: ./docs/check-claude-md.sh

set -e

CLAUDE_FILE="CLAUDE.md"
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "${BLUE}═══════════════════════════════════════${NC}"
echo "${BLUE}   CLAUDE.md Health Check${NC}"
echo "${BLUE}═══════════════════════════════════════${NC}"
echo ""

# Check if CLAUDE.md exists
if [ ! -f "$CLAUDE_FILE" ]; then
    echo "${RED}✗ CLAUDE.md not found in current directory${NC}"
    exit 1
fi

# Initialize score
total_checks=0
passed_checks=0

# Check 1: Line count
echo "${BLUE}1. Checking line count...${NC}"
total_checks=$((total_checks + 1))
line_count=$(wc -l < "$CLAUDE_FILE")
echo "   Lines: $line_count"

if [ "$line_count" -lt 500 ]; then
    echo "   ${GREEN}✓ Excellent! Under 500 lines${NC}"
    passed_checks=$((passed_checks + 1))
elif [ "$line_count" -lt 800 ]; then
    echo "   ${YELLOW}⚠ Warning: $line_count lines (recommended: <500)${NC}"
    echo "   ${YELLOW}  Consider refactoring soon${NC}"
else
    echo "   ${RED}✗ Critical: $line_count lines (recommended: <500)${NC}"
    echo "   ${RED}  Refactor recommended${NC}"
fi

echo ""

# Check 2: Session logs
echo "${BLUE}2. Checking for session logs...${NC}"
total_checks=$((total_checks + 1))
session_count=$(grep -c "^## Session" "$CLAUDE_FILE" || true)

if [ "$session_count" -eq 0 ]; then
    echo "   ${GREEN}✓ No session logs found${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo "   ${RED}✗ Found $session_count session log(s)${NC}"
    echo "   ${YELLOW}  Move to docs/DEVELOPMENT_HISTORY.md${NC}"
    echo ""
    echo "   Sessions found:"
    grep "^## Session" "$CLAUDE_FILE" | head -5
    if [ "$session_count" -gt 5 ]; then
        echo "   ... and $((session_count - 5)) more"
    fi
fi

echo ""

# Check 3: Commit hashes
echo "${BLUE}3. Checking for commit hashes...${NC}"
total_checks=$((total_checks + 1))
hash_count=$(grep -E -c "[a-f0-9]{7,40}" "$CLAUDE_FILE" || true)

if [ "$hash_count" -eq 0 ]; then
    echo "   ${GREEN}✓ No commit hashes found${NC}"
    passed_checks=$((passed_checks + 1))
elif [ "$hash_count" -lt 5 ]; then
    echo "   ${YELLOW}⚠ Found $hash_count potential commit hash(es)${NC}"
    echo "   ${YELLOW}  Consider moving to DEVELOPMENT_HISTORY.md${NC}"
else
    echo "   ${RED}✗ Found $hash_count potential commit hashes${NC}"
    echo "   ${RED}  Move detailed logs to DEVELOPMENT_HISTORY.md${NC}"
fi

echo ""

# Check 4: Implementation Details sections
echo "${BLUE}4. Checking for detailed logs...${NC}"
total_checks=$((total_checks + 1))
detail_count=$(grep -c "### Implementation Details" "$CLAUDE_FILE" || true)

if [ "$detail_count" -eq 0 ]; then
    echo "   ${GREEN}✓ No detailed implementation logs${NC}"
    passed_checks=$((passed_checks + 1))
elif [ "$detail_count" -lt 3 ]; then
    echo "   ${YELLOW}⚠ Found $detail_count 'Implementation Details' section(s)${NC}"
    echo "   ${YELLOW}  Monitor and consider archiving${NC}"
else
    echo "   ${RED}✗ Found $detail_count 'Implementation Details' sections${NC}"
    echo "   ${RED}  Archive detailed logs to DEVELOPMENT_HISTORY.md${NC}"
fi

echo ""

# Check 5: Pattern count
echo "${BLUE}5. Checking pattern documentation...${NC}"
total_checks=$((total_checks + 1))
pattern_count=$(grep -c "^### [0-9]" "$CLAUDE_FILE" || true)
echo "   Patterns documented: $pattern_count"

if [ "$pattern_count" -ge 3 ] && [ "$pattern_count" -le 6 ]; then
    echo "   ${GREEN}✓ Good pattern coverage (3-6 recommended)${NC}"
    passed_checks=$((passed_checks + 1))
elif [ "$pattern_count" -lt 3 ]; then
    echo "   ${YELLOW}⚠ Only $pattern_count pattern(s) documented${NC}"
    echo "   ${YELLOW}  Consider documenting more reusable patterns${NC}"
else
    echo "   ${YELLOW}⚠ $pattern_count patterns documented (6 recommended max)${NC}"
    echo "   ${YELLOW}  Consider consolidating similar patterns${NC}"
fi

echo ""

# Check 6: Archive links
echo "${BLUE}6. Checking for archive references...${NC}"
total_checks=$((total_checks + 1))
archive_ref=$(grep -c "DEVELOPMENT_HISTORY.md" "$CLAUDE_FILE" || true)

if [ "$archive_ref" -gt 0 ]; then
    echo "   ${GREEN}✓ Links to DEVELOPMENT_HISTORY.md found${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo "   ${YELLOW}⚠ No reference to DEVELOPMENT_HISTORY.md${NC}"
    echo "   ${YELLOW}  Add link in 'Reference Documentation' section${NC}"
fi

echo ""

# Summary
echo "${BLUE}═══════════════════════════════════════${NC}"
echo "${BLUE}   Summary${NC}"
echo "${BLUE}═══════════════════════════════════════${NC}"
echo ""

score=$((passed_checks * 100 / total_checks))
echo "Score: $passed_checks/$total_checks checks passed ($score%)"
echo ""

if [ "$score" -ge 80 ]; then
    echo "${GREEN}✓ CLAUDE.md is healthy!${NC}"
    echo ""
    exit 0
elif [ "$score" -ge 50 ]; then
    echo "${YELLOW}⚠ CLAUDE.md needs attention${NC}"
    echo "${YELLOW}  Review warnings above and consider refactoring${NC}"
    echo ""
    exit 0
else
    echo "${RED}✗ CLAUDE.md needs immediate refactoring${NC}"
    echo "${RED}  See docs/CLAUDE_MD_TEMPLATE.md for guidance${NC}"
    echo ""
    exit 1
fi
