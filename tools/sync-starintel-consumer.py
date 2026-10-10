#!/usr/bin/env python3
"""Pin or verify a downstream copy of the StarLang-generated StarIntel release.

Copy this tool into consumers. Never regenerate schema semantics downstream.
Only immutable Git commits are accepted, and all release inputs/outputs are
verified before a consumer lock or vendored file is written.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import urllib.request

REPOSITORY = "lost-rob0t/star-lang"
RELEASE = "specs/starintel/0.10.1"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def safe_path(path: str) -> str:
    require(isinstance(path, str) and bool(path), f"unsafe path: {path!r}")
    value = PurePosixPath(path)
    require(
        not value.is_absolute() and str(value) == path
        and all(part not in ("", ".", "..") for part in path.split("/"))
        and "\\" not in path and ":" not in path
        and not any(ord(char) < 32 or ord(char) == 127 for char in path),
        f"unsafe path: {path!r}",
    )
    return path


def safe_target(root: Path, relative: str) -> Path:
    """Reject symlinks and escapes before touching consumer-owned files."""
    relative = safe_path(relative)
    target = root / relative
    require(target.resolve().is_relative_to(root.resolve()), f"unsafe target: {relative}")
    current = root
    for part in PurePosixPath(relative).parts:
        current = current / part
        require(not current.is_symlink(), f"unsafe symlink target: {relative}")
    return target


def consumer_root(lock_path: Path) -> tuple[Path, Path]:
    # Do not resolve the lock first: that would let a lock symlink choose a
    # different repository root and erase the evidence of the symlink.
    absolute = lock_path.absolute()
    root = absolute.parent.parent
    return root, safe_target(root, absolute.relative_to(root).as_posix())


def read_source(commit: str, path: str, source: Path | None) -> bytes:
    safe_path(path)
    if source:
        # Read the commit, never an uncommitted or differently checked-out file.
        return subprocess.check_output(["git", "-C", str(source), "show", f"{commit}:{path}"])
    url = f"https://raw.githubusercontent.com/{REPOSITORY}/{commit}/{path}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def verify_release(commit: str, source: Path | None, read=None) -> tuple[dict, dict[str, bytes]]:
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "pin a full immutable commit SHA")
    if read is None:
        read = lambda path: read_source(commit, path, source)
    lock_path = f"{RELEASE}/release-lock.json"
    files = {lock_path: read(lock_path)}
    release = json.loads(files[lock_path])
    require(release["authorityLibrary"] == "org.starintel/core@1", "unexpected authority")
    require(release["releaseVersion"] == release["schemaVersion"] == "0.10.1", "release mismatch")
    require(release["canonicalKeyStyle"] == "lowerCamelCase", "wire key style mismatch")
    require(release["hashAlgorithm"] == "sha256", "unsupported release hash algorithm")
    for category, prefix in (("sources", RELEASE), ("artifacts", f"{RELEASE}/generated")):
        for name, expected in release[category].items():
            path = f"{prefix}/{safe_path(name)}"
            data = read(path)
            require(digest(data) == expected, f"upstream release hash mismatch: {path}")
            files[path] = data
    manifest = json.loads(files[f"{RELEASE}/generated/portable-manifest.json"])
    require(manifest["library"]["name"] == release["authorityLibrary"], "manifest authority mismatch")
    require(manifest["library"]["version"] == release["releaseVersion"], "manifest version mismatch")
    return release, files


def sync(lock_path: Path, commit: str, source: Path | None, destination: str) -> dict:
    release, files = verify_release(commit, source)
    # The repo root is the parent of schema/, the standard consumer lock location.
    root, lock_path = consumer_root(lock_path)
    destination = safe_path(destination)
    paths = {path: f"{destination}/{path.removeprefix(RELEASE + '/')}" for path in files}
    lock = {
        "canonical_repository": REPOSITORY,
        "canonical_commit": commit,
        "release_version": release["releaseVersion"],
        "schema_version": release["schemaVersion"],
        "authority_library": release["authorityLibrary"],
        "canonical_key_style": release["canonicalKeyStyle"],
        "release_lock_path": f"{RELEASE}/release-lock.json",
        "schema_path": f"{RELEASE}/generated/schema.json",
        "manifest_path": f"{RELEASE}/generated/portable-manifest.json",
        "vendored_files": {
            paths[path]: {"source": path, "sha256": digest(data)}
            for path, data in sorted(files.items())
        },
    }
    targets = {path: safe_target(root, local) for path, local in paths.items()}
    require(len(set(targets.values())) == len(files), "duplicate consumer target")
    require(lock_path not in targets.values(), "consumer artifact cannot overwrite its lock")
    for path, data in files.items():
        target = targets[path]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    return lock


def check(lock_path: Path, source: Path | None, *, offline: bool = False) -> dict:
    root, lock_path = consumer_root(lock_path)
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    require(lock["canonical_repository"] == REPOSITORY, "StarLang must own the canonical spec")
    local_paths = {}
    seen_sources = set()
    for local, entry in lock["vendored_files"].items():
        canonical = safe_path(entry["source"])
        require(canonical not in seen_sources, "duplicate canonical source")
        seen_sources.add(canonical)
        local_paths[local] = safe_target(root, local)
    read = None
    if offline:
        # Package builds verify their complete local release closure. CI must
        # still run the online/exact-commit check to establish upstream identity.
        local_sources = {}
        for local, entry in lock["vendored_files"].items():
            require(entry["source"] not in local_sources, "duplicate canonical source")
            data = local_paths[local].read_bytes()
            require(digest(data) == entry["sha256"], f"consumer hash mismatch: {local}")
            local_sources[entry["source"]] = data
        def read(path):
            require(path in local_sources, f"consumer must vendor the complete locked release: {path}")
            return local_sources[path]
    release, files = verify_release(lock["canonical_commit"], source, read)
    for local, canonical in (("release_version", "releaseVersion"), ("schema_version", "schemaVersion"),
                             ("authority_library", "authorityLibrary"), ("canonical_key_style", "canonicalKeyStyle")):
        require(lock[local] == release[canonical], f"consumer {local} mismatch")
    for name, expected in (("release_lock_path", f"{RELEASE}/release-lock.json"),
                           ("schema_path", f"{RELEASE}/generated/schema.json"),
                           ("manifest_path", f"{RELEASE}/generated/portable-manifest.json")):
        require(lock[name] == expected, f"consumer {name} mismatch")
    seen = set()
    for local, entry in lock["vendored_files"].items():
        require(entry["source"] in files, f"unlocked upstream artifact: {local}")
        canonical = files[entry["source"]]
        require(entry["sha256"] == digest(canonical), f"consumer hash mismatch: {local}")
        require(local_paths[local].read_bytes() == canonical, f"vendored artifact drift: {local}")
        seen.add(entry["source"])
    require(seen == set(files), "consumer must vendor the complete locked release")
    return lock


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=Path("schema/starintel-schema.lock.json"))
    parser.add_argument("--source", type=Path, help="local StarLang git checkout (otherwise fetch immutable URLs)")
    parser.add_argument("--commit", help="sync to this full SHA; omit to check without writes")
    parser.add_argument("--destination", default="schemas/starintel-0.10.1")
    parser.add_argument("--offline", action="store_true", help="verify local package closure; CI must also check exact upstream bytes")
    args = parser.parse_args()
    if args.offline and (args.commit or args.source):
        parser.error("--offline is a local check only; cannot combine with --commit or --source")
    try:
        lock = (sync(args.lock, args.commit, args.source, args.destination) if args.commit
                else check(args.lock, args.source, offline=args.offline))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"StarIntel consumer verification failed: {error}\n")
    print(f"verified StarLang StarIntel {lock['release_version']} at {lock['canonical_commit']}")


if __name__ == "__main__":
    main()
