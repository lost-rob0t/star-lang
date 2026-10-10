#!/usr/bin/env python3
"""Read-only, aggregate drift report for 0.10.1 StarLang consumer locks.

The committed StarLang release/bundle locks are authority. This tool never
regenerates schemas or modifies a downstream checkout. Online identity still
requires the existing sync-starintel-consumer.py check with an immutable ref.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
RELEASE = "specs/starintel/0.10.1"
BUNDLE_ROOT = "specs/starintel"
BUNDLE_FORMAT = "starintel-consumer-bundle/1"
REPOSITORY = "lost-rob0t/star-lang"


def safe_path(path: str) -> str:
    if (not isinstance(path, str) or not path or path != str(PurePosixPath(path))
        or PurePosixPath(path).is_absolute() or any(x in ("", ".", "..") for x in path.split("/"))
        or "\\" in path or ":" in path or any(ord(x) < 32 or ord(x) == 127 for x in path)):
        raise ValueError(f"unsafe path: {path!r}")
    return path


def safe_target(root: Path, relative: str, *, file: bool = False) -> Path:
    target = root / safe_path(relative)
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"unsafe target: {relative}")
    current = root
    for part in PurePosixPath(relative).parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"unsafe symlink target: {relative}")
    if file and target.exists() and (not target.is_file() or target.stat().st_nlink != 1):
        raise ValueError(f"unsafe nonregular target: {relative}")
    return target


def consumer_root(lock_path: Path) -> tuple[Path, Path]:
    absolute = lock_path.absolute()
    root = absolute.parent.parent
    return root, safe_target(root, absolute.relative_to(root).as_posix(), file=True)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def authority_closure(root: Path, bundle: bool) -> tuple[dict[str, str], list[str]]:
    """Derive expected source hashes *only* from the canonical release locks."""
    errors: list[str] = []
    release_path = RELEASE + "/release-lock.json"
    release_bytes = safe_target(root, release_path, file=True).read_bytes()
    release = json.loads(release_bytes)
    if release.get("releaseVersion") != "0.10.1" or release.get("schemaVersion") != "0.10.1":
        errors.append("authority: release version is not 0.10.1")
    if release.get("authorityLibrary") != "org.starintel/core@1":
        errors.append("authority: unexpected library")
    expected = {release_path: sha256(release_bytes)}
    for group, prefix in (("sources", RELEASE),
                          ("artifacts", RELEASE + "/generated")):
        for filename, digest in release[group].items():
            path = prefix + "/" + safe_path(filename)
            expected[path] = digest
    if bundle:
        bundle_path = RELEASE + "/bundle-lock.json"
        bundle_bytes = safe_target(root, bundle_path, file=True).read_bytes()
        metadata = json.loads(bundle_bytes)
        if metadata.get("bundleFormat") != BUNDLE_FORMAT:
            errors.append("authority: unsupported bundle format")
        bundle_files = {
            BUNDLE_ROOT + "/" + safe_path(filename): value
            for filename, value in metadata["files"].items()
        }
        for path, digest in expected.items():
            if bundle_files.get(path) != digest:
                errors.append("authority: release/bundle hash mismatch: " + path)
        if set(expected) - set(bundle_files):
            errors.append("authority: bundle omits release closure")
        expected = bundle_files
        expected[bundle_path] = sha256(bundle_bytes)
    for path, digest in expected.items():
        try:
            target = safe_target(root, path, file=True)
            if sha256(target.read_bytes()) != digest:
                errors.append("authority: committed file drift: " + path)
        except (OSError, ValueError) as exc:
            errors.append("authority: unreadable file: " + path + ": " + str(exc))
    return expected, errors


def audit(lock_path: Path, authority_root: Path) -> dict:
    """Report all visible file/hash/mapping drift without writing any files."""
    errors: list[str] = []
    root, lock_file = consumer_root(lock_path)
    lock = json.loads(lock_file.read_text(encoding="utf-8"))
    bundle = "bundle_format" in lock
    expected, authority_errors = authority_closure(authority_root, bundle)
    errors.extend(authority_errors)
    if lock.get("canonical_repository") != REPOSITORY:
        errors.append("consumer: noncanonical repository")
    if lock.get("release_version") != "0.10.1" or lock.get("schema_version") != "0.10.1":
        errors.append("consumer: unexpected release version")
    if bundle and lock.get("bundle_format") != BUNDLE_FORMAT:
        errors.append("consumer: unsupported bundle format")
    files = lock.get("vendored_files")
    if not isinstance(files, dict):
        raise ValueError("vendored_files must be a JSON object")
    seen: dict[str, str] = {}
    for local, entry in sorted(files.items()):
        if not isinstance(entry, dict) or not isinstance(entry.get("source"), str):
            errors.append("consumer: invalid mapping: " + str(local))
            continue
        source = entry["source"]
        if source in seen:
            errors.append("consumer: duplicate source: " + source)
        seen[source] = local
        if source not in expected:
            errors.append("consumer: unlisted source: " + source)
            continue
        if entry.get("sha256") != expected[source]:
            errors.append("consumer: stale lock hash: " + str(local))
        try:
            target = safe_target(root, local, file=True)
            if sha256(target.read_bytes()) != expected[source]:
                errors.append("consumer: vendored bytes drift: " + str(local))
        except (OSError, ValueError) as exc:
            errors.append("consumer: unreadable target: " + str(local) + ": " + str(exc))
    for source in sorted(set(expected) - set(seen)):
        errors.append("consumer: missing source: " + source)
    return {"lock": str(lock_path), "release": "0.10.1",
            "mode": "bundle" if bundle else "release", "ok": not errors,
            "errors": sorted(set(errors))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--authority-root", type=Path, default=HERE.parent)
    parser.add_argument("--lock", type=Path, action="append", required=True)
    args = parser.parse_args()
    reports = []
    for lock in args.lock:
        try:
            reports.append(audit(lock, args.authority_root))
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            reports.append({"lock": str(lock), "ok": False, "errors": [str(exc)]})
    print(json.dumps({"reports": reports}, indent=2, sort_keys=True))
    return 0 if all(item["ok"] for item in reports) else 1


if __name__ == "__main__":
    raise SystemExit(main())
