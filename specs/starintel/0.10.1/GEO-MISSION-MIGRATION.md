# StarIntel 0.10.1 geo and mission boundary

StarLang source in `core.star` is the schema authority. Generated bindings,
portable manifests, and JSON Schema are derived artifacts; downstream
repositories must not hand-maintain competing geo or mission object models.

## Canonical records

0.10.1 defines canonical geometry/location/address records plus:

- `mission` — operator-authored plan, constraints, scope and referenced spatial plan;
- `mission-target` — one evidence-backed subject within a mission;
- `route` — a route that references canonical line geometry and waypoint records;
- `geofence` — canonical geometry plus bounded transition policy;
- `encounter` — bounded co-observation/proximity evidence;
- `map-layer` — rebuildable operator/query projection, never a new truth store.

The `query-spatial` message is transport-neutral. StarIntel Server / star-geo
owns authorization-aware execution and indexing.

## Identity boundary

An encounter never means that two observations identify the same person or
device, establish ownership, residence, affiliation, or any other relationship.
Those claims require separate canonical records with their own evidence,
confidence, provenance, and adjudication.

## Direct, anchored and derived geography

- **direct** geography is present on or explicitly referenced by the source record;
- **anchored** geography follows an explicit canonical reference/relation;
- **derived** geography comes from a named bounded rule and must retain proof/path,
  temporal validity, uncertainty and provenance.

Derived geography must never be copied back as direct evidence.

## Worker ownership

- **Android** captures/caches/synchronizes canonical records and executes mission
  effects through scoped capabilities; it does not define geo schema.
- **Wireless** emits WiGLE/Kismet/radio evidence and references canonical locations.
  RF encounter logic does not make identity claims.
- **Media** extracts geo/time evidence and references canonical location/geometry.
- **Quasar** renders/query-plans layers, routes, missions and timelines.
- **StarIntel Server / star-geo** owns GeoProjection, bbox/nearest/intersection
  queries, authorization/tenancy filtering and rebuildable spatial indexes.

## Migration order

1. Change `core.star`.
2. Run the StarLang compiler/conformance suite.
3. Regenerate `generated/portable-manifest.json`, `generated/schema.json`, and
   every language binding.
4. Finalize and verify `release-lock.json`.
5. Repin downstream consumers to the exact StarLang commit/release lock.
6. Only then implement persistence/API behavior in server, Android, Quasar,
   wireless, media or edge repositories.

Legacy 0.9.x records are migration input only. Canonical output is 0.10.1
lowerCamelCase.

## Frozen 0.10.1 source-to-generator signature checks

The Common Lisp compiler suite loads
`starlang-compiler/tests/fixtures/geo-mission-signatures-0101.json` and
recompiles `core.star` before checking the exact field names, required fields,
and inheritance of geo points, locations, addresses, missions, mission targets,
routes, geofences, encounters, map layers, and the spatial-query request.
A second test checks generated JSON Schema references for coordinates,
mission subjects, and route geometry. CI runs the real compiler test system.

These signatures are **regression fixtures**, not a new release authority:
the pinned 0.10.1 `core.star`, generated outputs, and release lock do not
change. The fixture does not imply that JSON Schema validates decimal-string
range/scale, four-element bbox cardinality, GeoPoint's geometry discriminator,
cross-field time ordering, or a spatial-query response. SL01/SL02 must
address those gaps through an explicitly versioned successor contract;
IR14 coordinates any consumer repins. Android, wireless, Quasar and media
continue to exchange canonical references/evidence. SS11/SS13 own authorized
CouchDB JSON spatial execution and indexing, not StarLang.
