# Supported workflow contract closure (local draft)

The executable legacy Auto-Dig base vocabulary has 57 dtypes, plus its separately
installed operation contract. Against StarLang #197, 28 named dtypes lack an
exact canonical type. All 28 have executable schemas; none is safely treated as
an undefined label or an exact alias. This draft retains all 28 as distinct
canonical documents rather than retiring schema-driven generic authoring.

` supported-workflow-inventory.json ` records each classification and evidence:
22 have direct producer/editor or requested-output pipeline evidence. For six
(education, evidence-record, meeting, ownership, product, task), the survey found
only compatibility/read/schema/selection evidence. They are marked
historical-only-observed, not discontinued; generic legacy authoring was still
supported. Dossier remains outside this set because no executable definition
was found. Social-media-post is not relabeled socialmpost without an established
lossless semantic equivalence.

## Lossless field mapping

See supported-workflow-mappings.json. Domain data fields become lowerCamelCase;
opaque map keys and arbitrary contents remain unchanged. ID strings remain
strings, not invented schema/id reference pairs. Decimal numbers become exact
strings; numeric bounds are carried by generated scalar definitions. Metadata
and payload do not overwrite each other:

- payload valid_from/valid_to become nullable ISO contentValidFrom/contentValidUntil
- research-node payload created_at becomes nullable ISO nodeCreatedAt
- other payload/envelope name collisions use explicit payload-prefixed fields
- envelope createdAt/validFrom remain independent Unix integer metadata
- dataset-manifest counts_by_dtype becomes an injective typed key/value entry
  list; keys remain verbatim, values remain integers. Keys must be unique.

Typed nested research-node limits, counters, stop policies and history preserve
old requireds, bounds and false/null values. Existing UI state transition rules,
stop behavior, runtime accounting and the128-entry history policy remain runtime
behavior. Snapshot schema validation does not pretend to execute those workflows.

## Evidence and verification boundary

legacy-workflow-oracle.json contains exact data_schema outputs from the pinned
original executable source, with its repository/commit/path/SHA-256. Paired
fixtures first validate original legacy data against that oracle, then validate
the corresponding canonical document against generated schema and scalar bounds.
Inverse mapping recovers every original field/value, including IDs, fractional
RFC3339 timestamps with offsets, false, null, decimal values and opaque keys.

Negative checks cover enum violations, missing required fields, nested unknown
keys, integer and decimal lower bounds, and duplicate typed-map keys. These tests
prove structural/mapping parity, not end-to-end behavior for every producer.
Consumers must call workflow_semantics.py's checks (or an equivalent native
implementation) in addition to operation semantics and generated validation.
Repinning alone does not migrate a producer's API or persisted corpus.

No corpus records are rewritten. No publishing, merging or deployment is part
of this local draft. Document counts should be derived from persistent manifest
entries, never hardcoded while vocabulary closure is underway.
