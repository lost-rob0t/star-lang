# SL04 typed spatial result successor proposal

This source proposal fills the absent typed reply to the canonical 0.10.1
query-spatial request. The candidate is compiled in memory as 0.10.2;
the 0.10.1 core, generated artifacts and release lock remain immutable.
The successor version is provisional pending SL01/SL02 and IR14 review.

SpatialMatch carries typed source, projection, geometry and evidence references;
participation distinguishes direct, anchored and derived. QuerySpatialResult
carries typed matches, completeness (complete/partial/unknown), snapshot
identity, opaque cursor pagination, hasMore and evaluatedAt.

Thirteen golden message cases exercise the real portable validator:
three accepted envelopes, ten rejected malformed or semantically invalid
shapes. Spatial matches optionally distinguish observedAt (source observation)
from validFrom/validUntil (projection applicability) and evaluatedAt (query
execution). The wire validator checks Unix timestamp types and nonnegativity,
not cross-field interval ordering or the credibility of evidence references. Tests generate actual JSON Schema and Python/TypeScript/Rust bindings
from a compiled candidate; generated output is checked in memory and must
not be mistaken for a published immutable release.

Shape validation cannot prove source identity, spatial association, attribution,
cursor authorization, snapshot consistency, the veracity of completeness, or
nonempty evidence lists. Derived geography must not be promoted to direct
evidence. SS11/SS13 retain JSON/CouchDB storage, GeoCouch bbox indexing,
authorization and query execution; StarLang does not implement a search runtime.

Commands on a provisioned repo:
  sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:test-system "starlang-compiler-tests")'
  nix flake check -L

SL01 owns normalized semantics. SL02 owns parser/generator output and the
accepted float decision (#5). IR14 owns successor promotion and pinned
consumer migrations. Android, wireless, Quasar and media must not adopt the
new contract until a generated and locked release is available.

## SL04 typed WGS84 bounding-box request proposal

The frozen 0.10.1 query-spatial.boundingBox field is a variable-length
list of decimal strings. It cannot enforce a four-coordinate bbox shape.

Provisional 0.10.2 adds QuerySpatialBbox requiring a typed SpatialBounds
object with west/east Longitude and south/north Latitude fields. This
is a new message, not an alteration of frozen 0.10.1 messages or
generated release artifacts. Two accepted and ten rejected golden wire
cases check field presence, scalar ranges, types and unsupported claims.
The real compiler emits the candidate message in the portable manifest,
SpatialBounds in JSON Schema, and Python/TypeScript/Rust bindings in memory
during executable tests. JSON Schema does not emit message definitions.

Antimeridian-crossing boxes (west greater than east) remain representable.
The wire type cannot enforce south <= north, logical cursor consistency,
tenant authorization or geospatial query execution. SS11/SS13 own those
runtime checks and CouchDB/GeoCouch storage and indexing, not StarLang.

Coordinates use canonical 0.10.1 decimal strings in these regression
fixtures. SL01/SL02 must reconcile the future binary64 coordinate
decision (issue #5) before IR14 generates and locks a successor release.
No Android, wireless, Quasar or media repin is authorized by this proposal.
