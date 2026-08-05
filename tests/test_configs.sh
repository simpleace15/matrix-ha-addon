#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# test_configs.sh — Validate HA addon config.yaml, Element config.json,
#                    and nginx.conf
# ──────────────────────────────────────────────────────────────────────
# Catches:
#   - Missing required HA addon fields in config.yaml
#   - Invalid JSON in config.json
#   - Missing required Element Web config keys
#   - nginx.conf missing SPA routing, Ingress headers, or port 8080
#   - Ingress/panel misconfiguration
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_YAML="$REPO_ROOT/matrix_web_addon/config.yaml"
CONFIG_JSON="$REPO_ROOT/matrix_web_addon/config.json"
NGINX_CONF="$REPO_ROOT/matrix_web_addon/nginx.conf"

PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "━━━ Config Tests ━━━"

# ── Python helper for YAML/JSON parsing ──
python_check() {
    python3 -c "$1" 2>&1
}

# ═══════════════════════════════════════
# config.yaml (HA Addon Manifest)
# ═══════════════════════════════════════
echo "  ── config.yaml ──"

if [ ! -f "$CONFIG_YAML" ]; then
    fail "config.yaml not found"
    exit 1
fi

# Valid YAML
if python_check "import yaml; yaml.safe_load(open('$CONFIG_YAML'))" >/dev/null; then
    pass "config.yaml is valid YAML"
else
    fail "config.yaml is not valid YAML"
    python_check "import yaml; yaml.safe_load(open('$CONFIG_YAML'))"
    exit 1
fi

# Required HA addon fields
REQUIRED_FIELDS=(
    name version slug description arch init ingress ingress_port
    panel_icon panel_title options schema
)

