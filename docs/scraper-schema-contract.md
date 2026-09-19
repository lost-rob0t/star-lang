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
