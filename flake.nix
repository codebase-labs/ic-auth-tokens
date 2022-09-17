{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dfinity-sdk = {
      url = "github:paulyoung/nixpkgs-dfinity-sdk?rev=28bb54dc1912cd723dc15f427b67c5309cfe851e";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, crane, dfinity-sdk, flake-utils, rust-overlay, ... }:
    let
      supportedSystems = [
        flake-utils.lib.system.aarch64-darwin
        flake-utils.lib.system.x86_64-darwin
      ];
    in
      flake-utils.lib.eachSystem supportedSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (final: prev: (import dfinity-sdk) final prev)
              (import rust-overlay)
            ];
          };

          dfinitySdk = (pkgs.dfinity-sdk {
            acceptLicenseAgreement = true;
            sdkSystem = system;
          }).makeVersion {
            systems = {
              "x86_64-darwin" = {
                sha256 = "sha256-5F70Hc57NSEuOadM8/ZnFXKGzBmazdU044cNpQmQhDI=";
              };
            };
            version = "0.12.0-beta.2";
          };

          rustWithWasmTarget = pkgs.rust-bin.stable.latest.default.override {
            targets = [ "wasm32-unknown-unknown" ];
          };

          # NB: we don't need to overlay our custom toolchain for the *entire*
          # pkgs (which would require rebuidling anything else which uses rust).
          # Instead, we just want to update the scope that crane will use by appending
          # our specific toolchain there.
          craneLib = (crane.mkLib pkgs).overrideToolchain rustWithWasmTarget;

          src = ./.;

          # Build *just* the cargo dependencies, so we can reuse
          # all of that work (e.g. via cachix) when running in CI
          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src;
          };

          buildRustPackage = options: craneLib.buildPackage ({
            inherit cargoArtifacts src;
            cargoBuildCommand = "cargo build --target=wasm32-unknown-unknown";
            doCheck = true;
          } // options);

          ic-auth-tokens = buildRustPackage {
            cargoExtraArgs = "--package ic-auth-tokens";
          };

          ic-auth-tokens-example = buildRustPackage {
            cargoExtraArgs = "--package ic-auth-tokens-example";
          };
        in
        {
          checks = {
            inherit ic-auth-tokens ic-auth-tokens-example;
          };

          packages = {
            inherit ic-auth-tokens ic-auth-tokens-example;
          };

          defaultPackage = ic-auth-tokens-example;

          devShell = pkgs.mkShell {
            # RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
            RUST_SRC_PATH = pkgs.rust.packages.stable.rustPlatform.rustLibSrc;
            inputsFrom = builtins.attrValues self.checks;
            nativeBuildInputs = with pkgs; [
              dfinitySdk
              rustWithWasmTarget
            ];
          };
        });
}
