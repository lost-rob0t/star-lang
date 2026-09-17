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
        swipl = pkgs.swi-prolog;

        # The nixpkgs Common Lisp snapshot predates Sento's current remoting
        # stack. Keep the pinned backend closure in one focused module.
        sentoRemoting = import ./nix/sento-remoting.nix { inherit pkgs; };
        sbcl = pkgs.sbcl.withPackages (ps: [
          ps.babel
          ps.dexador
          ps.fiveam
          ps.ironclad
          ps.usocket
          ps.yason
          (sentoRemoting ps)
        ]);

        starLang = pkgs.stdenvNoCC.mkDerivation {
          pname = "star-lang";
          version = "0.2.0";
          src = lib.cleanSource ./.;

          strictDeps = true;
          nativeBuildInputs = [
            sbcl
            swipl
            pkgs.python3
          ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild

            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export CL_SOURCE_REGISTRY="$PWD//"
            export STARLANG_SWI_EXECUTABLE="${swipl}/bin/swipl"

            while IFS= read -r target_system; do
              [ -n "$target_system" ] || continue
              echo "Loading $target_system"
              sbcl --non-interactive \
                --eval '(require :asdf)' \
                --eval "(asdf:load-system :$target_system)" \
                --eval '(assert (null (find-package "STAR-LANG.PROTOTYPE")))' \
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
            export STARLANG_SWI_EXECUTABLE="${swipl}/bin/swipl"

            sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:test-system :star-actor-protocol)' \
              --eval '(asdf:test-system :star-canonical-json)' \
              --eval '(asdf:test-system :star-journal)' \
              --eval '(asdf:test-system :star-lease)' \
              --eval '(asdf:test-system :starlang-runtime)' \
              --eval '(asdf:test-system :star-sento-compat)' \
              --eval '(asdf:test-system :star-http-port)' \
              --eval '(asdf:test-system :star-http-dexador-tests)' \
              --eval '(asdf:test-system :star-scrape)' \
              --eval '(asdf:test-system :star-process-port)' \
              --eval '(asdf:test-system :star-logic-protocol)' \
              --eval '(asdf:test-system :star-logic-ir)' \
              --eval '(asdf:test-system :starlang-compiler)' \
              --eval '(asdf:test-system :starlang-loader)' \
              --eval '(asdf:test-system :starlang-cli)' \
              --eval '(asdf:test-system :star-logic-adapter-swi)' \
              --eval '(assert (find-package "STAR-LANG.LOADER"))' \
              --eval '(assert (null (find-package "STAR-LANG.PROTOTYPE")))' \
              --eval '(sb-ext:quit)'

            timeout 120 sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:test-system :star-sento-compat-integration-tests)' \
              --eval '(sb-ext:quit)'

            bash "$source_root/ci/check-swi-adapter-contracts.sh"
            bash "$source_root/ci/check-final-authority.sh"

            sbcl --script "$source_root/starlang-cli/starlang-cli.lisp" version
            sbcl --script "$source_root/starlang-cli/starlang-cli.lisp" \
              check "$source_root/fixtures/actor-compiler/enrichment-worker.star"
            sbcl --script "$source_root/starlang-cli/starlang-cli.lisp" \
              compile "$source_root/fixtures/actor-compiler/enrichment-worker.star" \
              --manifest "$test_root/actor-manifest.json"
            sbcl --script "$source_root/starlang-cli/starlang-cli.lisp" \
              load "$source_root/fixtures/star-cl.star" \
              --cache "$test_root/cli-cache"
            sbcl --script "$source_root/starlang-cli/starlang-cli.lisp" \
              run "$source_root/fixtures/actor-compiler/enrichment-worker.star" \
              --eval "(defun enrichment-worker-handler (dispatcher command) (declare (ignore dispatcher command)) (list :outcome :complete))"

            cd "$source_root"
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall

            source_root="$out/share/common-lisp/source/star-lang"
            mkdir -p "$source_root" "$out/bin"
            cp -R "$src"/. "$source_root/"

            cat > "$out/bin/starlang" <<EOF_SCRIPT
            #!${pkgs.runtimeShell}
            set -euo pipefail

            source_root="$out/share/common-lisp/source/star-lang"
            export CL_SOURCE_REGISTRY="\$source_root//"

            exec ${sbcl}/bin/sbcl \
              --script "\$source_root/starlang-cli/starlang-cli.lisp" \
              "\$@"
            EOF_SCRIPT

            cat > "$out/bin/starlang-test" <<EOF_SCRIPT
            #!${pkgs.runtimeShell}
            set -euo pipefail

            source_root="$out/share/common-lisp/source/star-lang"
            test_root="\$(${pkgs.coreutils}/bin/mktemp -d)"
            trap '${pkgs.coreutils}/bin/rm -rf "\$test_root"' EXIT

            export HOME="\$test_root/home"
            ${pkgs.coreutils}/bin/mkdir -p "\$HOME"
            export CL_SOURCE_REGISTRY="\$source_root//"
            export STARLANG_SWI_EXECUTABLE="${swipl}/bin/swipl"
            cd "\$test_root"

            ${sbcl}/bin/sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:test-system :star-actor-protocol)' \
              --eval '(asdf:test-system :star-canonical-json)' \
              --eval '(asdf:test-system :star-journal)' \
              --eval '(asdf:test-system :star-lease)' \
              --eval '(asdf:test-system :starlang-runtime)' \
              --eval '(asdf:test-system :star-sento-compat)' \
              --eval '(asdf:test-system :star-http-port)' \
              --eval '(asdf:test-system :star-http-dexador-tests)' \
              --eval '(asdf:test-system :star-scrape)' \
              --eval '(asdf:test-system :star-process-port)' \
              --eval '(asdf:test-system :star-logic-protocol)' \
              --eval '(asdf:test-system :star-logic-ir)' \
              --eval '(asdf:test-system :starlang-compiler)' \
              --eval '(asdf:test-system :starlang-loader)' \
              --eval '(asdf:test-system :starlang-cli)' \
              --eval '(asdf:test-system :star-logic-adapter-swi)' \
              --eval '(assert (find-package "STAR-LANG.LOADER"))' \
              --eval '(assert (null (find-package "STAR-LANG.PROTOTYPE")))' \
              --eval '(sb-ext:quit)'

            ${pkgs.coreutils}/bin/timeout 120 ${sbcl}/bin/sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:test-system :star-sento-compat-integration-tests)' \
              --eval '(sb-ext:quit)'

            ${pkgs.bash}/bin/bash "\$source_root/ci/check-swi-adapter-contracts.sh"
            ${pkgs.bash}/bin/bash "\$source_root/ci/check-final-authority.sh"
            EOF_SCRIPT

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
        hydraJobs =
          if builtins.match ".*-linux" system != null then
            { default = starLang; }
          else
            { };

        devShells.default = pkgs.mkShell {
          packages = [
            sbcl
            swipl
            pkgs.git
            pkgs.python3
          ] ++ lib.optional (pkgs ? roswell) pkgs.roswell;

          shellHook = ''
            export CL_SOURCE_REGISTRY="$PWD//"
            export STARLANG_SWI_EXECUTABLE="${swipl}/bin/swipl"
            echo "star-lang dev shell: $(sbcl --version)"
            echo "SWI: $($STARLANG_SWI_EXECUTABLE --version)"
            echo "Build: nix build"
            echo "Run: nix run"
            echo "Test: nix run .#tests"
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
