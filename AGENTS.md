# AGENTS.md

Nix flake packaging [Lemonade](https://github.com/lemonade-sdk/lemonade) — a local LLM server with GPU/NPU acceleration, an OpenAI-compatible API, and a built-in React web UI.

## Project Type

This is a **Nix packaging project** (not an application). All build logic lives in a single `flake.nix`. There are no application source files in this repo — the actual source is fetched from GitHub via `fetchFromGitHub`.

## Essential Commands

```bash
# Build the package (outputs to ./result symlink)
nix build

# Run the router (main binary)
nix run

# Enter development shell (Python 3 with black, pylint, requests)
nix develop

# Install into user profile
nix profile install git+https://codeberg.org/tmichnicki/lemonade-nix
```

## Updating the Package

### Bumping the Lemonade version (automated)

Run the update script — it detects a new release, computes hashes, builds, and pushes:

```bash
./scripts/update-lemonade.sh          # auto-detects latest, commits, and pushes
./scripts/update-lemonade.sh --dry-run  # same but skips git push (for testing)
```

Requires `nix-prefetch-github` on PATH. If it isn't installed:

```bash
nix shell nixpkgs#nix-prefetch-github --command ./scripts/update-lemonade.sh
```

If the script fails at the final build step (non-routine break: renamed binary, swapped transitive dep, broken `postPatch`), it leaves the tree dirty so you can finish by hand. See the manual procedure below.

### Bumping the Lemonade version (manual fallback)

1. Change `version` in `flake.nix` (line 14) to the new version
2. Update `lemonade-src` hash — replace the hash with a fake one (e.g. `sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`), then run `nix build` and copy the expected hash from the error
3. Repeat for `lemonade-webapp` `outputHash` (line 73) — same fake-hash technique
4. Check if `cpp-httplib` or `libwebsockets` dependency versions in the upstream CMakeLists.txt have changed; update their `rev`/`hash` if so

### Updating nixpkgs

```bash
nix flake lock --update-input nixpkgs
```

## Repository Structure

```
flake.nix          # All build/packaging logic — the only file you'll edit
flake.lock         # Pinned dependency versions (nixpkgs, flake-utils)
README.md          # User-facing documentation
result/            # Build output symlink (gitignored)
```

## flake.nix Architecture

The flake has three main derivations:

1. **`lemonade-src`** — Fetches the Lemonade release tarball from GitHub (`v${version}`)
2. **`lemonade-webapp`** — Fixed-output derivation that builds the React web app via npm/webpack outside the Nix sandbox (required because npm needs network access)
3. **`packages.default`** — The main CMake build of `lemonade-router` and `lemonade-server`, with the pre-built web app injected in `installPhase`

Key design decisions:
- `cpp-httplib` and `IXWebSocket` are pre-fetched via `fetchFromGitHub` and passed to CMake via `FETCHCONTENT_SOURCE_DIR_*` flags, because they aren't in nixpkgs and CMake FetchContent can't access the network inside the sandbox
- The web app is built as a separate fixed-output derivation (`outputHash` instead of `outputHashAlgo`+`outputHash` on older nix) so npm can reach the network; the hash ensures reproducibility
- A `postPatch` sed command patches `path_utils.cpp` so resource lookup works with the FHS install layout (`$prefix/share/lemonade-server/`)
- Linux-specific build inputs (`systemd`, `libcap`, `libdrm`) are conditionally included via `lib.optionals stdenv.isLinux`

## Binaries Produced

| Binary | Description |
|---|---|
| `lemonade-server` | Backend inference server |
| `lemonade-router` | Main router / OpenAI-compatible API server (also `meta.mainProgram`) |

## Runtime Dependency

For FLM-based models, [fastflowlm-nix](https://codeberg.org/tmichnicki/fastflowlm-nix) must also be installed and on `PATH`.

## Gotchas

- **Fixed-output derivation hash updates**: When updating the version, the `lemonade-webapp` hash must be updated too. Use a fake hash, build, and copy the real one from the error. This is standard Nix practice but easy to forget.
- **Symlink dereferencing in webapp build**: The `unpackPhase` uses `cp -rL` to dereference symlinks from the Lemonade source tree (some files in `src/web-app/` are symlinks into `src/app/`). If upstream changes this structure, the build may break silently.
- **`postPatch` sed**: The path patching is fragile — if upstream renames or restructures `path_utils.cpp`, the sed will silently fail (or produce incorrect output). Verify the patch still applies after version bumps.
- **No tests**: There is no test suite in this repo. Validation is manual (`nix build` succeeds, binaries run).
- **Platforms**: Flake uses `flake-utils.lib.eachDefaultSystem` but upstream CMake has Linux-specific dependencies; macOS builds may fail at the CMake level.
- **License**: Apache 2.0 (upstream Lemonade license).

## Style Conventions

- Nix formatting follows standard conventions (2-space indentation)
- String interpolation `${...}` used throughout for derivation references
- `with pkgs;` used in `nativeBuildInputs` and `buildInputs` lists
- Comments in `flake.nix` explain non-obvious packaging decisions
