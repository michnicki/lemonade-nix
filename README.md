# lemonade-nix

Nix flake for [Lemonade](https://github.com/lemonade-sdk/lemonade) — a local LLM server with GPU/NPU acceleration and an OpenAI-compatible API.

## Usage

### Run without installing

```bash
nix run git+https://codeberg.org/tmichnicki/lemonade-nix
```

### Install into a profile

```bash
nix profile install git+https://codeberg.org/tmichnicki/lemonade-nix
```

### NixOS / home-manager

Add to your flake inputs:

```nix
inputs.lemonade-nix.url = "git+https://codeberg.org/tmichnicki/lemonade-nix";
```

Then add the package:

```nix
environment.systemPackages = [ inputs.lemonade-nix.packages.${system}.default ];
```

### Development shell

```bash
nix develop
```

Includes Python 3 with `black`, `pylint`, and `requests`.

## Binaries

| Binary | Description |
|---|---|
| `lemonade-router` | Main router / OpenAI-compatible API server |
| `lemonade-server` | Backend inference server |

## Version

Currently packages Lemonade **v10.0.0**.

## License

Lemonade is licensed under the [Apache 2.0 License](https://github.com/lemonade-sdk/lemonade/blob/main/LICENSE).
