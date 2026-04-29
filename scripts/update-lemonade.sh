#!/usr/bin/env bash
# Automatically bumps lemonade-nix to the latest upstream release.
# Usage: ./scripts/update-lemonade.sh [--dry-run]
#
# Requires on PATH: git, curl, jq, nix, nix-prefetch-github, sed, grep
# To bring in nix-prefetch-github:
#   nix shell nixpkgs#nix-prefetch-github nixpkgs#jq --command ./scripts/update-lemonade.sh
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

# ── Pre-flight ────────────────────────────────────────────────────────────────

for tool in git curl jq nix nix-prefetch-github sed grep; do
    command -v "$tool" > /dev/null 2>&1 \
        || die "Required tool not found: $tool
  To install nix-prefetch-github: nix shell nixpkgs#nix-prefetch-github"
done

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] \
    || die "Not on main branch (currently on '$BRANCH'). Switch to main first."
[[ -z "$(git status --porcelain)" ]] \
    || die "Working tree is dirty. Commit or stash changes first."
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

# ── Compute lemonade-src hash ─────────────────────────────────────────────────

echo "Computing lemonade-src hash for v$NEW_VERSION..."
PREFETCH=$(nix-prefetch-github --json lemonade-sdk lemonade --rev "v$NEW_VERSION")
NEW_SRC_HASH=$(echo "$PREFETCH" | jq -r '.hash // .sha256')
# Older nix-prefetch-github outputs Nix base32 in .sha256; convert to SRI.
if [[ "$NEW_SRC_HASH" != sha256-* ]]; then
    NEW_SRC_HASH=$(nix hash to-sri --type sha256 "$NEW_SRC_HASH")
fi
echo "  lemonade-src hash: $NEW_SRC_HASH"

# ── Patch flake.nix: version + lemonade-src hash ──────────────────────────────

echo "Patching flake.nix..."

sed -i "s|version = \"$CURRENT_VERSION\";|version = \"$NEW_VERSION\";|" flake.nix

# Replace hash only inside the lemonade-src block (stops at first }; after the block opens).
sed -i "/lemonade-src = pkgs.fetchFromGitHub/,/^[[:space:]]*};$/{
    s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$NEW_SRC_HASH\";|
}" flake.nix

# Sanity-check: the new hash must appear exactly once.
HASH_MATCHES=$(grep -c "hash = \"$NEW_SRC_HASH\"" flake.nix || true)
[[ "$HASH_MATCHES" -eq 1 ]] \
    || die "lemonade-src hash patch failed or matched $HASH_MATCHES times. Restore flake.nix with: git checkout flake.nix"

# ── Compute lemonade-webapp outputHash via fake-hash trick ────────────────────

echo "Computing lemonade-webapp outputHash..."
echo "  (Running nix build with a fake hash to get the real one — may take several minutes.)"

ORIG_OUTPUT_HASH=$(grep -oP 'outputHash = "\K[^"]+' flake.nix | head -1)
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
sed -i "s|outputHash = \"$ORIG_OUTPUT_HASH\";|outputHash = \"$FAKE_HASH\";|" flake.nix

LOG=$(mktemp /tmp/lemonade-update.XXXXXX.log)
echo "  Build log: $LOG"
nix build .#default --no-link 2>&1 | tee "$LOG" || true

NEW_OUTPUT_HASH=$(grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' "$LOG" | tail -1)
if [[ -z "$NEW_OUTPUT_HASH" ]]; then
    echo "" >&2
    echo "ERROR: Could not extract outputHash from build output." >&2
    echo "       lemonade-src hash may also be wrong — check the build log." >&2
    echo "       Build log: $LOG" >&2
    echo "       Working tree is dirty; inspect and finish manually." >&2
    exit 1
fi
echo "  outputHash: $NEW_OUTPUT_HASH"

sed -i "s|outputHash = \"$FAKE_HASH\";|outputHash = \"$NEW_OUTPUT_HASH\";|" flake.nix

# ── Final verification build ──────────────────────────────────────────────────

echo "Running final verification build..."
if ! nix build .#default; then
    echo "" >&2
    cat >&2 <<EOF
ERROR: Final build failed — this looks like a non-routine bump.
       Possible causes: renamed binary, swapped dependency, broken postPatch.
       Compare upstream changes:
         https://github.com/lemonade-sdk/lemonade/compare/v$CURRENT_VERSION...v$NEW_VERSION
       Working tree is intentionally left dirty. Finish the bump manually.
EOF
    exit 1
fi

# ── Update README ─────────────────────────────────────────────────────────────

sed -i "s/Lemonade \*\*v[0-9.]\+\*\*/Lemonade **v$NEW_VERSION**/" README.md

# ── Commit and push ───────────────────────────────────────────────────────────

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
