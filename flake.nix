{
  description = "star-lang: Common Lisp-only StarLang compiler and durable actor runtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        sbcl = pkgs.sbcl;
        roswell = pkgs.roswell or null;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            sbcl
            pkgs.git
          ] ++ (if roswell != null then [ roswell ] else [ ]);
          shellHook = ''
            export CL_SOURCE_REGISTRY="$PWD//"
            echo "star-lang dev shell: sbcl $(sbcl --version)"
            echo "Load a system with: sbcl --eval '(require :asdf)' --eval '(asdf:load-system :star-actor-protocol)'"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "star-lang";
          version = "0.0.0";
          src = ./.;
          nativeBuildInputs = [ sbcl ];
          buildPhase = ''
            export CL_SOURCE_REGISTRY="$src//"
            for asd in ./*/*.asd; do
              sbcl --non-interactive \
                --eval "(require :asdf)" \
                --eval "(asdf:load-system :$(basename "$asd" .asd))" || true
            done
          '';
          installPhase = "mkdir -p $out";
          doCheck = false;
        };
      });
}
