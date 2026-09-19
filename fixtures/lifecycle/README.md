# Document lifecycle fixtures (star-lang#142)

Committed fixtures consumed by the server lifecycle executor slice
(starintel-server#240, LATER). The server is NOT implemented here.

## Files

- `document-lifecycle.star` -- a compilable StarLang spec-library declaring a
  `person` document and a `person-lifecycle` policy exercising the full
  closed lifecycle vocabulary: states, transitions, guards, retention,
  archival, replication class, indexing/search policy, encryption/privacy
  class, legal hold, derivation/supersession, redaction/tombstone, TTL,
  storage tier, and event emission.
- `document-lifecycle.manifest.json` -- the deterministic canonical JSON
  (RFC 8785) serialization of the compiled lifecycle manifest.
- `generate-manifest.lisp` -- regenerates the manifest JSON:

  ```sh
  ci/with-nix-sbcl.sh --script fixtures/lifecycle/generate-manifest.lisp
  ```

## Manifest shape

The compiler public surface emits the manifest as runtime-neutral plist IR:

```lisp
(starlangcompiler:emit-lifecycle-manifest lifecycle-ir)
;; => (:wire-version 1 :lifecycle (:kind :lifecycle ...))
(starlangcompiler:lifecycle-transition-table lifecycle-ir)
;; => the transition rows alone, declared order
```

`lifecycle-ir` is the `:lifecycle` declaration entry of a compiled
spec-library (`:declarations`). The JSON fixture maps that plist field by
field with a closed key mapping (lower camel case, absent optional fields
omitted):

| plist                          | JSON                    |
|--------------------------------+-------------------------|
| `:wire-version`                | `wireVersion` (1)       |
| `:name`                        | `name`                  |
| `:qualified-name`              | `qualifiedName`         |
| `:applies`                     | `applies`               |
| `:version`                     | `version`               |
| `:initial`                     | `initial`               |
| `:states`                      | `states[]`              |
| `:retention` `:evidence-days`  | `retention.evidenceDays`|
| `:storage` `:tier`             | `storage.tier`          |
| `:storage` `:replication`      | `storage.replication`   |
| `:ttl-days`                    | `ttlDays`               |
| `:indexing` `:mode`            | `indexing.mode`         |
| `:encryption` `:class`         | `encryption.class`      |
| `:hold` `:class` / `:reason`   | `hold.class` / `hold.reason` |
| `:events`                      | `events[]`              |
| `:transitions` (rows, declared order) | `transitions[]`  |

Each transition row maps `:from`/`:on`/`:to` verbatim, `:action` to its
downcased closed keyword (default `keep`), and omits `guard`/`emit`/
`supersedes` when absent:

```json
{"from": "draft", "on": "submitted", "to": "active",
 "guard": "submit-guard", "action": "keep", "emit": "submitted"}
```

## Server-consumption contract (for starintel-server#240)

- Determinism: identical `.star` source bytes compile to identical manifest
  plists and identical JSON bytes; durations are normalized to integer days
  (months = 30, years = 365).
- Versioned replay: `version` is the declared lifecycle policy version; the
  `(:from, :on)` transition table is a total function over the declared event
  vocabulary from `initial` (ambiguity and unreachability are compile-time
  rejections), so an executor can replay event sequences deterministically.
- Safety: no transition row carries action `destroy` while `retention` or
  `hold` is present; provenance-erasing deletion cannot enter a manifest that
  promises evidence.
