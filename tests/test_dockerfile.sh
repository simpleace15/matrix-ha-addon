#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# test_dockerfile.sh — Validate the Dockerfile for common HA addon pitfalls
# ──────────────────────────────────────────────────────────────────────
# Catches the exact bugs we hit during development:
#   1. ARG BUILD_FROM declared inside a FROM scope (empty base image)
#   2. ARG ELEMENT_WEB_VERSION not redeclared in builder stage (empty in RUN)
#   3. COPY --from=builder paths that don't match the build output
#   4. Missing CMD or run.sh not made executable
#   5. ADD URL validity (tarball URL resolves, not git clone which needs DNS)
# ──────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKERFILE="$REPO_ROOT/matrix_web_addon/Dockerfile"

PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "━━━ Dockerfile Tests ━━━"

# ── 1. File exists ──
if [ -f "$DOCKERFILE" ]; then
    pass "Dockerfile exists"
else
    fail "Dockerfile not found at $DOCKERFILE"
    exit 1
fi

# ── 2. ARG BUILD_FROM declared before any FROM (global scope) ──
# This was bug #1: ARG BUILD_FROM was after the first FROM, so
# Docker treated it as stage-scoped and it was empty for stage 2's FROM.
first_from_line=$(grep -n '^FROM ' "$DOCKERFILE" | head -1 | cut -d: -f1)
build_from_arg_line=$(grep -n '^ARG BUILD_FROM' "$DOCKERFILE" | head -1 | cut -d: -f1)

if [ -z "$first_from_line" ] || [ -z "$build_from_arg_line" ]; then
    fail "Could not find FROM or ARG BUILD_FROM lines"
else
    if [ "$build_from_arg_line" -lt "$first_from_line" ]; then
        pass "ARG BUILD_FROM is declared before first FROM (global scope)"
    else
        fail "ARG BUILD_FROM (line $build_from_arg_line) is after first FROM (line $first_from_line) — will be empty in stage 2"
    fi
fi

# ── 3. ARG ELEMENT_WEB_VERSION redeclared inside builder stage ──
# This was bug #3: global ARG is only available in FROM lines, not RUN.
# The builder stage must redeclare it for git clone / ADD to use it.
builder_stage_start=$(grep -n '^FROM .* AS builder' "$DOCKERFILE" | head -1 | cut -d: -f1)
second_from_line=$(grep -n '^FROM ' "$DOCKERFILE" | sed -n 2p | cut -d: -f1)

if [ -z "$builder_stage_start" ] || [ -z "$second_from_line" ]; then
    fail "Could not locate builder stage or second FROM"
else
    # Look for ARG ELEMENT_WEB_VERSION between builder FROM and second FROM
    redeclare_found=false
    while IFS= read -r line_num; do
        if [ "$line_num" -gt "$builder_stage_start" ] && [ "$line_num" -lt "$second_from_line" ]; then
            redeclare_found=true
            break
        fi
    done < <(grep -n '^ARG ELEMENT_WEB_VERSION' "$DOCKERFILE" | cut -d: -f1)

    if [ "$redeclare_found" = true ]; then
        pass "ARG ELEMENT_WEB_VERSION is redeclared inside builder stage"
    else
        fail "ARG ELEMENT_WEB_VERSION not redeclared inside builder stage — will be empty in RUN commands"
    fi
fi

# ── 4. Two-stage build (builder + runtime) ──
if grep -q 'FROM .* AS builder' "$DOCKERFILE" && grep -q 'FROM \${BUILD_FROM}' "$DOCKERFILE"; then
    pass "Two-stage build: builder + \${BUILD_FROM} runtime"
else
    fail "Missing expected two-stage build structure"
fi

# ── 5. No git clone (use ADD tarball instead — avoids container DNS issues) ──
if grep -q 'git clone' "$DOCKERFILE"; then
    fail "Dockerfile uses 'git clone' — will fail on HA hosts with container DNS issues. Use ADD <url> instead."
elif grep -q '^ADD https://' "$DOCKERFILE"; then
    pass "Uses ADD <url> for source download (no git clone — DNS-safe)"
else
    fail "Neither ADD <url> nor git clone found — how is source being fetched?"
fi

# ── 6. COPY --from=builder path matches build output ──
# The build produces webapp/ in the builder stage. The COPY must reference
# the correct path (e.g. /build/element-web/webapp).
copy_line=$(grep 'COPY --from=builder' "$DOCKERFILE" | head -1)
if [ -n "$copy_line" ]; then
    pass "COPY --from=builder found: $copy_line"
    # Verify the path ends with /webapp
    if echo "$copy_line" | grep -q '/webapp'; then
        pass "COPY --from=builder path includes /webapp"
    else
        fail "COPY --from=builder path doesn't end with /webapp — build output won't be copied correctly"
    fi
else
    fail "COPY --from=builder not found — built static files won't be copied to runtime"
fi

# ── 7. run.sh is made executable in the Dockerfile ──
if grep -q 'chmod.*run.sh' "$DOCKERFILE"; then
    pass "run.sh is chmod'd in Dockerfile"
else
    fail "run.sh not made executable in Dockerfile"
fi

# ── 8. CMD or ENTRYPOINT points to run.sh ──
if grep -qE '(CMD|ENTRYPOINT).*run\.sh' "$DOCKERFILE"; then
    pass "CMD/ENTRYPOINT references run.sh"
else
    fail "No CMD/ENTRYPOINT referencing run.sh — container won't start"
fi

# ── 9. HA labels present ──
for label in io.hass.type io.hass.arch; do
    if grep -q "$label" "$DOCKERFILE"; then
        pass "Label $label present"
    else
        fail "Label $label missing"
    fi
done

# ── 10. No exposed ports (Ingress only — no 'ports' in config.yaml) ──
# We check the Dockerfile for EXPOSE (shouldn't have it) and config.yaml for ports
if grep -qi '^EXPOSE' "$DOCKERFILE"; then
    fail "Dockerfile has EXPOSE — addon should use Ingress only (no exposed ports)"
else
    pass "No EXPOSE in Dockerfile (Ingress only)"
fi

# ── 11. Verify the ADD tarball URL is reachable (if curl available) ──
add_url=$(grep '^ADD https://' "$DOCKERFILE" | head -1 | awk '{print $2}' | cut -d' ' -f1)
if [ -n "$add_url" ] && command -v curl &>/dev/null; then
    # Replace ${ELEMENT_WEB_VERSION} with the actual version from ARG
    version=$(grep '^ARG ELEMENT_WEB_VERSION=' "$DOCKERFILE" | head -1 | cut -d= -f2)
    resolved_url="${add_url/\$\{ELEMENT_WEB_VERSION\}/$version}"
    http_code=$(curl -sI -o /dev/null -w '%{http_code}' -L "$resolved_url" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ]; then
        pass "ADD tarball URL resolves (HTTP $http_code): $resolved_url"
    elif [ "$http_code" = "000" ]; then
        echo "  ⚠️  ADD tarball URL unreachable (network issue, skipping): $resolved_url"
    else
        fail "ADD tarball URL returns HTTP $http_code: $resolved_url"
    fi
else
    echo "  ⚠️  Skipping ADD URL reachability check (no curl or no URL)"
fi

echo ""
echo "  Results: $PASS passed, $FAIL failed"
exit $FAIL