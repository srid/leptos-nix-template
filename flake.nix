{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";

    # Rust
    dream2nix.url = "github:nix-community/dream2nix";
    fenix.url = "github:nix-community/fenix";

    # Dev tools
    treefmt-nix.url = "github:numtide/treefmt-nix";
    mission-control.url = "github:Platonic-Systems/mission-control";
    flake-root.url = "github:srid/flake-root";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.dream2nix.flakeModuleBeta
        inputs.treefmt-nix.flakeModule
        inputs.mission-control.flakeModule
        inputs.flake-root.flakeModule
      ];
      perSystem = { config, self', inputs', pkgs, lib, system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            (_: super: inputs.fenix.overlays.default pkgs pkgs)
          ];
        };

        # Rust project definition
        # cf. https://github.com/nix-community/dream2nix
        dream2nix.inputs."start-axum" =
          let
            fenix = inputs.fenix.packages.${system};
            rust = fenix.complete;
            rust_targets = with fenix.targets; [
              wasm32-unknown-unknown.latest.rust-std
              x86_64-unknown-linux-musl.latest.rust-std
            ];
            toolchain = with rust; fenix.combine [
              rustc
              cargo
              clippy
              rustfmt
              rust_targets
            ];
          in
          {
            source = lib.sourceFilesBySuffices ./. [
              ".rs"
              "Cargo.toml"
              "Cargo.lock"
            ];
            projects."start-axum" = { name, ... }: {
              inherit name;
              subsystem = "rust";
              translator = "cargo-lock";
            };
            packageOverrides =
              let
                common = {
                  add-deps = with pkgs; with pkgs.darwin.apple_sdk.frameworks; {
                    nativeBuildInputs = old: old ++ lib.optionals stdenv.isDarwin [
                      libiconv
                      Security
                    ];
                  };
                };
              in
              {
                # Use Rust nightly (provided by fenix)
                "^.*".set-toolchain.overrideRustToolchain = old: {
                  cargo = toolchain;
                  rustc = toolchain;
                };

                # Project and dependency overrides:
                start-axum = common // {
                  # https://github.com/leptos-rs/start-axum/issues/14
                  disableTest = {
                    cargoTestFlags = "--no-run";
                  };
                };
                start-axum-deps = common;
              };
          };

        # Flake outputs
        # TODO: release package (and `nix run`)
        packages = config.dream2nix.outputs.start-axum.packages;
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            config.dream2nix.outputs.start-axum.devShells.default
            config.treefmt.build.devShell
            config.mission-control.devShell
            config.flake-root.devShell
          ];
          shellHook = ''
            # For rust-analyzer 'hover' tooltips to work.
            export RUST_SRC_PATH=${pkgs.rustPlatform.rustLibSrc}
          '';
          nativeBuildInputs = with pkgs; [
            cargo-watch
            rust-analyzer
            dart-sass
            cargo-leptos
          ];
        };

        # Add your auto-formatters here.
        # cf. https://numtide.github.io/treefmt/
        treefmt.config = {
          projectRootFile = "flake.nix";
          programs = {
            nixpkgs-fmt.enable = true;
            rustfmt.enable = true;
          };
        };

        # Makefile'esque but in Nix. Add your dev scripts here.
        # cf. https://github.com/Platonic-Systems/mission-control
        mission-control.scripts = {
          fmt = {
            exec = config.treefmt.build.wrapper;
            description = "Auto-format project tree";
          };

          watch = {
            exec = ''
              set -x
              cargo leptos watch "$@"
            '';
            description = "Run leptops watch";
          };

          build = {
            exec = ''
              set -x
              cargo leptos build --release "$@"
            '';
            description = "Run leptops build";
          };

        };
      };
    };
}