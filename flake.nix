{
  nixConfig.bash-prompt-prefix = ''\[\e[0;31m\](löve) \e[0m'';

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [(import inputs.rust-overlay)];
        };

        pname = "balatro";
        version = "1.0.1o";
        drv = pkgs.stdenv.mkDerivation {
          inherit pname;
          version = version;
          src = ./Balatro.exe;

          dontUnpack = true;
          doCheck = false;

          nativeBuildInputs = with pkgs; [p7zip copyDesktopItems makeWrapper];
          buildInputs = [pkgs.love];

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
            cat ${pkgs.lib.getExe pkgs.love} $balatro_bundle \
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

        lovely-injector = let
          src = pkgs.fetchFromGitHub {
            fetchSubmodules = true;
            owner = "janw4ld";
            repo = "lovely-injector";
            rev = "ada045e30bb1788b6606a31ef6c7d21682051c60";
            hash = "sha256-bzCY86gfAKDF+0uFZRqMlmJDxJF7y8t+EUAUqgl6lSs=";
          };

          rustPlatform = let
            rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile (src + /rust-toolchain.toml);
          in
            pkgs.makeRustPlatform {
              cargo = rust-toolchain;
              rustc = rust-toolchain;
            };

          cargo-toml = pkgs.lib.importTOML (src + /crates/lovely-unix/Cargo.toml);
          pname = cargo-toml.package.name;
          version = cargo-toml.package.version;
        in
          rustPlatform.buildRustPackage {
            inherit src pname version;

            doCheck = false;

            useFetchCargoVendor = true;
            cargoLock = {
              lockFile = src + /Cargo.lock;
              outputHashes."retour-0.4.0-alpha.2" = "sha256-GtLTjErXJIYXQaOFLfMgXb8N+oyHNXGTBD0UeyvbjrA=";
            };
            cargoBuildFlags = ["--package" "lovely-unix"];

            nativeBuildInputs = with pkgs; [cmake];

            env = {
              RUSTC_BOOTSTRAP = 1; # nightly rust features
              RUST_BACKTRACE = 1;
            };
          };
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
