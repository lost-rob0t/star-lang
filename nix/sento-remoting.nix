{ pkgs }:
ps:
let
  clCancelSource = pkgs.fetchFromGitHub {
    owner = "atgreen";
    repo = "cl-cancel";
    rev = "bec34fb37fe713746bdeefaf542f578d174d9ffa";
    hash = "sha256-M+cV1t6ZYcRoSVGIExu/KYyUlw3wQ694/NfXlTlJUOI=";
  };

  pureTlsSource = pkgs.fetchFromGitHub {
    owner = "atgreen";
    repo = "pure-tls";
    rev = "79230b1489242e955476ff7185bb46ed043cfdea";
    hash = "sha256-qbTAd6iHbErLP1HRAdQ+2vso4NEBB8lYLUUULlecY1w=";
  };

  sentoSource = pkgs.fetchFromGitHub {
    owner = "mdbergmann";
    repo = "cl-gserver";
    rev = "013ab6370042686e65943568b0d97e33319c0f54";
    hash = "sha256-z+AKk8Y09rpF+NgyKhcHNvn0jsjeGe3dSibkv8yySKg=";
  };

  clCancelPinned = pkgs.sbcl.buildASDFSystem {
    pname = "cl-cancel";
    version = "0.1.0";
    src = clCancelSource;
    lispLibs = [
      ps.atomics
      ps.bordeaux-threads
      ps.precise-time
    ];
  };

  pureTlsPinned = pkgs.sbcl.buildASDFSystem {
    pname = "pure-tls";
    version = "1.13.0";
    src = pureTlsSource;
    systems = [ "pure-tls" ];
    lispLibs = [
      ps.alexandria
      ps.bordeaux-threads
      ps.cl-base64
      clCancelPinned
      ps.flexi-streams
      ps.idna
      ps.ironclad
      ps.trivial-features
      ps.trivial-gray-streams
      ps.usocket
    ];
  };
in
pkgs.sbcl.buildASDFSystem {
  pname = "sento";
  version = "3.4.4";
  src = sentoSource;
  systems = [
    "sento"
    "sento-remoting"
  ];
  lispLibs = [
    ps.alexandria
    ps.atomics
    ps.binding-arrows
    ps.bordeaux-threads
    ps.cl-speedy-queue
    ps.flexi-streams
    ps.local-time-duration
    ps.log4cl
    pureTlsPinned
    ps.str
    ps.timer-wheel
    ps.usocket
  ];
}
