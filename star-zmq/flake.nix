{
  description = "StarLang local ZMQ binding and CL/Nim interoperability gate (draft)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      build = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = pkgs.lib;
          zmqLibrary = "${lib.getLib pkgs.zeromq}/lib/libzmq.so";
          lisp = pkgs.sbcl.withPackages (ps: [ ps.cffi ps.bordeaux-threads ]);
          python = pkgs.python3.withPackages (ps: [ ps.pyzmq ]);
          nimPeer = pkgs.stdenv.mkDerivation {
            pname = "star-zmq-peer";
            version = "0.1.0";
            src = self;
            nativeBuildInputs = [ pkgs.nim ];
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              nim c --threads:off -d:release \
                --nimcache:"$TMPDIR/nimcache" \
                -d:StarZmqLibrary=${zmqLibrary} \
                --out:star-zmq-peer nim/peer.nim
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              install -Dm755 star-zmq-peer "$out/bin/star-zmq-peer"
              runHook postInstall
            '';
            meta = {
              description = "One-shot Nim ZMQ byte peer; not a federation service";
              license = lib.licenses.agpl3Only;
              mainProgram = "star-zmq-peer";
              platforms = systems;
            };
          };
          pythonClient = pkgs.python3Packages.buildPythonPackage {
            pname = "star-zmq-local";
            version = "0.1.0";
            src = ./python;
            pyproject = true;
            build-system = [ pkgs.python3Packages.setuptools ];
            dependencies = [ pkgs.python3Packages.pyzmq ];
          };
          clSource = pkgs.runCommand "star-zmq-cl-source-0.1.0" { } ''
            mkdir -p "$out/share/common-lisp/source/star-zmq"
            cp -R ${self}/src ${self}/tests ${self}/star-zmq.asd \
              "$out/share/common-lisp/source/star-zmq/"
          '';
          nimSource = pkgs.runCommand "star-zmq-nim-source-0.1.0" { } ''
            mkdir -p "$out/share/nim/star-zmq"
            cp ${self}/nim/star_zmq.nim "$out/share/nim/star-zmq/"
          '';
          nativeCheck = pkgs.runCommand "star-zmq-native-interop" {
            nativeBuildInputs = [ lisp ];
            STAR_ZMQ_LIBRARY = zmqLibrary;
            STAR_ZMQ_PEER = "${nimPeer}/bin/star-zmq-peer";
          } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:load-asd #P"${self}/star-zmq.asd")' \
              --eval '(asdf:test-system "star-zmq")'
            touch "$out"
          '';
          pythonCheck = pkgs.runCommand "star-zmq-python-transport" {
            nativeBuildInputs = [ python ];
          } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            python -m unittest discover -s ${self}/tests -p 'test_*.py' -v
            touch "$out"
          '';
        in {
          packages = {
            default = nimPeer;
            star-zmq-peer = nimPeer;
            star-zmq-cl = clSource;
            star-zmq-nim = nimSource;
            star-zmq-python = pythonClient;
          };
          apps = {
            default = { type = "app"; program = "${nimPeer}/bin/star-zmq-peer"; };
            peer = { type = "app"; program = "${nimPeer}/bin/star-zmq-peer"; };
          };
          checks = {
            native-interop = nativeCheck;
            python-transport = pythonCheck;
            python-package = pythonClient;
          };
          devShells.default = pkgs.mkShell {
            packages = [ lisp pkgs.nim pkgs.zeromq python ];
            STAR_ZMQ_LIBRARY = zmqLibrary;
          };
        };
    in {
      packages = eachSystem (system: (build system).packages);
      apps = eachSystem (system: (build system).apps);
      checks = eachSystem (system: (build system).checks);
      devShells = eachSystem (system: (build system).devShells);
    };
}
