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

## Agent Zero coding orchestration

For coding tasks, load the `star-lang` skill and use the StarIntel Sol/GLM flow:

1. Run `starintel-code-critic` with GPT-5.6 Sol at HIGH reasoning against the latest `main`. The critic chooses one executable vertical slice and owns semantics, task DAG, adversarial tests, acceptance gates, and explicit out-of-scope work.
2. Hand that report to `starintel-code-coordinator` running GPT-5.6 Sol. The coordinator owns architecture, integration, review, tests, branch/PR state, and merge decisions.
3. Delegate bounded implementation packets to GLM workers. GLM may implement code/tests/fixtures inside its assigned scope, but it must not independently redefine architecture, public APIs, language semantics, verification gates, or expand scope.
4. Sol reviews every worker diff and independently reruns the relevant tests before integration.
5. Keep one executable vertical slice per PR; do not start the next slice in the same branch.

When prose conflicts with executable ownership, audit the executable path first
and correct the prose in the same pull request.
