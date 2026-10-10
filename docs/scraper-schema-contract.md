# Scraper schema contracts (`org.starscrape/scraper@1`)

Status: final system slice (`star-scrape`), schema authority in StarLang.

This document describes the StarLang-owned schema contract for a generic
website-scraper actor (star-lang#137). The vocabulary — every bound, enum,
and field contract — lives in `fixtures/star-scrape-core.star` and enters
the system only through the closed StarLang parser. No Common Lisp reader,
`eval`, or second parser is involved anywhere in the path.

## Pipeline

```text
fixtures/star-scrape-core.star            (versioned .star vocabulary)
  -> starlangcompiler:load-star-form      (closed UTF-8 parser)
  -> spec-library normalized IR           (data-only, deterministic)
  -> starlangcompiler:emit-portable-manifest
  -> portable vocabulary manifest
       +  policy (plain Lisp data built by the consumer, never eval)
  -> starscrape.schema:compile-scraper-manifest
  -> portable scraper manifest            (data-only plist)
  -> starscrape.schema:scraper-manifest-json
  -> canonical JSON (sorted keys, lower camelCase)
```

`compile-scraper-manifest` validates the policy twice:

1. **Generic vocabulary validation** through
   `staractorprotocol:validate-portable-wire-value`. The compiled
   vocabulary enforces field presence (`:required`), unknown-field
   rejection, enum membership, and scalar `:minimum`/`:maximum` bounds.
   The bounds live only in `.star`; no Lisp code re-declares them.
2. **The closed scraper policy gate** (`starscrape.schema`), for rules a
   type vocabulary cannot express. The gate rejects:
   - `privateNetwork` values other than `forbid` (SSRF deny-by-default);
   - allowed origins that are not bare `https://` public hostnames
     (plaintext schemes, paths, queries, fragments, userinfo, ports over
     five digits, address literals such as loopback or link-local IPs,
     and bare single-label names are all rejected);
   - empty origin or content-type allowlists and malformed
     `type/subtype` media types (parameters and whitespace rejected);
   - selectors or attribute names that are empty, over 256 characters,
     or contain control characters;
   - `attribute` extractors without an attribute name;
   - pagination kind `next-link` without `nextSelector`, `page-param`
     without `pageParameter`, or `none` with either;
   - empty extraction field lists, empty document mapping lists, and
     mappings with zero field entries; non-list `transform` values;
   - malformed `documentType` (must be lowercase ASCII identifiers) and
     extracted/mapped field names (must be lower camelCase ASCII);
   - unbounded provenance strings (`collector` at most 256 characters,
     `userAgent` at most 128).

A policy that passes both stages yields a deterministic, data-only
manifest:

```lisp
(:manifest-schema "org.starscrape/scraper-manifest@1"
 :wire-version 1
 :vocabulary <portable vocabulary manifest>
 :policy <validated policy>)
```

## Vocabulary coverage

`fixtures/star-scrape-core.star` declares `org.starscrape/scraper@1`
version `1.0.0` with bounded scalars, closed enums, and documents for
each configuration area:

| Area | Vocabulary document |
| --- | --- |
| Request policy, allowed origins, SSRF/redirect/size/content-type bounds | `request-policy` |
| Selectors, extractors, transforms | `extraction-plan`, `extraction-field` |
| Document mapping | `document-mapping`, `field-mapping` |
| Pagination and recursion bounds | `pagination-policy` |
| Rate and concurrency bounds | `rate-limits` |
| Retry/backoff | `retry-backoff` |
| Robots/policy metadata | `robots-policy` |
| Provenance | `provenance-info` |
| Effect capabilities (closed allowlist) | `effect-capability` enum |
| Top-level aggregation | `scraper-policy` |

Explicit bounds (schema authority, not restated in code): at most 5
redirects; at most 100 MiB response bodies; crawl depth at most 8;
pagination bounded between 1 and 1000 pages; at most 10 attempts;
timeouts and delays at most 600000 ms; at most 1000 requests/second and
64 concurrent requests.

The `effect-capability` enum is the closed effect allowlist:
`net-https-fetch`, `parse-html`, `rate-limit-scheduler`, `crawl-budget`,
`starintel-documents`. Capabilities outside the enum — for example
private-network fetch, filesystem writes, process execution, or host
evaluation — are rejected during validation. Widening the allowlist is a
vocabulary version change, not a code change.

## Consumer contract

A Lisp consumer constructs a policy as plain data (keyword plists,
lists, strings, integers, booleans) and compiles it without eval:

```lisp
(multiple-value-bind (vocabulary ir)
    (starscrape.schema:load-scraper-vocabulary
     #p"fixtures/star-scrape-core.star"
     :expected-name "org.starscrape/scraper@1")
  (declare (ignore ir))
  (let ((manifest
          (starscrape.schema:compile-scraper-manifest vocabulary policy)))
    (starscrape.schema:scraper-manifest-json manifest)))
```

Validation failures signal `starscrape.schema:scraper-policy-error`
(domain gate) or `staractorprotocol:invalid-wire-envelope-error`
(vocabulary). Malformed `.star` vocabularies signal structured
`starlangcompiler` compiler conditions.

## Guarantees and limits

- The manifest and its canonical JSON are deterministic: the same
  vocabulary and policy produce byte-identical JSON. Source paths never
  enter the portable manifest.
- Canonical JSON round-trips without semantic drift: decoding and
  re-encoding the emitted JSON reproduces the same bytes; integer,
  boolean, string, array, and object structure is preserved; absent
  optional fields stay absent; `null` never appears.
- Schema authority is the `.star` vocabulary. The scalar `:pattern`
  constraints documented there are enforced by the policy gate for the
  security-critical strings listed above; the generic wire validator
  does not interpret patterns.
- This slice defines and compiles the schema contract. Executing a
  manifest against the network (egress enforcement, robots handling,
  redirect following) remains with the HTTP port and runtime actor
  layers; the manifest is the declaration those layers consume.
- Runtime actor consumption of scraper manifests (building runtime
  scrape plans from a manifest) is a follow-up migration slice.


## Version 2: reusable offline mapping

`fixtures/star-scrape-core-v2.star` declares `org.starscrape/scraper@2`
version `2.0.0`. Version 1 source and wire contracts stay unchanged. A
consumer must explicitly select v2; unknown major versions fail closed.
The pure entry point is:

```lisp
(starscrape.schema:compile-mapping-manifest vocabulary mapping-plan)
```

It yields `{manifestSchema: "org.starscrape/mapping-manifest@2",
wireVersion: 2, vocabulary: ..., mappingPlan: ...}`. The existing
`compile-scraper-manifest` entry accepts either vocabulary version and
emits the matching `org.starscrape/scraper-manifest@1` or `@2`. A v2
acquisition policy contains `mappingPlan` instead of the v1 `extraction`
and `mapping` pair. Never silently reinterpret a v1 plan as v2.

### Pure mapping wire fields

- `inputFormat`: `html` or `json`.
- `maxInputBytes`, `maxRows`, `maxDepth`: required bounded integers from
  the vocabulary. Runtime checks apply before/during parsing, not only
  after allocating the full input. `maxRows` limits total scope rows and
  each multi-valued field's selected values. Depth bounds parsed input
  nesting and traversal. Configuration and output size should also be
  bounded by the consumer's execution budget.
- `scopes`: unique named parent-row selectors, each containing `name`,
  `selectorKind` (`css`, `xpath`, `json-path`), `selector`, and `fields`.
- Each field contains `name`, `selectorKind`, `selector`, and `kind`
  (`text`, `attribute`, `html`, `value`); `attribute`, `many`, `required`,
  and ordered `transform` are optional. Only `attribute` extractors may
  declare an attribute. JSON uses `value`, HTML uses the other kinds.
- `documents`: unique mappings with `name`, `scope`, canonical
  `documentType`, `naturalKey` (distinct extracted field names), and
  `fields` (`source` extraction name and canonical `target` field).
  Identity keys must be required scalar extractions. Missing, null, or
  empty natural keys fail; row position is never an identity key.
- `relations` is optional. Each entry has `name`, `scope`, canonical
  `predicate`, `sourceDocument`, and `destinationDocument`. Endpoint
  names reference document mappings emitted in that same row, never raw
  source IDs, unrelated rows, or array positions. Predicate endpoint
  types must conform to canonical inheritance. Resulting canonical
  relations use typed `source` and `destination` references plus
  `predicate`; `relationType`, `subject`, and `object` are not output
  fields. Relation identity derives from emitted endpoints and predicate.
- `emitSource` and `emitUrl` are optional booleans. When enabled, the
  runtime emits canonical `source`/`url` documents from explicitly
  supplied source identity/provenance; these flags grant no fetch or
  filesystem capability. URL emission requires a supplied usable URL.

Canonical output authority remains `specs/starintel/0.10.1/core.star`.
The mapping compiler loads it through the same closed compiler and
checks dtypes, inherited fields, predicates, and endpoint types. No
copied dtype registry or second schema parser is introduced. Runtime
output validation must additionally check required fields, value types,
scalar bounds and cross-field semantics. Outputs use flat StarIntel
0.10.1 camelCase envelopes (`id`, `dataset`, `dtype`, `schemaVersion`),
never nested legacy envelopes. Mapping cannot override those four fields.

### Selection and transformation semantics

JSON paths consist of `$`, ASCII `.property` identifiers (initial letter
or underscore, then letters/digits/underscore), and nonnegative `[index]`
steps. `$` always means the current selection root. Filters, wildcards,
recursive descent, host expressions and evaluation are forbidden. Scope
selectors start at the input root; an array result expands to its items,
an object/scalar result creates one row, and a missing result creates
zero rows. Field selectors start at that row, never the input root.
`many: true` selects an array; otherwise a scalar is required. JSON null
is distinct from missing and false during extraction; required/null and
natural-key/null fail. Optional null must not be coerced to the string
`"null"`; output omission or rejection follows the canonical field type.

HTML scopes select row elements. Field CSS and XPath selection is
relative to that element. Field XPath must start with `.`; runtimes must
also enforce that all returned nodes belong to the row subtree and
reject escaping axes, absolute alternatives, scalar expressions, or
extension functions. HTML parsing must disable external resource loads,
DTDs and entity expansion. No scraping adapter is being implemented by
this compiler-only contract change.

Transforms are closed, ordered, and data-only: `trim`, `lowercase`,
`uppercase`, `strip-tags`, `absolute-url`, `decode-entities`, `integer`,
`decimal`, `boolean`. Unknown transforms are rejected. String transforms
require strings; conversions are explicit and strict, never Python/Lisp
truthiness or evaluation. `integer` rejects fractional values and boolean
inputs; `decimal` preserves exact decimal precision and rejects NaN or
infinity; `boolean` accepts booleans or exact `true`/`false` text only.
Conversions apply elementwise for `many`. Consumer resource limits bound
numeric tokens and collection sizes. `absolute-url` requires explicitly
supplied source URI and does not fetch the result. The canonical output
adapter must use the canonical SDK's exact-number representation.

Stable identity must include dataset, source namespace, scope and mapping
name, and typed natural-key values, encoded unambiguously. Reordering
rows must not change IDs. Supplied source URI is preferred; a content-hash
URN is a deterministic fallback for a fixed offline input, but changing
input bytes changes that fallback namespace. Local absolute filenames
must never be implicitly persisted as provenance. Runtime execution
context supplies dataset, collector and source identity separately from
the pure plan.

### Acquisition and generation

V2 request policy optionally accepts `authRef` with lexical shape
`secret-ref:<bounded-identifier>`. It cannot contain a credential value,
URL, query string, bearer prefix or arbitrary header map. Omission is
anonymous, including public API usage. Runtime resolves a reference only
through its authorized scoped secret port; the mapper never resolves it.
Existing SSRF, origin, redirect, robots and rate-limit gates still apply.
The versioned effect allowlist adds `parse-json` for JSON acquisition.

Generate consumable artifacts only with:

```sh
CL_SOURCE_REGISTRY="$PWD//:" sbcl --script tools/generate-scraper-release.lisp
CL_SOURCE_REGISTRY="$PWD//:" sbcl --script tools/generate-scraper-release.lisp --check
```

The generator uses the existing compiler and JSON-schema emitter to
produce `specs/scraper/2.0.0/generated/portable-manifest.json`,
`schema.json`, and `bundle-lock.json`. The lock pins the source, manifest
and schema SHA-256 bytes (including final newline), vocabulary version,
and canonical StarIntel output version. Consumers import these outputs,
verify digests and reject unsupported contracts; they do not edit them.
The generated artifact CI job re-generates and verifies exact bytes.
These portable schema artifacts do not claim a new runtime backend or
new generated language-specific mapper implementations. Existing language
ownership and supported backend matrix remain unchanged.

V2 serialization reuses the canonical typed wire codec for `mappingPlan`
and `policy`, while retaining the established vocabulary codec for the
embedded type manifest. Explicit false flags stay false, omitted flags
stay absent, and `relations: []` stays an empty array. Lisp callers may
use either NIL or `staractorprotocol:+portable-json-false+` for false;
a false sentinel never counts as a required natural-key field. An empty
transform list should be omitted rather than declared.
