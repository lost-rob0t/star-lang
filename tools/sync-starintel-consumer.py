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
BUNDLE_ROOT = "specs/starintel"
BUNDLE_FORMAT = "starintel-consumer-bundle/1"
COMPATIBILITY_FILES = ("registry.json", "versioned_reader.py", "raw_json_numbers.py",
                       "README.md", "capabilities.json")

# A canonical release object is currently below 1 MiB. Keep HTTP downloads
# bounded before digest verification, rather than trusting remote lengths.
MAX_HTTP_ARTIFACT_BYTES = 4 * 1024 * 1024


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


def safe_target(root: Path, relative: str, *, file: bool = False) -> Path:
    """Reject symlinks and escapes before touching consumer-owned files."""
    relative = safe_path(relative)
    target = root / relative
    require(target.resolve().is_relative_to(root.resolve()), f"unsafe target: {relative}")
    current = root
    for part in PurePosixPath(relative).parts:
        current = current / part
        require(not current.is_symlink(), f"unsafe symlink target: {relative}")
    if file and target.exists():
        require(target.is_file(), f"unsafe nonregular target: {relative}")
        require(target.stat().st_nlink == 1, f"unsafe hardlinked target: {relative}")
    return target


def verify_closed_destination(root: Path, destination: str, allowed: set[Path]) -> None:
    """A dedicated bundle directory must not contain unpinned import shadows."""
    directory = safe_target(root, destination)
    if not directory.exists():
        return
    require(directory.is_dir(), "bundle destination must be a directory")
    for path in directory.rglob("*"):
        require(not path.is_symlink(), f"unsafe bundle symlink: {path}")
        if path.is_dir():
            require(path not in allowed, f"bundle file is a directory: {path}")
            continue
        require(path.is_file() and path in allowed, f"unlisted bundle file: {path}")
        require(path.stat().st_nlink == 1, f"unsafe hardlinked bundle file: {path}")


def consumer_root(lock_path: Path) -> tuple[Path, Path]:
    # Do not resolve the lock first: that would let a lock symlink choose a
    # different repository root and erase the evidence of the symlink.
    absolute = lock_path.absolute()
    root = absolute.parent.parent
    return root, safe_target(root, absolute.relative_to(root).as_posix(), file=True)


def read_source(commit: str, path: str, source: Path | None) -> bytes:
    safe_path(path)
    if source:
        # Read the commit, never an uncommitted or differently checked-out file.
        return subprocess.check_output(["git", "-C", str(source), "show", f"{commit}:{path}"])
    url = f"https://raw.githubusercontent.com/{REPOSITORY}/{commit}/{path}"
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read(MAX_HTTP_ARTIFACT_BYTES + 1)
    require(len(data) <= MAX_HTTP_ARTIFACT_BYTES,
            f"upstream artifact exceeds limit: {path}")
    return data


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


def supported_release(release: str) -> None:
    # The authority reader and generator currently target this release only.
    require(release == "0.10.1", f"unsupported release: {release}")


def registry_target(relative: str) -> str:
    """Normalize authority registry references while forbidding root escape."""
    require(isinstance(relative, str) and relative and not relative.startswith("/")
            and "\\" not in relative and ":" not in relative
            and not any(ord(c) < 32 or ord(c) == 127 for c in relative),
            f"unsafe registry path: {relative!r}")
    parts = ["compatibility"]
    for part in relative.split("/"):
        require(part not in ("", "."), f"unsafe registry path: {relative}")
        if part == "..":
            require(bool(parts), f"unsafe registry escape: {relative}")
            parts.pop()
        else:
            parts.append(part)
    return safe_path("/".join(parts))


def verify_bundle(commit: str, source: Path | None, read=None, *, release="0.10.1"):
    supported_release(release)
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "pin a full immutable commit SHA")
    if read is None:
        read = lambda path: read_source(commit, path, source)
    bundle_path = f"{RELEASE}/bundle-lock.json"
    files = {bundle_path: read(bundle_path)}
    bundle = json.loads(files[bundle_path])
    require(bundle["bundleFormat"] == BUNDLE_FORMAT, "unsupported bundle format")
    require(bundle["authorityLibrary"] == "org.starintel/core@1", "unexpected bundle authority")
    require(bundle["releaseVersion"] == bundle["schemaVersion"] == release, "bundle release mismatch")
    require(bundle["hashAlgorithm"] == "sha256", "unsupported bundle hash algorithm")
    require(bundle["releaseLock"] == "0.10.1/release-lock.json", "bundle release lock mismatch")
    require(bundle["readerRegistry"] == "compatibility/registry.json", "bundle registry mismatch")
    for relative, expected in bundle["files"].items():
        path = f"{BUNDLE_ROOT}/{safe_path(relative)}"
        require(path != bundle_path, "bundle cannot hash itself")
        data = read(path)
        require(digest(data) == expected, f"upstream bundle hash mismatch: {path}")
        files[path] = data

    def bundled(path):
        require(path in files, f"consumer must vendor the complete locked bundle: {path}")
        return files[path]

    authority, release_files = verify_release(commit, source, bundled)
    registry = json.loads(bundled(f"{BUNDLE_ROOT}/compatibility/registry.json"))
    require(registry["contract"] == "starintel-migration/1", "unsupported reader contract")
    expected_paths = set(release_files)
    expected_paths.update(f"{BUNDLE_ROOT}/compatibility/{name}" for name in COMPATIBILITY_FILES)
    for relative, expected in registry["sha256"].items():
        path = f"{BUNDLE_ROOT}/{registry_target(relative)}"
        require(digest(bundled(path)) == expected, f"registry hash mismatch: {path}")
        expected_paths.add(path)
    require(set(files) - {bundle_path} == expected_paths, "bundle must contain the complete locked reader closure")
    return authority, files


