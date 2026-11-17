{
  description = "R + Bayesian + Quarto dev environment (from devbox.json)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs, nixpkgs-stable }:
    let
      system = "x86_64-linux"; # Change if needed
      pkgs = import nixpkgs { inherit system; };
      pkgs-stable = import nixpkgs-stable { inherit system; };
      cmdstanr_manual = pkgs.rPackages.buildRPackage rec {
          name = "cmdstanr";
          version = "0.9.0";

          src = pkgs.fetchurl {
            url = "https://stan-dev.r-universe.dev/src/contrib/${name}_${version}.tar.gz";
            # run: nix-prefetch-url --unpack <url>
            hash = "sha256-pURkVHB6RSbzLC9oA2BZvLxDarqiFvxmSnXiFt2aDtA=";
          };

          propagatedBuildInputs = with pkgs.rPackages; [
            checkmate
            data_table
            jsonlite
            posterior
            processx
            R6
            withr
            rlang
            qpdf
          ];

          # keep builds fast & avoid pandoc/tex
          doCheck = false;
          R_BUILD_ARGS = [ "--no-build-vignettes" ];
          R_CHECK_ARGS = [ "--ignore-vignettes" "--no-manual" ];

          meta = with pkgs.lib; {
            description = "R interface to CmdStan";
            license = licenses.bsd3;
            platforms = platforms.unix;
          };
        };

      myRPkgs = with pkgs.rPackages; [
        languageserver
        devtools
        arrow

        tidyverse
        cowplot
        ggplot2
        systemfonts
        patchwork
        ggh4x

        # gt
        # kableExtra
        # formattable # Not sure about non-html output
        flextable
        # tinytable # Looks good but happy with flextable for now

        # rstan
        posterior
        tidybayes
        cmdstanr_manual # built above #

        Hmisc
        
        crew
        crew_cluster
        targets
        tarchetypes

        checkmate
      ] ++ [
        # marked as broken in unstable
        pkgs-stable.rPackages.httpgd
        ];
    in {
      devShells.${system}.default = pkgs.mkShell {

        name = "r-bayes-quarto-dev";

        # Could rewrite using rWrapper; radianWrapper
        packages = [
          pkgs.R
          pkgs.cmdstan
          pkgs.radian
          pkgs.quarto
        ] ++ myRPkgs;

        env = rec {
          QUARTO_PROJECT_DIR = "$PWD";
          R_BIN = "${pkgs.R.outPath}/bin/R";
          RADIAN_BIN = "${pkgs.radian.outPath}/bin/radian";
          QUARTO_R = R_BIN;
          QUARTO_PANDOC = "${pkgs.pandoc}/bin/pandoc";
          CMDSTAN = "${pkgs.cmdstan}/opt/cmdstan";
        };

        shellHook = ''
          tmpfile=$(mktemp)
          cat .vscode/settings.json |
              jq '."r.rterm.linux" = env.RADIAN_BIN | ."r.rpath.linux" = env.R_BIN' > \
              $tmpfile
          mv $tmpfile .vscode/settings.json
          echo 'Welcome to R Bayes + Quarto dev environment' > /dev/null
        '';
      };
    };
}

