#!/usr/bin/env bash
# Automatically bumps lemonade-nix to the latest upstream release.
# Usage: ./scripts/update-lemonade.sh [--dry-run]
#
# Requires on PATH: git, curl, jq, nix, sed, grep  (all standard; no extra tools needed)
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[dry-run] Will skip git push"
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

extract_got_hash() {
    grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' "$1" | tail -1
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

for tool in git curl jq nix sed grep; do
    command -v "$tool" > /dev/null 2>&1 || die "Required tool not found: $tool"
done

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] \
    || die "Not on main branch (currently on '$BRANCH'). Switch to main first."
git diff --quiet && git diff --cached --quiet \
    || die "Working tree has uncommitted changes. Commit or stash first."
git remote get-url origin > /dev/null 2>&1 \
    || die "No 'origin' remote configured."

# ── Detect latest release ─────────────────────────────────────────────────────

echo "Fetching latest Lemonade release from GitHub..."
LATEST_TAG=$(curl -fsSL \
    "https://api.github.com/repos/lemonade-sdk/lemonade/releases/latest" \
    | jq -r '.tag_name')
[[ "$LATEST_TAG" == v* ]] \
    || die "Unexpected tag format from GitHub API: '$LATEST_TAG'"
NEW_VERSION="${LATEST_TAG#v}"

CURRENT_VERSION=$(grep -oP 'version = "\K[0-9.]+' flake.nix | head -1)
echo "Current: v$CURRENT_VERSION  →  Latest: v$NEW_VERSION"

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "Already at v$NEW_VERSION. Nothing to do."
    exit 0
fi

LOG=$(mktemp /tmp/lemonade-update.XXXXXX.log)

# ── Build 1: get lemonade-src hash ───────────────────────────────────────────
# Bump version and set a fake lemonade-src hash; nix fails fast at the network
# fetch and reports the real hash in the error output.

echo "Patching version..."
sed -i "s|version = \"$CURRENT_VERSION\";|version = \"$NEW_VERSION\";|" flake.nix

echo "Build 1/3: computing lemonade-src hash..."
sed -i "/lemonade-src = pkgs.fetchFromGitHub/,/^[[:space:]]*};$/{
    s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$FAKE_HASH\";|
}" flake.nix

nix build .#default --no-link 2>&1 | tee "$LOG" || true

NEW_SRC_HASH=$(extract_got_hash "$LOG")
[[ -n "$NEW_SRC_HASH" ]] \
    || die "Could not extract lemonade-src hash from build output. Log: $LOG"
echo "  lemonade-src hash: $NEW_SRC_HASH"

sed -i "/lemonade-src = pkgs.fetchFromGitHub/,/^[[:space:]]*};$/{
    s|hash = \"$FAKE_HASH\";|hash = \"$NEW_SRC_HASH\";|
}" flake.nix

# ── Build 2: get lemonade-webapp outputHash ───────────────────────────────────
# Source hash is now correct; fake the webapp FOD hash so nix builds the web
# app and reports the real hash at the end.

ORIG_OUTPUT_HASH=$(grep -oP 'outputHash = "\K[^"]+' flake.nix | head -1)
sed -i "s|outputHash = \"$ORIG_OUTPUT_HASH\";|outputHash = \"$FAKE_HASH\";|" flake.nix

echo "Build 2/3: computing lemonade-webapp outputHash (runs npm install + webpack, may take minutes)..."
echo "  Log: $LOG"
nix build .#default --no-link 2>&1 | tee "$LOG" || true

NEW_OUTPUT_HASH=$(extract_got_hash "$LOG")
if [[ -z "$NEW_OUTPUT_HASH" ]]; then
    echo "" >&2
    echo "ERROR: Could not extract outputHash from build output." >&2
    echo "       Log: $LOG" >&2
    echo "       Working tree is intentionally left dirty." >&2
    exit 1
fi
echo "  outputHash: $NEW_OUTPUT_HASH"

sed -i "s|outputHash = \"$FAKE_HASH\";|outputHash = \"$NEW_OUTPUT_HASH\";|" flake.nix

# ── Build 3: final verification ───────────────────────────────────────────────

echo "Build 3/3: final verification..."
if ! nix build .#default; then
    cat >&2 <<EOF

ERROR: Final build failed — likely a non-routine bump (renamed binary, swapped dep, broken postPatch).
       Compare upstream changes:
         https://github.com/lemonade-sdk/lemonade/compare/v$CURRENT_VERSION...v$NEW_VERSION
       Working tree is intentionally left dirty. Finish the bump manually.
EOF
    exit 1
fi

# ── Update README + commit ────────────────────────────────────────────────────

sed -i "s/Lemonade \*\*v[0-9.]\+\*\*/Lemonade **v$NEW_VERSION**/" README.md

echo "Committing..."
git add flake.nix README.md
git commit -m "Update to Lemonade v$NEW_VERSION"

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Skipping git push. Commit is local only."
else
    echo "Pushing to origin/main..."
    git push origin main
fi

RESULT_PATH=$(readlink -f result 2>/dev/null || echo "(no result symlink)")
echo ""
echo "✓ Lemonade v$NEW_VERSION"
echo "  lemonade-src hash:  $NEW_SRC_HASH"
echo "  webapp outputHash:  $NEW_OUTPUT_HASH"
echo "  Build result:       $RESULT_PATH"
