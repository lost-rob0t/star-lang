# StarIntel schemas in StarLang

StarLang source under this directory is the canonical schema authority for
StarIntel documents. Language-specific libraries and generated bindings are
consumers; they must not maintain an independent copy of the object model.

## 0.10.1

Canonical source:

- `specs/starintel/0.10.1/core.star`

The 0.10.1 core includes the generic `file` contract and first-class media,
audio, packet-capture, network-device, and wireless documents. Generic files do
not use an extension or MIME allowlist. A filename extension is descriptive
metadata only; consumers make security decisions from content identity,
content sniffing/magic, quarantine state, parser policy, and capabilities.

Specialized media documents extend the generic file contract:

```text
file
├── image
│   └── video-frame
├── picture
├── video
└── audio-recording
```

The same compiled portable manifest is used to generate boundaries for:

- Common Lisp
- Kotlin
- Java
- Python
- TypeScript
- Nim
- Go
- Rust
- Emacs Lisp
- Prolog

Do not hand-edit generated language bindings to change schema semantics. Change
the `.star` source, compile it, regenerate bindings, and run the cross-language
conformance suite.
