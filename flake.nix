{
  description = "R + Bayesian + Quarto development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { nixpkgs, nixpkgs-stable, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          pkgs-stable = import nixpkgs-stable { inherit system; };
          # Keep the working httpgd source from stable, using the current R and
          # dependencies. Mixing the two compiled R package sets is unsafe.
          httpgd = (pkgs.rPackages.buildRPackage {
            name = "httpgd";
            version = "2.0.3";
            src = pkgs-stable.rPackages.httpgd.src;
            propagatedBuildInputs = with pkgs.rPackages; [ AsioHeaders cpp11 unigd ];
            meta = pkgs-stable.rPackages.httpgd.meta;
          }).overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
            buildInputs = old.buildInputs ++ [ pkgs.cairo.dev ];
          });

          cmdstanr = pkgs.rPackages.buildRPackage {
            name = "cmdstanr";
            version = "0.9.0";

            # R-universe repacks old releases, which invalidates fixed hashes.
            src = pkgs.fetchurl {
              name = "cmdstanr-0.9.0.tar.gz";
              url = "https://codeload.github.com/stan-dev/cmdstanr/tar.gz/da99e2ba954658bdad63bffb738c4444c33a4e0e";
              hash = "sha256-ufxMGYbswvnmADbSBxzQRQpg19BS6SF3slRvnUqu6NU=";
            };

            # CmdStanR 0.9.0 hand-quotes CSV paths in shell commands. Let R
            # escape them so output paths such as "Tong's projects" work.
            postPatch = ''
              substituteInPlace R/csv.R \
                --replace-fail \
                ${pkgs.lib.escapeShellArg ''fread_cmd <- paste0("grep -v '^#' --color=never '", output_file, "'")''} \
                ${pkgs.lib.escapeShellArg ''fread_cmd <- paste("grep -v '^#' --color=never --", shQuote(output_file))''} \
                --replace-fail \
                ${pkgs.lib.escapeShellArg ''fread_cmd <- paste0("grep '^[#a-zA-Z]' --color=never '", path.expand(csv_file), "'")''} \
                ${pkgs.lib.escapeShellArg ''fread_cmd <- paste("grep '^[#a-zA-Z]' --color=never --", shQuote(path.expand(csv_file)))''}
            '';

            propagatedBuildInputs = with pkgs.rPackages; [
              checkmate data_table jsonlite posterior processx R6 withr rlang
            ];

            doCheck = false;
            R_BUILD_ARGS = [ "--no-build-vignettes" ];
            R_CHECK_ARGS = [ "--ignore-vignettes" "--no-manual" ];

            meta = {
              description = "R interface to CmdStan";
              license = pkgs.lib.licenses.bsd3;
              platforms = pkgs.lib.platforms.unix;
            };
          };

          rPackages = with pkgs.rPackages; [
            languageserver devtools arrow
            tidyverse cowplot ggplot2 systemfonts patchwork ggh4x
            flextable posterior tidybayes cmdstanr Hmisc
            crew crew_cluster targets tarchetypes checkmate
            httpgd
          ];
        in {
          default = pkgs.mkShell {
            name = "r-bayes-quarto-dev";

            packages = [ pkgs.R pkgs.cmdstan pkgs.radian pkgs.quarto ] ++ rPackages;

            env = rec {
              R_BIN = "${pkgs.R}/bin/R";
              RADIAN_BIN = "${pkgs.radian}/bin/radian";
              QUARTO_R = R_BIN;
              QUARTO_PANDOC = "${pkgs.pandoc}/bin/pandoc";
            };

            shellHook = ''
              if [ -n "''${BELZ_EECS_PROJECT_ROOT:-}" ]; then
                cd "$BELZ_EECS_PROJECT_ROOT" || exit 1
              fi
              export QUARTO_PROJECT_DIR="$PWD"

              # CmdStan writes build products into its installation directory.
              # Use a writable cache outside the repo (whose path may have spaces).
              cmdstan_cache_root="/tmp/belz-eecs-poster-rating-$(id -u)"
              export CMDSTAN="$cmdstan_cache_root/${baseNameOf (toString pkgs.cmdstan)}"
              if [ ! -f "$CMDSTAN/.nix-dev-shell-ready" ]; then
                mkdir -p "$cmdstan_cache_root" || exit 1
                cmdstan_stage=$(mktemp -d "$cmdstan_cache_root/.cmdstan.XXXXXXXX") || exit 1
                if cp -R "${pkgs.cmdstan}/opt/cmdstan/." "$cmdstan_stage/" &&
                   chmod -R u+w "$cmdstan_stage"; then
                  # Store PCH files embed their original build paths. Compile
                  # models with the shell's compiler without reusing those PCHs.
                  cat > "$cmdstan_stage/make/local" <<'MAKE_LOCAL'
              CXX = ${pkgs.stdenv.cc}/bin/c++
              PRECOMPILED_HEADERS = false
              MAKE_LOCAL
                  touch "$cmdstan_stage/.nix-dev-shell-ready"
                  if [ ! -e "$CMDSTAN" ]; then
                    mv "$cmdstan_stage" "$CMDSTAN" || exit 1
                  else
                    rm -rf "$cmdstan_stage"
                  fi
                else
                  rm -rf "$cmdstan_stage"
                  echo "Could not prepare writable CmdStan at $CMDSTAN" >&2
                  exit 1
                fi
              fi
              unset cmdstan_cache_root cmdstan_stage
            '';
          };
        });
    };
}
