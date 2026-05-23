# lemonade-nix

Nix flake for [Lemonade](https://github.com/lemonade-sdk/lemonade) — a local LLM server with GPU/NPU acceleration, an OpenAI-compatible API, and a built-in React web UI.

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
| `lemonade` | CLI for managing and interacting with the server |
| `lemond` | Main server daemon (OpenAI-compatible API) |
| `lemonade-server` | Legacy compatibility shim |

## Dependencies

For FLM-based models, [fastflowlm-nix](https://codeberg.org/tmichnicki/fastflowlm-nix) must also be installed and available on `PATH`.

## Web UI

The package includes the Lemonade web app. Once `lemond` is running, open [http://localhost:13305](http://localhost:13305) in your browser to access the chat interface.

## What's New in v10.2.0

*   **Embeddable Lemonade**: Portable binaries designed for bundling into other applications.
*   **Expanded Model Support**: Support for **Qwen Image** models and improved integration for GGUF and RAI models.
*   **`lemonade pull` Enhancements**: Smarter automatic detection of checkpoints, recipes, and labels.
*   **OpenCode Integration**: New integration accessible via `lemonade launch opencode`.
*   **Hardware Reporting**: Improved device type detection for `llamacpp` and `whispercpp` backends.

## Version

Currently packages Lemonade **v10.6.0**.

## License

Lemonade is licensed under the [Apache 2.0 License](https://github.com/lemonade-sdk/lemonade/blob/main/LICENSE).