for field in "${REQUIRED_FIELDS[@]}"; do
    result=$(python_check "
import yaml
c = yaml.safe_load(open('$CONFIG_YAML'))
print('OK' if '$field' in c else 'MISSING')
")
    if [ "$result" = "OK" ]; then
        pass "config.yaml has required field: $field"
    else
        fail "config.yaml missing required field: $field"
    fi
done

# Ingress must be true
ingress=$(python_check "import yaml; print(yaml.safe_load(open('$CONFIG_YAML'))['ingress'])")
if [ "$ingress" = "True" ] || [ "$ingress" = "true" ]; then
    pass "ingress is enabled"
else
    fail "ingress should be true, got: $ingress"
fi

# Ingress port must be 8080 (matches nginx.conf and Dockerfile)
ingress_port=$(python_check "import yaml; print(yaml.safe_load(open('$CONFIG_YAML'))['ingress_port'])")
if [ "$ingress_port" = "8080" ]; then
    pass "ingress_port is 8080"
else
    fail "ingress_port should be 8080, got: $ingress_port"
fi

# No 'ports' mapping (Ingress only — no exposed ports)
has_ports=$(python_check "import yaml; print('yes' if 'ports' in yaml.safe_load(open('$CONFIG_YAML')) else 'no')")
if [ "$has_ports" = "no" ]; then
    pass "No 'ports' mapping (Ingress only)"
else
    fail "config.yaml has 'ports' — addon should use Ingress only"
fi

# Schema must have matching options keys
schema_check=$(python_check "
import yaml
c = yaml.safe_load(open('$CONFIG_YAML'))
opts = set(c.get('options', {}).keys())
schema = set(c.get('schema', {}).keys())
missing = opts - schema
extra = schema - opts
if missing:
    print(f'OPTIONS_NOT_IN_SCHEMA: {missing}')
elif extra:
    print(f'SCHEMA_NOT_IN_OPTIONS: {extra}')
else:
    print('OK')
" 2>&1 || echo "PYTHON_ERROR")
if [ "$schema_check" = "OK" ]; then
    pass "options and schema keys match"
else
    fail "options/schema mismatch: $schema_check"
fi

# ═══════════════════════════════════════
# config.json (Element Web Config)
# ═══════════════════════════════════════
echo "  ── config.json ──"

if [ ! -f "$CONFIG_JSON" ]; then
    fail "config.json not found"
    exit 1
fi

# Valid JSON
if python_check "import json; json.load(open('$CONFIG_JSON'))" >/dev/null; then
    pass "config.json is valid JSON"
else
    fail "config.json is not valid JSON"
    python_check "import json; json.load(open('$CONFIG_JSON'))"
    exit 1
fi

# Required Element Web config keys
# Using > as separator since m.homeserver contains a dot
REQUIRED_JSON_KEYS=(
    "default_server_config"
    "default_server_config>m.homeserver>base_url"
    "default_server_config>m.homeserver>server_name"
    "brand"
    "default_theme"
    "room_directory"
    "room_directory>servers"
)

for key in "${REQUIRED_JSON_KEYS[@]}"; do
    result=$(python_check "
import json
d = json.load(open('$CONFIG_JSON'))
parts = '$key'.split('>')
obj = d
for p in parts:
    if p not in obj:
        print('MISSING')
        break
    obj = obj[p]
else:
    print('OK')
")
    if [ "$result" = "OK" ]; then
        pass "config.json has key: $key"
    else
        fail "config.json missing key: $key"
    fi
done

# Threads must be enabled (key reason we chose Element Web)
threads_feature=$(python_check "import json; print(json.load(open('$CONFIG_JSON'))['features']['feature_threads'])")
if [ "$threads_feature" = "True" ]; then
    pass "Threads enabled (feature_threads: true)"
else
    fail "Threads not enabled — feature_threads should be true"
fi

threading_view=$(python_check "import json; print(json.load(open('$CONFIG_JSON'))['setting_defaults']['ThreadingView'])")
if [ "$threading_view" = "True" ]; then
    pass "ThreadingView enabled"
else
    fail "ThreadingView should be true"
fi

# Default theme should be dark
theme=$(python_check "import json; print(json.load(open('$CONFIG_JSON'))['default_theme'])")
if [ "$theme" = "dark" ]; then
    pass "Default theme is dark"
else
    fail "Default theme should be 'dark', got: $theme"
fi

# ═══════════════════════════════════════
# nginx.conf
# ═══════════════════════════════════════
echo "  ── nginx.conf ──"

if [ ! -f "$NGINX_CONF" ]; then
    fail "nginx.conf not found"
    exit 1
fi

# Listens on port 8080
if grep -q 'listen 8080' "$NGINX_CONF"; then
    pass "nginx listens on port 8080"
else
    fail "nginx.conf doesn't listen on port 8080 (must match ingress_port)"
fi

# SPA routing (try_files ... index.html)
if grep -q 'try_files.*index\.html' "$NGINX_CONF"; then
    pass "SPA routing (try_files → index.html) present"
else
    fail "nginx.conf missing SPA routing — needs 'try_files \$uri \$uri/ /index.html'"
fi

# X-Frame-Options for Ingress
if grep -qi 'X-Frame-Options.*SAMEORIGIN' "$NGINX_CONF"; then
    pass "X-Frame-Options: SAMEORIGIN (Ingress iframe compatible)"
else
    fail "nginx.conf missing X-Frame-Options: SAMEORIGIN — won't render in HA Ingress iframe"
fi

# No restrictive CSP frame-ancestors that would block Ingress
if grep -qi 'frame-ancestors.*none' "$NGINX_CONF"; then
    fail "nginx.conf has 'frame-ancestors: none' — would block HA Ingress"
else
    pass "No restrictive frame-ancestors CSP"
fi

# Gzip enabled
if grep -q 'gzip on' "$NGINX_CONF"; then
    pass "Gzip compression enabled"
else
    fail "nginx.conf missing gzip — large JS bundles won't be compressed"
fi

# Root directory set
if grep -q 'root /app/webapp' "$NGINX_CONF"; then
    pass "nginx root is /app/webapp"
else
    fail "nginx.conf root should be /app/webapp"
fi

# config.json should never be cached (patched at startup)
if grep -q 'config\.json' "$NGINX_CONF" && grep -qi 'no-store\|no-cache' "$NGINX_CONF"; then
    pass "config.json is set to no-cache (runtime patched)"
else
    fail "nginx.conf should have a no-cache rule for config.json"
fi

# ── Cross-file consistency ──
echo "  ── Cross-file consistency ──"

# Ingress port in config.yaml matches nginx listen port
if [ "$ingress_port" = "8080" ] && grep -q 'listen 8080' "$NGINX_CONF"; then
    pass "Ingress port (config.yaml) matches nginx listen port (8080)"
else
    fail "Port mismatch between config.yaml and nginx.conf"
fi

# nginx root matches Dockerfile COPY destination
if grep -q 'root /app/webapp' "$NGINX_CONF" && grep -q 'COPY.* /app/webapp' "$REPO_ROOT/matrix_web_addon/Dockerfile"; then
    pass "nginx root (/app/webapp) matches Dockerfile COPY destination"
else
    fail "nginx root doesn't match Dockerfile COPY path"
fi

echo ""
echo "  Results: $PASS passed, $FAIL failed"
exit $FAIL