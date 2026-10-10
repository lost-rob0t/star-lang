# StarLang coding-agent contract

This file defines the repository execution contract for autonomous coding
agents. The marked block is intentionally duplicated in `README.md` and is
checked byte-for-byte by CI.

BEGIN STARLANG AGENT INSTRUCTIONS
- `main` is canonical; every change is reviewed through a pull request.
- StarLang is intentionally polyglot. Common Lisp is a permanent first-class compiler and runtime backend; Kotlin/JVM is an additive peer runtime backend.
- The language-neutral StarLang specification, normalized IR, wire contracts, canonical fixtures, and conformance tests own semantics across implementations.
- The StarLang research/design repository is semantic design authority, subject to explicit operator reversals recorded in the active design/issue authority.
- Executable ASDF, Gradle, Nix, CI, and runtime state outranks stale status prose.
- Add no new authoritative behavior under `prototype/`.
- Never delete, demote, or mark a supported language/runtime backend as temporary without a separate explicit operator-approved decision.
- Runtime port work adds conforming implementations; parity never authorizes removal of the Common Lisp implementation.
- Preserve portable generated/boundary support for Common Lisp, Python, TypeScript, Nim, Java, Kotlin, Go, Rust, Emacs Lisp, and Prolog.
- Use test-driven development and run focused, surrounding, cross-runtime, and full gates.
- Actor-semantic tests must execute the real runtime boundary they claim to verify.
- Mocks may replace external-effect ports, never actor semantics evidence.
- Keep the final-system dependency graph acyclic.
- Java is a JVM consumer ABI, Nim may provide isolated native/edge adapters, and C is thin FFI unless separately approved.
- Commit no secrets, credentials, private datasets, or private evidence.
- Complete the applicable ASDF, Gradle, CI, cross-runtime conformance, and `nix flake check -L` gates before declaring completion.
- Update ownership and language-matrix documentation whenever executable ownership changes.
END STARLANG AGENT INSTRUCTIONS

When prose conflicts with executable ownership, audit the executable path first
and correct the prose in the same pull request.

<!-- BEGIN STARINTEL FLEET CONTRACT -->
## StarIntel 15-worker fleet contract

This repository participates in the StarIntel hourly worker fleet.

- **GitHub connector is the repository control surface for fleet automation.** Use the connected GitHub connector to read current `AGENTS.md`, repository files, issues, pull requests, branches, diffs, comments, reviews, and CI/check state, and for permitted writes. Attempt the connector before claiming GitHub repository access or mutation is unavailable.
- **Canonical StarIntel document authority is 0.10.1 generated from Star Language.** The source of truth is `lost-rob0t/star-lang/specs/starintel/0.10.1/core.star` and its generated artifacts. Consumer repositories must consume/pin generated output; they must not maintain a competing handwritten schema or revive 0.9.x as canonical authority.
- **Respect worker ownership.** SL01-SL05 own Star Language/compiler/schema domains; PA06-PA09 own Pro Actors/collection runtimes; SS10-SS13 own server/runtime/router/persistence/security; IR14-IR15 own cross-repo integration and release admission. Do not duplicate an in-flight branch or silently take over another worker's owned slice.
- **One writer per branch.** Re-fetch exact head/base immediately before mutation. Reuse an existing retained branch/PR when it owns the task. Never force-push or overwrite concurrent work.
- **Evidence is exact-head.** Required CI/checks must be observed on the exact candidate SHA; pending, skipped, stale, foreign, mock-only, or unrun evidence is not green.
- **No status-only escape hatch.** If the preferred task is blocked, record the precise blocker and advance another executable issue within scope.
- **Scheduled fleet tasks stay enabled.** Repository work must not disable a scheduled worker unless the operator explicitly asks for that task to be disabled.

Repository-specific rules still apply; stricter local rules win unless they conflict with canonical StarIntel 0.10.1 authority or an explicit current operator instruction.
<!-- END STARINTEL FLEET CONTRACT -->
