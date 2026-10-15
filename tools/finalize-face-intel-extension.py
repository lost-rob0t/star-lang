"""Lock source and generated extension artifacts; schema generation stays in Lisp."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "specs/starintel/extensions/face-intel/0.1.0"
CORE = ROOT / "specs/starintel/0.10.1"
LOCK = RELEASE / "release-lock.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def release_lock():
    manifest = json.loads((RELEASE / "generated/portable-manifest.json").read_text())
    expected_import = {
        "kind": "import",
        "name": "org.starintel/core@1",
        "version": "0.10.1",
        "digest": "sha256:" + digest(CORE / "core.star"),
    }
    if manifest["imports"] != [expected_import]:
        raise ValueError("Extension import differs from locked core source")
    return {
        "authorityLibrary": "org.starintel/face-intel@1",
        "releaseVersion": "0.1.0",
        "schemaVersion": "0.10.1",
        "canonicalKeyStyle": "lowerCamelCase",
        "hashAlgorithm": "sha256",
        "imports": [expected_import],
        "sources": {
            name: digest(RELEASE / name)
            for name in ("face-intel.star", "fixtures.json", "README.md")
        },
        "coreReleaseLockHash": digest(CORE / "release-lock.json"),
        "artifacts": {
            path.name: digest(path)
            for path in sorted((RELEASE / "generated").iterdir()) if path.is_file()
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = json.dumps(release_lock(), indent=2, sort_keys=True) + "\n"
    if args.check:
        if LOCK.read_text() != expected:
            raise ValueError("Missing or stale face extension release lock")
        print("FaceIntel 0.1.0 release lock verified")
    else:
        LOCK.write_text(expected)
        print("FaceIntel 0.1.0 release lock generated")


if __name__ == "__main__":
    main()
