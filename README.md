# StarLang

StarLang is a Common Lisp-only compiler and durable actor runtime.

This repository contains the language prototype, compiler/runtime systems, portable actor contracts, canonical JSON support, and adapters used to build durable StarIntel workflows.

## GitHub target actor

`star-github` consumes normal StarIntel `dtype=target` JSON documents whose `actor` is `github`. The runner scans `data/targets/*.json`, invokes the native StarLang actor, writes discovered GitHub users as StarIntel JSON documents under `data/documents-user/`, and records every execution under `data/target-runs/`.

The actor uses `STARINTEL_GITHUB_TOKEN` when present. GitHub Actions falls back to the workflow token for same-repository public collection and writeback.

Run locally with credentials available to `gh`:

```sh
export STARINTEL_GITHUB_TOKEN=...
export GH_TOKEN="$STARINTEL_GITHUB_TOKEN"
sbcl --script star-github/run-targets.lisp data
```

See the subsystem ASDF files and tests for the remaining compiler/runtime entry points.
