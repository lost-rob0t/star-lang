#!/usr/bin/env python3
"""Validate and lock the generated StarIntel 0.10.1 release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "specs" / "starintel" / "0.10.1"
GENERATED = RELEASE / "generated"
LOCK = RELEASE / "release-lock.json"
LOWER_CAMEL = re.compile(r"^[a-z][A-Za-z0-9]*$")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def validate_manifest(manifest: dict[str, object]) -> None:
    library = manifest.get("library")
    require(isinstance(library, dict), "portable manifest is missing library metadata")
    require(library.get("name") == "org.starintel/core@1", "unexpected authority library")
    require(library.get("version") == "0.10.1", "unexpected authority version")
    types = manifest.get("types")
    require(isinstance(types, list), "portable manifest types must be an array")
    for contract in types:
        if not isinstance(contract, dict):
            continue
        fields = contract.get("fields", [])
        if not isinstance(fields, list):
            continue
        for field in fields:
            require(isinstance(field, dict), "portable manifest field must be an object")
            name = field.get("name")
            require(
                isinstance(name, str) and LOWER_CAMEL.fullmatch(name) is not None,
                f"non-lowerCamelCase wire field in portable manifest: {name!r}",
            )


def validate_compatibility(compatibility: dict[str, object]) -> None:
    require(compatibility.get("canonicalKeyStyle") == "lowerCamelCase", "wrong canonical key style")
    require(compatibility.get("emittedSchemaVersion") == "0.10.1", "wrong emitted schema version")
    require(compatibility.get("idempotent") is True, "migration must be idempotent")
    legacy = compatibility.get("legacyInput")
    require(isinstance(legacy, dict), "legacyInput must be an object")
    aliases = legacy.get("envelopeAliases")
    require(isinstance(aliases, dict), "envelopeAliases must be an object")
    geo = compatibility.get("geo")
    require(isinstance(geo, dict), "geo compatibility rules must be an object")
    geo_aliases = geo.get("fieldAliases")
    require(isinstance(geo_aliases, dict), "geo fieldAliases must be an object")
    for target in [*aliases.values(), *geo_aliases.values()]:
        require(
            isinstance(target, str) and LOWER_CAMEL.fullmatch(target) is not None,
            f"legacy alias emits a non-lowerCamelCase field: {target!r}",
        )


def release_lock() -> dict[str, object]:
    core = RELEASE / "core.star"
    compatibility_path = RELEASE / "compatibility.json"
    fixtures_path = RELEASE / "compatibility-fixtures.json"
    lock_manifest_path = RELEASE / "schema-lock-manifest.json"
    manifest_path = GENERATED / "portable-manifest.json"
    schema_path = GENERATED / "schema.json"
    for path in (
        core,
        compatibility_path,
        fixtures_path,
        lock_manifest_path,
        manifest_path,
        schema_path,
    ):
        require(path.is_file(), f"missing release input: {path}")

    manifest = load_json(manifest_path)
    compatibility = load_json(compatibility_path)
    fixtures = load_json(fixtures_path)
    lock_manifest = load_json(lock_manifest_path)
    schema = load_json(schema_path)
    require(isinstance(manifest, dict), "portable manifest must be an object")
    require(isinstance(compatibility, dict), "compatibility manifest must be an object")
    require(isinstance(fixtures, dict), "compatibility fixtures must be an object")
    require(isinstance(lock_manifest, dict), "schema lock manifest must be an object")
    require(isinstance(schema, dict), "JSON Schema must be an object")
    validate_manifest(manifest)
    validate_compatibility(compatibility)
    require(fixtures.get("fixtureVersion") == 1, "unexpected compatibility fixture version")
    fixture_cases = fixtures.get("cases")
    require(isinstance(fixture_cases, list) and fixture_cases, "compatibility fixtures must have cases")
    require(lock_manifest.get("release_version") == "0.10.1", "wrong lock release version")
    require(lock_manifest.get("schema_version") == "0.10.1", "wrong lock schema version")
    require(
        lock_manifest.get("canonical_key_style") == "lowerCamelCase",
        "wrong lock canonical key style",
    )
    require(
        schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
        "generated schema is not JSON Schema 2020-12",
    )

    artifacts = {
        path.name: sha256(path)
        for path in sorted(GENERATED.iterdir(), key=lambda item: item.name)
        if path.is_file()
    }
    return {
        "authorityLibrary": "org.starintel/core@1",
        "releaseVersion": "0.10.1",
        "schemaVersion": "0.10.1",
        "canonicalKeyStyle": "lowerCamelCase",
        "hashAlgorithm": "sha256",
        "sources": {
            "core.star": sha256(core),
            "legacy-workflow-oracle.json": sha256(RELEASE / "legacy-workflow-oracle.json"),
            "supported-workflow-fixtures.json": sha256(RELEASE / "supported-workflow-fixtures.json"),
            "supported-workflow-mappings.json": sha256(RELEASE / "supported-workflow-mappings.json"),
            "supported-workflow-inventory.json": sha256(RELEASE / "supported-workflow-inventory.json"),
            "workflow_semantics.py": sha256(RELEASE / "workflow_semantics.py"),

            "operation_semantics.py": sha256(RELEASE / "operation_semantics.py"),
            "research-fixtures.json": sha256(RELEASE / "research-fixtures.json"),
            "compatibility.json": sha256(compatibility_path),
            "compatibility-fixtures.json": sha256(fixtures_path),
            "schema-lock-manifest.json": sha256(lock_manifest_path),
        },
        "artifacts": artifacts,
    }


def encoded_lock(value: dict[str, object]) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"



BUNDLE = RELEASE / "bundle-lock.json"
BUNDLE_FORMAT = "starintel-consumer-bundle/1"


def bundle_lock() -> dict[str, object]:
    """Lock the portable sibling layout without modifying release semantics."""
    root = RELEASE.parent.resolve()
    release = release_lock()
    require(LOCK.read_text(encoding="utf-8") == encoded_lock(release),
            "release lock must be finalized before bundle generation")
    paths = {LOCK}
    paths.update(RELEASE / name for name in release["sources"])
    paths.update(GENERATED / name for name in release["artifacts"])
    compatibility = root / "compatibility"
    registry_path = compatibility / "registry.json"
    registry = load_json(registry_path)
    require(registry.get("contract") == "starintel-migration/1", "unsupported reader contract")
    paths.update(compatibility / name for name in
                 ("registry.json", "versioned_reader.py", "raw_json_numbers.py",
                  "README.md", "capabilities.json"))
    for relative, expected in registry["sha256"].items():
        path = compatibility / relative
        require(path.resolve().is_relative_to(root), f"unsafe registry path: {relative}")
        require(path.is_file() and sha256(path) == expected,
                f"pinned compatibility artifact mismatch: {relative}")
        paths.add(path)
    files = {}
    for path in sorted(paths):
        resolved = path.resolve()
        require(resolved.is_relative_to(root), f"unsafe bundle path: {path}")
        relative = resolved.relative_to(root).as_posix()
        require(resolved != BUNDLE.resolve(), "bundle cannot hash itself")
        current = root
        for part in path.absolute().relative_to(root).parts:
            current = current / part
            require(not current.is_symlink(), f"symlink bundle input: {relative}")
        require(path.is_file(), f"missing bundle input: {relative}")
        files[relative] = sha256(path)
    return {
        "bundleFormat": BUNDLE_FORMAT,
        "authorityLibrary": release["authorityLibrary"],
        "releaseVersion": release["releaseVersion"],
        "schemaVersion": release["schemaVersion"],
        "hashAlgorithm": "sha256",
        "releaseLock": "0.10.1/release-lock.json",
        "readerRegistry": "compatibility/registry.json",
        "files": files,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--bundle", action="store_true", help="also generate/check the complete 0.10.1 reader bundle")
    args = parser.parse_args()
    expected = encoded_lock(release_lock())
    if args.check:
        require(LOCK.is_file(), f"missing release lock: {LOCK}")
        require(LOCK.read_text(encoding="utf-8") == expected, f"stale release lock: {LOCK}")
        if args.bundle:
            require(BUNDLE.is_file(), f"missing bundle lock: {BUNDLE}")
            require(BUNDLE.read_text(encoding="utf-8") == encoded_lock(bundle_lock()),
                    f"stale bundle lock: {BUNDLE}")
        print("StarIntel 0.10.1 release lock verified")
        return 0
    LOCK.write_text(expected, encoding="utf-8")
    if args.bundle:
        BUNDLE.write_text(encoded_lock(bundle_lock()), encoding="utf-8")
        print(f"wrote {BUNDLE}")
    print(f"wrote {LOCK}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
