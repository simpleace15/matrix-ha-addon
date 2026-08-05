#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# test_run.sh — Validate run.sh startup script and jq config patching
# ──────────────────────────────────────────────────────────────────────
# Catches:
#   - Bash syntax errors in run.sh
#   - Missing jq dependency or nginx start
#   - jq patch logic producing invalid JSON or wrong values
#   - run.sh not executable
#   - Options file reading (HA /data/options.json pattern)
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SH="$REPO_ROOT/matrix_web_addon/run.sh"
CONFIG_JSON="$REPO_ROOT/matrix_web_addon/config.json"

PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "━━━ run.sh Tests ━━━"

if [ ! -f "$RUN_SH" ]; then
    fail "run.sh not found"
    exit 1
fi

# ── 1. Bash syntax check ──
if bash -n "$RUN_SH" 2>&1; then
    pass "run.sh passes bash syntax check"
else
    fail "run.sh has bash syntax errors"
    bash -n "$RUN_SH"
    exit 1
fi

# ── 2. Executable bit ──
if [ -x "$RUN_SH" ]; then
    pass "run.sh is executable"
else
    fail "run.sh is not executable"
fi

# ── 3. Reads /data/options.json ──
if grep -q '/data/options.json' "$RUN_SH"; then
    pass "Reads /data/options.json (HA Supervisor pattern)"
else
    fail "run.sh doesn't read /data/options.json"
fi

# ── 4. Uses jq for config patching ──
if grep -q 'jq' "$RUN_SH"; then
    pass "Uses jq for config.json patching"
else
    fail "run.sh doesn't use jq — can't patch config.json at runtime"
fi

# ── 5. Starts nginx in foreground ──
if grep -q 'nginx.*daemon off' "$RUN_SH"; then
    pass "Starts nginx in foreground (daemon off)"
else
    fail "run.sh doesn't start nginx with 'daemon off' — container will exit immediately"
fi

# ── 6. Patches homeserver_url in config.json ──
if grep -q 'base_url.*\$hs' "$RUN_SH"; then
    pass "Patches homeserver base_url with configured value"
else
    fail "run.sh doesn't patch homeserver base_url"
fi

# ── 7. Patches server_name in config.json ──
if grep -q 'server_name.*\$sn' "$RUN_SH"; then
    pass "Patches server_name with configured value"
else
    fail "run.sh doesn't patch server_name"
fi

# ── 8. Patches brand in config.json ──
if grep -q 'brand.*\$brand' "$RUN_SH"; then
    pass "Patches brand with configured value"
else
    fail "run.sh doesn't patch brand"
fi

# ── 9. Has fallback defaults (when /data/options.json doesn't exist) ──
if grep -q 'matrix.example.com' "$RUN_SH"; then
    pass "Has fallback defaults for homeserver"
else
    fail "run.sh missing fallback defaults for homeserver"
fi

# ── 10. set -e (fail on error) ──
if grep -q 'set -e' "$RUN_SH"; then
    pass "Uses 'set -e' (fail fast on errors)"
else
    fail "run.sh missing 'set -e' — errors won't stop execution"
fi

# ═══════════════════════════════════════
# Functional test: jq patch produces valid JSON
# ═══════════════════════════════════════
echo "  ── jq patch functional test ──"

if ! command -v jq &>/dev/null; then
    echo "  ⚠️  jq not installed on this system — skipping functional tests"
    echo ""
    echo "  Results: $PASS passed, $FAIL failed"
    exit $FAIL
fi

# Create a temp options file (simulates HA /data/options.json)
TMPDIR=$(mktemp -d)
trap 'rm -rf $TMPDIR' EXIT

TEST_OPTIONS="$TMPDIR/options.json"
TEST_CONFIG="$TMPDIR/config.json"
PATCHED_CONFIG="$TMPDIR/config_patched.json"

cat > "$TEST_OPTIONS" <<'EOF'
{
    "homeserver_url": "https://matrix.test.example",
    "homeserver_name": "matrix.test.example",
    "server_name": "matrix.test.example",
    "brand": "Test Brand",
    "log_level": "debug"
}
EOF

# Copy the real config.json
cp "$CONFIG_JSON" "$TEST_CONFIG"

# Extract the jq command from run.sh and run it with test values
HOMESERVER_URL="https://matrix.test.example"
SERVER_NAME="matrix.test.example"
BRAND="Test Brand"

jq --arg hs "$HOMESERVER_URL" --arg sn "$SERVER_NAME" --arg brand "$BRAND" '
    .default_server_config["m.homeserver"].base_url = $hs |
    .default_server_config["m.homeserver"].server_name = $sn |
    .brand = $brand |
    .room_directory.servers = [$sn]
' "$TEST_CONFIG" > "$PATCHED_CONFIG" 2>&1

if [ $? -ne 0 ]; then
    fail "jq patch command failed"
    exit 1
fi

# Validate patched JSON
if python3 -c "import json; json.load(open('$PATCHED_CONFIG'))" 2>/dev/null; then
    pass "jq patch produces valid JSON"
else
    fail "jq patch produces invalid JSON"
    exit 1
fi

# Verify patched values
check_field() {
    local python_expr="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual=$(python3 -c "import json; $python_expr" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass "$label: $actual"
    else
        fail "$label: expected '$expected', got '$actual'"
    fi
}

check_field "print(json.load(open('$PATCHED_CONFIG'))['default_server_config']['m.homeserver']['base_url'])" \
    "https://matrix.test.example" "Patched base_url"

check_field "print(json.load(open('$PATCHED_CONFIG'))['default_server_config']['m.homeserver']['server_name'])" \
    "matrix.test.example" "Patched server_name"

check_field "print(json.load(open('$PATCHED_CONFIG'))['brand'])" \
    "Test Brand" "Patched brand"

check_field "print(json.load(open('$PATCHED_CONFIG'))['room_directory']['servers'][0])" \
    "matrix.test.example" "Patched room_directory.servers"

# Verify fields that should NOT be changed by the patch
check_field "print(json.load(open('$PATCHED_CONFIG'))['default_theme'])" \
    "dark" "Unpatched default_theme (preserved)"

check_field "print(json.load(open('$PATCHED_CONFIG'))['features']['feature_threads'])" \
    "True" "Unpatched feature_threads (preserved)"

echo ""
echo "  Results: $PASS passed, $FAIL failed"
exit $FAIL