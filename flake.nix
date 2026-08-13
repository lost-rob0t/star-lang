{
  description = "star-lang: Common Lisp-only StarLang compiler and durable actor runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        sbcl = pkgs.sbcl.withPackages (ps: [ ps.ironclad ]);

        starLang = pkgs.stdenvNoCC.mkDerivation {
          pname = "star-lang";
          version = "0.1.0";
          src = lib.cleanSource ./.;

          strictDeps = true;
          nativeBuildInputs = [
            sbcl
            pkgs.python3
          ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild

            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            # sbcl.withPackages prepends the dependency registry and its own
            # ASDF inheritance marker; do not add a second trailing colon here.
            export CL_SOURCE_REGISTRY="$PWD//"

            sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:load-system :starlang-prototype)' \
              --eval '(format t "~&starlang-prototype loaded successfully~%")' \
              --eval '(sb-ext:quit)'

            while IFS= read -r target_system; do
              [ -n "$target_system" ] || continue
              echo "Loading $target_system"
              sbcl --non-interactive \
                --eval '(require :asdf)' \
                --eval "(asdf:load-system :$target_system)" \
                --eval '(sb-ext:quit)'
            done < ci/target-systems.txt

            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck

            source_root="$PWD"
            test_root="$TMPDIR/star-lang-tests"
            mkdir -p "$test_root"
            cd "$test_root"

            export HOME="$test_root/home"
            mkdir -p "$HOME"
            export CL_SOURCE_REGISTRY="$source_root//"

            sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:test-system :star-actor-protocol)' \
              --eval '(asdf:test-system :starlang-runtime)' \
              --eval '(asdf:test-system :star-http-port)' \
              --eval '(asdf:test-system :star-scrape)' \
              --eval '(assert (null (find-package "STAR-LANG.PROTOTYPE")))' \
              --eval '(asdf:test-system :starlang-prototype)' \
              --eval '(sb-ext:quit)'

            sbcl --script "$source_root/prototype/run-star.lisp" \
              load "$source_root/fixtures/star-cl-constructors.star" \
              --runtime-compiler eval \
              --cache "$test_root/cli-cache"

            cd "$source_root"
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall

            source_root="$out/share/common-lisp/source/star-lang"
            mkdir -p "$source_root" "$out/bin"
            cp -R "$src"/. "$source_root/"

            cat > "$out/bin/starlang" <<EOF
            #!${pkgs.runtimeShell}
            set -euo pipefail

            source_root="$out/share/common-lisp/source/star-lang"
            export CL_SOURCE_REGISTRY="\$source_root//"

            exec ${sbcl}/bin/sbcl \
              --script "\$source_root/prototype/run-star.lisp" \
              "\$@"
            EOF

            cat > "$out/bin/starlang-test" <<EOF
            #!${pkgs.runtimeShell}
            set -euo pipefail

            source_root="$out/share/common-lisp/source/star-lang"
            test_root="\$(${pkgs.coreutils}/bin/mktemp -d)"
            trap '${pkgs.coreutils}/bin/rm -rf "\$test_root"' EXIT

            export HOME="\$test_root/home"
            ${pkgs.coreutils}/bin/mkdir -p "\$HOME"
            export CL_SOURCE_REGISTRY="\$source_root//"
            cd "\$test_root"

            ${sbcl}/bin/sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:test-system :star-actor-protocol)' \
              --eval '(asdf:test-system :starlang-runtime)' \
              --eval '(asdf:test-system :star-http-port)' \
              --eval '(asdf:test-system :star-scrape)' \
              --eval '(assert (null (find-package "STAR-LANG.PROTOTYPE")))' \
              --eval '(asdf:test-system :starlang-prototype)' \
              --eval '(sb-ext:quit)'
            EOF

            chmod +x "$out/bin/starlang" "$out/bin/starlang-test"

            runHook postInstall
          '';

          meta = {
            description = "Common Lisp StarLang compiler and durable actor runtime";
            homepage = "https://github.com/lost-rob0t/star-lang";
            license = lib.licenses.agpl3Only;
            mainProgram = "starlang";
            platforms = lib.platforms.unix;
          };
        };
      in
      {
        packages = {
          default = starLang;
          star-lang = starLang;
        };

        apps = {
          default = {
            type = "app";
            program = "${starLang}/bin/starlang";
          };
          tests = {
            type = "app";
            program = "${starLang}/bin/starlang-test";
          };
        };

        checks.default = starLang;

        devShells.default = pkgs.mkShell {
          packages = [
            sbcl
            pkgs.git
            pkgs.python3
          ] ++ lib.optional (pkgs ? roswell) pkgs.roswell;

          shellHook = ''
            export CL_SOURCE_REGISTRY="$PWD//"
            echo "star-lang dev shell: $(sbcl --version)"
            echo "Build: nix build"
            echo "Run: nix run"
            echo "Test: nix run .#tests"
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
