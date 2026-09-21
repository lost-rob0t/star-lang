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
