# StarIntel schemas in StarLang

StarLang source under this directory is the canonical schema authority for
StarIntel documents. Language-specific libraries and generated bindings are
consumers; they must not maintain an independent copy of the object model.

## 0.10.1

Canonical source:

- `specs/starintel/0.10.1/core.star`
- `specs/starintel/0.10.1/GEO-MISSION-MIGRATION.md` — geo/mission consumer boundary
- `specs/starintel/0.10.1/NETWORK-CAPTURE-MIGRATION.md` — HTTP/browser capture compatibility boundary

The 0.10.1 core includes the generic `file` contract and first-class media,
audio, transcript, typed person-identifier, first-class geometry, HTTP/browser
capture, packet-capture, network-device, and wireless documents. Generic files do
not use an extension or MIME allowlist. A filename extension is descriptive
metadata only; consumers make security decisions from content identity,
content sniffing/magic, quarantine state, parser policy, and capabilities.

Specialized media documents extend the generic file contract:

```text
file
├── image
│   └── video-frame
├── picture
├── video
└── audio
```

`compatibility.json` is the machine-readable migration authority. Its own keys
are lowerCamelCase. Legacy spellings appear only as quoted input aliases; they
are never canonical output. Migrations accept 0.9.0 and 0.10.1, emit only
0.10.1, preserve unknown input below `extensions.legacy`, and quarantine a
single document on ambiguity or validation failure instead of terminating a
consumer.

`compatibility-fixtures.json` is the cross-language executable contract for
that policy. Every consumer must produce those documents and reason codes
exactly; bindings may not add private compatibility interpretations.

`schema-lock-manifest.json` is only a bridge for the installed consumer-lock
resolver's historical control-file format. Its snake_case metadata is never
document wire data; `canonical_key_style` explicitly remains `lowerCamelCase`.

The geo hierarchy keeps coordinate meaning typed and explicit:

```text
geo
├── geo-point
├── geo-line-string
├── geo-polygon
├── geo-multi-point
├── geo-multi-line-string
├── geo-multi-polygon
└── geo-geometry-collection
```

Coordinates use longitude/latitude order and WGS84 (`EPSG:4326`) by default.
`location` names or classifies a place and references a geometry; `address`
describes a postal location and may reference a geometry.

The same compiled portable manifest is used to generate boundaries for:

- Common Lisp
- Kotlin
- Java
- Python
- TypeScript
- Nim
- Go
- Rust
- Emacs Lisp
- Prolog

Do not hand-edit generated language bindings to change schema semantics. Change
the `.star` source, compile it, regenerate bindings, and run the cross-language
conformance suite.

Regenerate or verify the checked artifacts with:

```sh
bash ci/with-nix-sbcl.sh --disable-debugger \
  --script tools/generate-starintel-release.lisp
bash ci/with-nix-sbcl.sh --disable-debugger \
  --script tools/generate-starintel-release.lisp --check
python3 tools/finalize-starintel-release.py
python3 tools/finalize-starintel-release.py --check
```

## Consuming a release

Every downstream repository must consume this generated release from an
immutable StarLang commit. This includes language libraries, schema mirrors,
document producers, servers, actor services, and applications. A matching
version string alone does not establish conformance: the old nested
`schema_version` envelope is a different contract from the flat 0.10.1
`schemaVersion` envelope.

Copy `tools/sync-starintel-consumer.py` into the consumer, then run it from that
repository root:

```sh
python3 tools/sync-starintel-consumer.py --commit <full-StarLang-commit>
python3 tools/sync-starintel-consumer.py
```

The first command verifies the upstream release hashes before vendoring every
source and generated artifact and writing `schema/starintel-schema.lock.json`.
The second is the required CI drift gate. It verifies the immutable upstream
release and every local copy; generated outputs must never be edited downstream.
Dependency consumers must additionally check that their library and application
locks identify the same StarLang release.

Load the generated language binding and derive runtime validation from the
generated manifest/schema. The JSON Schema root is a definitions library:
validation must select the concrete document definition using the manifest's
document dtype inventory, resolve references, and enforce the manifest's decimal
constraints. Validating only the root does not validate a document.

Retain historical contracts only behind an explicit versioned compatibility
boundary. Migrations must follow the fixtures above; changing a version constant
or renaming keys is insufficient. No downstream schema generator, handwritten
model, or historical repository becomes an independent specification authority.
