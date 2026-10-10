# SL04 typed spatial result successor proposal

This source proposal fills the absent typed reply to the canonical 0.10.1
query-spatial request. The candidate is compiled in memory as 0.10.2;
the 0.10.1 core, generated artifacts and release lock remain immutable.
The successor version is provisional pending SL01/SL02 and IR14 review.

SpatialMatch carries typed source, projection, geometry and evidence references;
participation distinguishes direct, anchored and derived. QuerySpatialResult
carries typed matches, completeness (complete/partial/unknown), snapshot
identity, opaque cursor pagination, hasMore and evaluatedAt.

The nine golden message cases exercise the real portable validator:
two accepted envelopes, seven rejected malformed or semantically invalid
shapes. Tests generate actual JSON Schema and Python/TypeScript/Rust bindings
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
