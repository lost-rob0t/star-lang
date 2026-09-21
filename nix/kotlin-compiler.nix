{ pkgs }:

let
  compilerZip = pkgs.fetchurl {
    url = "https://github.com/JetBrains/kotlin/releases/download/v2.4.20/kotlin-compiler-2.4.20.zip";
    hash = "sha256-WenKdMeQTvLBIrEhFJN2c8zOaN6CCmY/DtZsz4eZ4Lc=";
  };
in
pkgs.runCommand "kotlin-compiler-2.4.20" {
  nativeBuildInputs = [
    pkgs.unzip
  ];
} ''
  mkdir -p "$out" "$TMPDIR/unpack"
  unzip -q "${compilerZip}" -d "$TMPDIR/unpack"
  cp -R "$TMPDIR/unpack/kotlinc/." "$out/"
  patchShebangs "$out/bin"
''
