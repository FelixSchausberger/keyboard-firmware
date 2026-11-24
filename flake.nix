{
  description = "Keyboard firmware: Keychron K6 HE and Corne V4.1";

  # Nix configuration for public caches (avoids requiring personal cachix credentials)
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # The vial fork of qmk, stores the keyboard config in on-keyboard memory, and
    # supports the `Vial` GUI key map config app.
    vial-qmk = {
      url = "github:vial-kb/vial-qmk/vial";
      flake = false;
    };

    # Keychron's QMK fork carries the HE (analog matrix), wireless and RGB
    # drivers for the K6 HE. The input is pinned by revision only; the
    # submodules are fetched in the firmware derivation as a fixed-output
    # source, so the flake input's NAR hash does not depend on the Nix
    # version used to lock it.
    keychron-qmk = {
      url = "github:Keychron/qmk_firmware/2025q3";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    nixos-unstable,
    vial-qmk,
    keychron-qmk,
    flake-utils,
    ...
  }:
  # This effectively appends `.x86_64-linux` to the attributes returned
  # by the function passed in. The `system` parameter is also that string.
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux"] (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            # Add unstable packages
            (_final: prev: {
              unstable = nixos-unstable.legacyPackages."${prev.system}";
            })

            # Use python3.11 for compatibility with QMK
            (final: _prev: {
              python3 = final.python311;
              python3Packages = final.python311.pkgs;
            })
          ];
        };
        inherit (pkgs) lib;

        unstable = nixos-unstable.legacyPackages.${system};

        mkQmkFirmware = pkgs.callPackage ./lib/mkQmkFirmware.nix {
          inherit (unstable) qmk;
        };

        k6he = import ./keyboards/k6he/keyboard.nix {
          inherit pkgs keychron-qmk mkQmkFirmware;
        };

        flashK6he = pkgs.writeShellApplication {
          name = "flash-k6he";
          runtimeInputs = with pkgs; [dfu-util coreutils findutils gnugrep];
          text = ''
            set -eu

            usage() {
              cat <<'EOF'
            Flash a Keychron K6 HE firmware image over STM32 DFU.

            Usage: flash-k6he [--help] [path/to/firmware.bin]

            Without a path, the newest result/*.bin from `nix build .#k6he` is used.

            Bootloader entry:
              1. Set the mode switch to Cable.
              2. Disconnect USB-C.
              3. Hold Esc (or press the reset button under the space bar) and plug
                 USB-C in. The keyboard enumerates as STM32 DFU (0483:df11).

            The script refuses to run unless exactly one STM32 DFU device is present.
            It never guesses between multiple boards.

            Rollback: use the firmware update in Keychron Launcher to restore the
            stock firmware before flashing a custom image.
            EOF
            }

            if [ "''${1:-}" = "--help" ] || [ "''${1:-}" = "-h" ]; then
              usage
              exit 0
            fi

            artifact="''${1:-}"
            if [ -z "$artifact" ]; then
              artifact="$(find result/ -maxdepth 1 -type f -name '*.bin' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2- || true)"
            fi
            if [ -z "$artifact" ] || [ ! -f "$artifact" ]; then
              echo "no firmware .bin found; run 'nix build .#k6he' first or pass a path" >&2
              exit 1
            fi

            mapfile -t devices < <(dfu-util -l 2>/dev/null | grep -E '0483:df11' | grep -o 'serial="[^"]*"' | sort -u)
            if [ "''${#devices[@]}" -ne 1 ]; then
              echo "expected exactly one STM32 DFU device (0483:df11), found ''${#devices[@]}" >&2
              dfu-util -l >&2 || true
              exit 1
            fi

            dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D "$artifact"
          '';
        };
      in {
        # Development shell for building firmware
        devShells.default = pkgs.mkShell {
          # Corne V4.1 specific configuration
          KEYBOARD = "crkbd/rev4_1/standard"; # ✅ Correct for Corne V4.1 (46 keys)
          KEYMAP = "custom_hrmods"; # Custom keymap with RGB indicators and home row mod fixes

          # Enhanced build configuration
          VIAL_QMK_DIR = "${vial-qmk}";

          # SSL certificate configuration (required for prek and git operations)
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

          # Build inputs with additional tools
          # Split into CI-required (always) and dev-only (local development)
          buildInputs = with pkgs;
            [
              # Core firmware build tools (needed in CI)
              cacert # SSL certificates for git operations
              qmk
              unstable.vial
              dfu-util # For flashing via DFU
              avrdude # For AVR microcontrollers
              gcc-arm-embedded # For ARM microcontrollers
              python3 # QMK requirements
              python3Packages.setuptools

              # QMK Python dependencies
              unstable.python3Packages.milc # Need >= 1.9.0 for via2json
              python3Packages.dotty-dict
              python3Packages.hid
              python3Packages.hjson
              python3Packages.jsonschema
              python3Packages.pyusb
              python3Packages.argcomplete
              python3Packages.platformdirs # MILC dependency
              python3Packages.appdirs # Legacy MILC dependency
              python3Packages.pyyaml # YAML parsing for pre-commit hooks
              git # For QMK setup
              which # Build dependency
              gnumake # Build system

              # Additional utilities (needed in CI for layout generation)
              jq # JSON processing for layout files
              unstable.keymap-drawer # Layout visualization tool
              librsvg # SVG to PDF conversion (rsvg-convert command)

              # Rust tool: VIAL to QMK JSON converter (needed in CI)
              (pkgs.rustPlatform.buildRustPackage {
                pname = "vil2json";
                version = "0.1.0";
                src = ./tools/vil2json;
                cargoLock.lockFile = ./tools/vil2json/Cargo.lock;
              })
            ]
            ++ lib.optionals (builtins.getEnv "CI" != "true") [
              # Development-only tools (NOT in CI - saves ~5-8GB disk space)
              # GitHub Actions CI uses j178/prek-action instead of nix prek
              unstable.prek # Pre-commit hook manager (meta-tool, Rust-based, heavy build)
              alejandra # Nix formatter (prek)
              deadnix # Remove unused Nix code (prek)
              statix # Nix linter (prek)
              unstable.flake-checker # Flake validation (prek)
              yamlfmt # YAML formatter (prek)
              taplo # TOML formatter (prek)
              nodePackages.prettier # JSON/YAML/Markdown formatter (prek)
              ripsecrets # Secret detection (prek)
              act # Local GitHub Actions runner
              nodePackages.markdownlint-cli # Markdown linting
              yamllint # YAML validation
            ];

          # Alias commands for building and flashing
          shellHook = ''
            # SSL certificates for git/curl operations (required for prek)
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export NIX_SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export GIT_SSL_CAINFO="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            export CURL_CA_BUNDLE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

            # Unset any conflicting git config (let environment variables take precedence)
            git config --global --unset http.sslCAInfo 2>/dev/null || true

            # Ensure QMK is properly configured
            export QMK_HOME="${vial-qmk}"

            # Add scripts directory to PATH for easy command access
            export PATH="$(pwd)/scripts:$PATH"
            export LOCAL_QMK_DIR="$(pwd)/vendor/vial-qmk"
            export LOCAL_QMK_SOURCE_MARKER="$LOCAL_QMK_DIR/.source-path"
            unalias build 2>/dev/null || true
            alias build="$(pwd)/scripts/build"

            _ensure_qmk_local() {
              if [ ! -d "$LOCAL_QMK_DIR" ] || [ ! -f "$LOCAL_QMK_SOURCE_MARKER" ] || [ "$(cat "$LOCAL_QMK_SOURCE_MARKER" 2>/dev/null)" != "${vial-qmk}" ]; then
                rm -rf "$LOCAL_QMK_DIR"
                mkdir -p "$LOCAL_QMK_DIR"
                cp -R ${vial-qmk}/. "$LOCAL_QMK_DIR"/
                echo "${vial-qmk}" > "$LOCAL_QMK_SOURCE_MARKER"
              fi
              chmod -R u+w "$LOCAL_QMK_DIR"
            }

            # Simple build commands (fish-compatible)
            # Copy custom keymap to vial-qmk before flashing
            _copy_keymap() {
              _ensure_qmk_local
              local keyboard_root="$${KEYBOARD%%/*}"
              local src="keyboards/$${keyboard_root}/keymaps/$${KEYMAP}"
              local target="$LOCAL_QMK_DIR/keyboards/$${KEYBOARD}/keymaps"
              mkdir -p "$target"
              cp -r "$src" "$target/" 2>/dev/null || true
              echo "✓ Custom keymap copied to QMK source"
            }
            alias flash='_copy_keymap && make -C $LOCAL_QMK_DIR BUILD_DIR=$(pwd)/build COPY=echo -j$(nproc) $KEYBOARD:$KEYMAP:flash'
            alias clean='rm -rf build/ && echo "Build directory cleaned"'
            alias copy-uf2='cp build/*.uf2 firmware/ 2>/dev/null && echo "UF2 copied to firmware/" || echo "No UF2 files found"'

            # Environment setup
            echo "Corne V4.1 Vial-QMK Build Environment Ready"
            echo "==========================================="
            echo ""
            echo "Configuration:"
            echo "  Keyboard: \$KEYBOARD"
            echo "  Keymap:   \$KEYMAP"
            echo "  QMK Dir:  \$QMK_HOME"
            echo ""
            echo "Available commands:"
            echo ""
            echo "Build Commands:"
            echo "  build            - Build firmware (.uf2 file)"
            echo "  flash            - Build and flash firmware"
            echo "  clean            - Clean build directory"
            echo "  copy-uf2         - Copy built UF2 to firmware/"
            echo ""
            echo "Testing Commands:"
            echo "  test-all.sh      - Run complete test suite"
            echo "  test-layouts.sh  - Validate VIAL layout files"
            echo "  test-configs.sh  - Validate Nix configurations"
            echo "  act-check.sh     - Run firmware CI locally"
            echo ""
            echo "Code Quality:"
            echo "  prek run --all-files  - Run all code quality checks"
            echo "  prek run --fail-fast  - Run checks, stop on first failure"
            echo "  alejandra .           - Format Nix files"
            echo "  deadnix .             - Remove unused Nix code"
            echo "  statix check .        - Lint Nix files"
            echo "  yamlfmt .             - Format YAML files"
            echo ""
            echo "Utility Commands:"
            echo "  keymap           - Generate layout images from YAML files"
            echo "  validate-vial.sh - Manual VIAL file validation"
            echo ""
            echo "Build process:"
            echo "  1. Run 'build' to compile firmware"
            echo "  2. Put keyboard in bootloader mode"
            echo "  3. Copy .uf2 file to mounted drive"
            echo ""

            # Verify keyboard configuration exists
            if [ -d "${vial-qmk}/keyboards/crkbd/rev4_1/standard" ]; then
              echo "✅ Corne V4.1 keyboard configuration found"
            else
              echo "❌ Corne V4.1 keyboard configuration NOT found"
            fi
            echo ""
          '';

          # Additional environment variables
          NIX_SHELL_PRESERVE_PROMPT = "1";
        };

        # Formatter for the flake
        formatter = pkgs.alejandra;

        packages = {
          k6he = k6he.qwerty;
          k6he-colemak = k6he.colemak;
          default = k6he.qwerty;
        };

        apps = {
          flash-k6he = {
            type = "app";
            program = "${flashK6he}/bin/flash-k6he";
          };
        };
      }
    );
}
