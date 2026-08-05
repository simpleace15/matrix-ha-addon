#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# run_tests.sh — Master test runner for matrix-ha-addon
# ──────────────────────────────────────────────────────────────────────
# Runs all test suites in tests/ and exits non-zero if any fail.
# Used by CI (GitHub Actions) and can be run locally.
#
# Usage:
#   ./tests/run_tests.sh              # run all tests
#   ./tests/run_tests.sh --verbose    # show all output (not just failures)
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERBOSE=false
if [ "${1:-}" = "--verbose" ] || [ "${1:-}" = "-v" ]; then
    VERBOSE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Matrix HA Addon — Test Suite                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check dependencies ──
echo "Checking dependencies..."
missing_deps=()

if ! command -v bash &>/dev/null; then
    missing_deps+=("bash")
fi

if ! command -v python3 &>/dev/null; then
    missing_deps+=("python3")
fi

# PyYAML check
if ! python3 -c "import yaml" 2>/dev/null; then
    missing_deps+=("PyYAML (pip install pyyaml)")
fi

if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}⚠️  jq not found — run.sh functional tests will be skipped${NC}"
fi

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
    exit 1
fi

echo -e "${GREEN}All required dependencies found${NC}"
echo ""

# ── Run test suites ──
TEST_SUITES=(
    "$SCRIPT_DIR/test_dockerfile.sh"
    "$SCRIPT_DIR/test_configs.sh"
    "$SCRIPT_DIR/test_run.sh"
)

for suite in "${TEST_SUITES[@]}"; do
    suite_name=$(basename "$suite" .sh)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running: $suite_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ "$VERBOSE" = true ]; then
        bash "$suite" 2>&1 | tee /tmp/test_output_$$
        exit_code=${PIPESTATUS[0]}
    else
        # Run quietly, only show output on failure
        bash "$suite" > /tmp/test_output_$$ 2>&1
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ]; then
        echo -e "  ${GREEN}✅ $suite_name PASSED${NC}"
    else
        echo -e "  ${RED}❌ $suite_name FAILED${NC}"
        echo ""
        cat /tmp/test_output_$$
        FAILED_SUITES+=("$suite_name")
    fi

    echo ""

    rm -f /tmp/test_output_$$
done

# ── Summary ──
echo "════════════════════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════════════════════"
echo ""

total_suites=${#TEST_SUITES[@]}
failed_suites=${#FAILED_SUITES[@]}
passed_suites=$((total_suites - failed_suites))

echo "  Test suites: $total_suites total, $passed_suites passed, $failed_suites failed"
echo ""

if [ $failed_suites -eq 0 ]; then
    echo -e "  ${GREEN}✅ All test suites passed!${NC}"
    echo ""
    exit 0
else
    echo -e "  ${RED}❌ Failed suites: ${FAILED_SUITES[*]}${NC}"
    echo ""
    exit 1
fi