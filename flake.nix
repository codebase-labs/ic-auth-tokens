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

    ic-repl-src = {
      url = "github:chenyan2002/ic-repl";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    crane,
    dfinity-sdk,
    flake-utils,
    ic-repl-src,
    rust-overlay,
    ...
  }:
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

          ic-repl = crane.lib."${system}".buildPackage {
            src = ic-repl-src;
            nativeBuildInputs = [
              pkgs.libiconv

              # https://nixos.wiki/wiki/Rust#Building_the_openssl-sys_crate
              pkgs.openssl_1_1
              pkgs.pkgconfig
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.Security
            ];
          };

          ic-wasm = crane.lib."${system}".buildPackage {
            src = pkgs.stdenv.mkDerivation {
              name = "ic-wasm-src";
              src = pkgs.fetchFromGitHub {
                owner = "dfinity";
                repo = "ic-wasm";
                rev = "2e876e84953e24e6a1820aa524f228c8edea4307";
                sha256 = "sha256-0E7Qa0tOtFwV6pkZsjvkGE2TGaj/30+JSlNGtiU0xYo=";
              };
              installPhase = ''
                cp -R --preserve=mode,timestamps . $out
              '';
            };
            doCheck = false;
            nativeBuildInputs = [
              pkgs.libiconv
            ];
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
            cargoBuildCommand = "cargo build --profile release --target wasm32-unknown-unknown";
          } // options);

          ic-auth-tokens = buildRustPackage {
            cargoExtraArgs = "--package ic-auth-tokens";
          };

          ic-auth-tokens-example = buildRustPackage {
            cargoExtraArgs = "--package ic-auth-tokens-example";
            buildInputs = [
              ic-wasm
              pkgs.gzip
            ];
            postBuild = ''
              # find $out
              # find .
              # exit 1
              WASM=target/wasm32-unknown-unknown/release/ic_auth_tokens_example.wasm
              WASM_GZ="$WASM".gz
              ic-wasm -o "$WASM" "$WASM" shrink
              gzip --to-stdout --best "$WASM" > "$WASM_GZ"
              mkdir -p $out/lib
              cp "$WASM_GZ" $out/lib/ic_auth_tokens_example.wasm.gz
            '';
            checkInputs = [
              dfinitySdk
              ic-repl
              pkgs.jq
            ];
            checkPhase = ''
              # Stop the replica if anything goes wrong
              trap "dfx stop" EXIT

              HOME=$TMP

              jq '.canisters = (.canisters | map_values(del(.build) | .wasm = "target/wasm32-unknown-unknown/release/ic_auth_tokens_example.wasm.gz"))' dfx.json > new.dfx.json
              mv dfx.json old.dfx.json
              mv new.dfx.json dfx.json

              dfx start --background --host 127.0.0.1:0
              WEBSERVER_PORT=$(dfx info webserver-port)
              dfx deploy ic_auth_tokens_example --network "http://127.0.0.1:$WEBSERVER_PORT" --no-wallet

              ic-repl --replica "http://127.0.0.1:$WEBSERVER_PORT" examples/ic-auth-tokens-example/test.ic-repl
              dfx stop
            '';
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
