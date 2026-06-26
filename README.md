# lemonade-nix

Nix flake for [Lemonade](https://github.com/lemonade-sdk/lemonade), a local LLM server with GPU/NPU acceleration, an OpenAI-compatible API, and a bundled React web UI.

## Package Summary

| Field | Value |
|---|---|
| Upstream | [lemonade-sdk/lemonade](https://github.com/lemonade-sdk/lemonade) |
| Packaged version | Lemonade **v10.8.1** |
| Main programs | `lemonade`, `lemond` |
| Supported systems | Linux and Darwin |
| Flake outputs | `packages.${system}.default`, `devShells.${system}.default` |

## Requirements

- Nix with flakes enabled.
- For FLM-based models, [fastflowlm-nix](https://github.com/michnicki/fastflowlm-nix) must also be installed and available on `PATH`.

## Usage

### Run without installing

```bash
nix run github:michnicki/lemonade-nix -- --help
```

### Build

```bash
nix build github:michnicki/lemonade-nix
```

### Install into a profile

```bash
nix profile install github:michnicki/lemonade-nix
```

### Use in a NixOS or home-manager module

After adding `inputs.lemonade-nix.url = "github:michnicki/lemonade-nix";` to your flake, add the package to your module:

```nix
{ inputs, pkgs, ... }: {
  environment.systemPackages = [
    inputs.lemonade-nix.packages.${pkgs.system}.default
  ];
}
```

For home-manager, add the same package to `home.packages`.

### Web UI

The package includes the Lemonade web app. Once `lemond` is running, open [http://localhost:13305](http://localhost:13305) to use the chat interface.

## Development

Enter the development shell to get Python 3 with `black`, `pylint`, and `requests`:

```bash
nix develop github:michnicki/lemonade-nix
```

## Updating

To bump to a new upstream release:

1. Set `version` in `flake.nix` to the new tag (without the leading `v`).
2. Refresh `lemonade-src.hash` — set it to a fake hash, run `nix build`, and copy the real hash from the error.
3. Refresh the `lemonade-webapp` `outputHash` the same way.
4. Run `nix build` to verify, then update the version reference above.

A non-routine bump (renamed binary, a new bundled dependency pulled in via `FetchContent`, or a changed build layout) may also need edits to `buildInputs`, `postPatch`, or `installPhase`.

## License

Lemonade is licensed under Apache 2.0. See the [upstream license](https://github.com/lemonade-sdk/lemonade/blob/main/LICENSE).