def sync(lock_path: Path, commit: str, source: Path | None, destination: str,
         *, bundle: bool = False, release: str = "0.10.1") -> dict:
    supported_release(release)
    release, files = (verify_bundle(commit, source) if bundle else verify_release(commit, source))
    # The repo root is the parent of schema/, the standard consumer lock location.
    root, lock_path = consumer_root(lock_path)
    destination = safe_path(destination)
    prefix = BUNDLE_ROOT if bundle else RELEASE
    paths = {path: f"{destination}/{path.removeprefix(prefix + '/')}" for path in files}
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
    if bundle:
        lock["bundle_format"] = BUNDLE_FORMAT
        lock["bundle_lock_path"] = f"{RELEASE}/bundle-lock.json"
    targets = {path: safe_target(root, local, file=True) for path, local in paths.items()}
    require(len(set(targets.values())) == len(files), "duplicate consumer target")
    require(lock_path not in targets.values(), "consumer artifact cannot overwrite its lock")
    if bundle:
        require(not lock_path.is_relative_to(root / destination),
                "consumer lock must stay outside the dedicated bundle destination")
        verify_closed_destination(root, destination, set(targets.values()))
    for path, data in files.items():
        target = targets[path]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    return lock


def verify_bundle_layout(lock: dict) -> str:
    """Return the dedicated destination after checking canonical sibling paths."""
    require(lock["bundle_format"] == BUNDLE_FORMAT, "unsupported bundle format")
    require(lock.get("bundle_lock_path") == f"{RELEASE}/bundle-lock.json", "bundle lock path mismatch")
    for local, entry in lock["vendored_files"].items():
        safe_path(local)
        require(isinstance(entry, dict) and isinstance(entry.get("source"), str),
                f"invalid bundle mapping: {local}")
    bundle_locals = [local for local, entry in lock["vendored_files"].items()
                     if entry["source"] == lock["bundle_lock_path"]]
    require(len(bundle_locals) == 1, "consumer must vendor the complete locked bundle")
    suffix = "/0.10.1/bundle-lock.json"
    require(bundle_locals[0].endswith(suffix), "bundle sibling layout mismatch")
    destination = bundle_locals[0][:-len(suffix)]
    safe_path(destination)
    for local, entry in lock["vendored_files"].items():
        require(entry["source"].startswith(BUNDLE_ROOT + "/"), "bundle source root mismatch")
        expected_local = destination + "/" + entry["source"].removeprefix(BUNDLE_ROOT + "/")
        require(local == expected_local, "bundle sibling layout mismatch")
    return destination


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
        local_paths[local] = safe_target(root, local, file=True)
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
    if "bundle_format" in lock:
        destination = verify_bundle_layout(lock)
        release, files = verify_bundle(lock["canonical_commit"], source, read)
        verify_closed_destination(root, destination, set(local_paths.values()))
    else:
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
    parser.add_argument("--destination", help="vendor root; bundle mode preserves release/compatibility siblings")
    parser.add_argument("--release", default="0.10.1", help="explicit authority release (currently only 0.10.1)")
    parser.add_argument("--bundle", action="store_true", help="sync the complete reader bundle; checks detect mode from the lock")
    parser.add_argument("--offline", action="store_true", help="verify local package closure; CI must also check exact upstream bytes")
    args = parser.parse_args()
    if args.offline and (args.commit or args.source):
        parser.error("--offline is a local check only; cannot combine with --commit or --source")
    try:
        supported_release(args.release)
        destination = args.destination or ("schemas/starintel" if args.bundle else "schemas/starintel-0.10.1")
        lock = (sync(args.lock, args.commit, args.source, destination,
                     bundle=args.bundle, release=args.release) if args.commit
                else check(args.lock, args.source, offline=args.offline))
        require(not args.bundle or lock.get("bundle_format") == BUNDLE_FORMAT,
                "requested bundle mode requires a bundle lock")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"StarIntel consumer verification failed: {error}\n")
    print(f"verified StarLang StarIntel {lock['release_version']} at {lock['canonical_commit']}")


if __name__ == "__main__":
    main()
