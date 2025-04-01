{
  nixConfig.bash-prompt-prefix = ''\[\e[0;31m\](löve) \e[0m'';

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = inputs.nixpkgs.legacyPackages.${system};

        pname = "balatro";
        version = "1.0.1o";
        drv = pkgs.stdenv.mkDerivation {
          inherit pname;
          version = version;
          src = ./Balatro.exe;
          /*
          # or to build from source
          with pkgs.lib.fileset;
          toSource {
            root = ./.;
            fileset = fileFilter (f:
              builtins.foldl' (acc: it: acc || f.hasExt it) false
              ["lua" "png" "ogg" "fs" "ttf" "jkr" "txt"])
            ./src;
          };
          */

          dontUnpack = true;

          nativeBuildInputs = with pkgs; [p7zip copyDesktopItems makeWrapper];
          buildInputs = [love];

          buildPhase = ''
            runHook preBuild

            tmpdir=$(mktemp -d)
            7z x $src -o$tmpdir -y
            (cd $tmpdir && {
              for i in ${./patches}/*.patch; do
                patch -p1 -uNi "$i"
              done
            })
            balatro_bundle=$(mktemp -u).zip
            7z a $balatro_bundle $tmpdir/*

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            install -Dm444 $tmpdir/resources/textures/2x/balatro.png -t $out/share/icons/
            # just concat the löve executable with the game source zip
            cat ${pkgs.lib.getExe love} $balatro_bundle \
              > $out/share/Balatro
            chmod +x $out/share/Balatro

            mkdir -p $out/bin
            ln -s $out/share/Balatro $out/bin/Balatro.exe

            runHook postInstall
          '';

          meta.mainProgram = "Balatro.exe";
          desktopItems = [
            (pkgs.makeDesktopItem {
              name = "balatro";
              desktopName = "Balatro";
              exec = "Balatro.exe";
              keywords = ["Game"];
              categories = ["Game"];
              icon = "balatro";
            })
          ];
        };

        love =
          pkgs.love
          /*
          # lovely's developer says it can 2x the score calculation speed
          .override {luajit = pkgs.luajit_openresty;}
          */
          ;

        lovely-injector = pkgs.rustPlatform.buildRustPackage (let
          v = "0.7.1-dirty";
        in {
          pname = "lovely-injector";
          version = v;
          src = pkgs.fetchFromGitHub {
            owner = "ethangreen-dev";
            repo = "lovely-injector";
            # not yet released fixes for stdout/stderr bugs
            rev = "23620198270c2d2bad2cf4ccc7061d9e2f032235";
            hash = "sha256-Rhf61yrQnCaNa2vpczqFeO8/lnNEXFr9ADjBfd5kfQw=";
          };

          useFetchCargoVendor = true;
          cargoHash = "sha256-hHq26kSKcqEldxUb6bn1laTpKGFplP9/2uogsal8T5A=";
          cargoBuildFlags = ["--package" "lovely-unix"];

          doCheck = false;
          env.RUSTC_BOOTSTRAP = 1; # nightly rust features
        });
      in {
        packages = rec {
          default = lovely;

          vanilla = drv;

          bundle = vanilla.overrideAttrs (_: {
            version = version + "-bundle";
            installPhase = ''install -Dm644 $balatro_bundle $out/Balatro.love'';
          });

          lovely = vanilla.overrideAttrs (old: {
            version = version + "+lovely";
            buildInputs = old.buildInputs ++ [lovely-injector];
            postInstall = ''
              rm -rf $out/bin/Balatro.exe
              makeWrapper $out/share/Balatro $out/bin/Balatro.exe \
                --prefix LD_PRELOAD : '${lovely-injector}/lib/liblovely.so'
            '';
          });
        };

        devShell = pkgs.mkShell {
          inputsFrom = pkgs.lib.attrValues inputs.self.packages.${system};
          packages = with pkgs; [luajit];
          shellHook = ''echo "with löve from wrd :)"'';
        };
      }
    );
}
