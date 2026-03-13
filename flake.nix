{
  description = "Lemonade - Local LLM server with GPU/NPU acceleration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        version = "10.0.0";

        lemonade-src = pkgs.fetchFromGitHub {
          owner = "lemonade-sdk";
          repo = "lemonade";
          rev = "v${version}";
          hash = "sha256-PT3HzdQy+Zc2Y7uutgU62uvhA1w6V37UyrcFqCezM80=";
        };

        # cpp-httplib is not packaged in nixpkgs; pre-fetch for FetchContent.
        cpp-httplib-src = pkgs.fetchFromGitHub {
          owner = "yhirose";
          repo = "cpp-httplib";
          rev = "v0.26.0";
          hash = "sha256-+VPebnFMGNyChM20q4Z+kVOyI/qDLQjRsaGS0vo8kDM=";
        };

        # IXWebSocket is always fetched via FetchContent on Linux (no find_package fallback).
        ixwebsocket-src = pkgs.fetchFromGitHub {
          owner = "machinezone";
          repo = "IXWebSocket";
          rev = "v11.4.4";
          hash = "sha256-BLvZBZA9wTvzDuUFXT0YQAEuQxeGyRPxCLuFS4xrknI=";
        };

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "lemonade";
          inherit version;

          src = lemonade-src;

          nativeBuildInputs = with pkgs; [
            cmake
            ninja
            pkg-config
          ];

          buildInputs = with pkgs; [
            nlohmann_json
            cli11
            curl
            zstd
            openssl
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            systemd
            libcap
            libdrm
          ];

          postPatch = ''
            # Make resource lookup work for FHS install layout:
            # binary at $prefix/bin/, resources at $prefix/share/lemonade-server/
            sed -i 's|std::vector<std::string> install_prefixes = {|std::vector<std::string> install_prefixes = {\n        (exe_dir.parent_path() / "share" / "lemonade-server").string(),|' \
              src/cpp/server/utils/path_utils.cpp
          '';

          cmakeFlags = [
            "-DBUILD_WEB_APP=OFF"
            # Pre-fetched sources for dependencies not available via pkg-config/find_package
            "-DFETCHCONTENT_SOURCE_DIR_HTTPLIB=${cpp-httplib-src}"
            "-DFETCHCONTENT_SOURCE_DIR_IXWEBSOCKET=${ixwebsocket-src}"
          ];

          installPhase = ''
            runHook preInstall
            install -Dm755 lemonade-router $out/bin/lemonade-router
            install -Dm755 lemonade-server $out/bin/lemonade-server
            # Resources are looked up relative to the binary's parent directory
            mkdir -p $out/share/lemonade-server
            cp -r resources $out/share/lemonade-server/
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Local LLM server with GPU/NPU acceleration (OpenAI-compatible API)";
            homepage = "https://github.com/lemonade-sdk/lemonade";
            license = licenses.asl20;
            mainProgram = "lemonade-router";
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
          packages = with pkgs; [
            python3
            python3Packages.black
            python3Packages.pylint
            python3Packages.requests
          ];
        };
      }
    );
}
