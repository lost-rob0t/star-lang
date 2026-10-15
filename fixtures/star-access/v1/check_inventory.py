#!/usr/bin/env python3
"""Lint the access test-requirement inventory; never claim runtime conformance."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

MAX_BYTES = 256 * 1024
BINDINGS = {"local", "rabbit", "starRouter", "http", "a2a"}
OPERATIONS = {
    *(f"star.documents.{name}@1" for name in (
        "get", "head", "put", "patch", "delete", "bulk-get", "bulk-write",
        "query", "changes",
    )),
    *(f"star.targets.{name}@1" for name in (
        "submit", "get", "status", "cancel", "reschedule", "result",
    )),
}


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def string_set(value: Any, name: str) -> set[str]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{name}: expected nonempty array")
    if not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{name}: expected nonempty strings")
    if len(set(value)) != len(value):
        raise ValueError(f"{name}: duplicate entries")
    return set(value)


def validate(data: Any) -> tuple[int, int]:
    if not isinstance(data, dict):
        raise ValueError("inventory must be an object")
    expected = {
        "format": "star.access.conformance-plan/1",
        "profile": "star.access/1",
        "status": "required",
        "evidenceClass": "test-requirements-not-results",
    }
    for field, value in expected.items():
        if data.get(field) != value:
            raise ValueError(f"invalid {field}; requirements are not results")
    if set(data) != {*expected, "defaultBindings", "operations", "cases"}:
        raise ValueError("unexpected or missing inventory fields")
    if string_set(data["operations"], "operations") != OPERATIONS:
        raise ValueError("operation inventory must match all 15 profile operations")
    if string_set(data["defaultBindings"], "defaultBindings") != BINDINGS:
        raise ValueError("binding inventory does not match this plan")
    cases = data["cases"]
    if not isinstance(cases, list) or not 64 <= len(cases) <= 1000:
        raise ValueError("expected between 64 and 1000 required scenarios")
    covered: set[str] = set()
    required = {"id", "operations", "given", "when", "then"}
    for index, case in enumerate(cases, 1):
        if not isinstance(case, dict):
            raise ValueError(f"scenario {index}: expected object")
        if not required <= set(case) <= required | {"bindings"}:
            raise ValueError(f"scenario {index}: invalid fields")
        if case["id"] != f"ACCESS-{index:03d}":
            raise ValueError(f"scenario {index}: IDs must be unique and contiguous")
        for field in ("given", "when", "then"):
            if not isinstance(case[field], str) or not case[field].strip():
                raise ValueError(f"{case['id']}: empty {field}")
        used = string_set(case["operations"], case["id"])
        if not used <= OPERATIONS:
            raise ValueError(f"{case['id']}: unknown operation")
        selected = string_set(case.get("bindings", data["defaultBindings"]), "bindings")
        if not selected <= BINDINGS:
            raise ValueError(f"{case['id']}: unknown binding")
        covered.update(used)
    if covered != OPERATIONS:
        raise ValueError("one or more operations have no required scenarios")
    return len(cases), len(covered)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", nargs="?", type=Path,
                        default=Path(__file__).with_name("scenarios.json"))
    args = parser.parse_args()
    try:
        with args.inventory.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("inventory exceeds byte limit")
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
        count, covered = validate(data)
    except (OSError, UnicodeError, ValueError, RecursionError) as error:
        parser.exit(1, f"inventory invalid: {error}\n")
    print(f"Inventory valid: {count} required scenarios cover {covered} operations.")
    print("Packaging/metadata lint only; no actor, transport or runtime tests executed.")


if __name__ == "__main__":
    main()
