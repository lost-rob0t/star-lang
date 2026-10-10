# SL05: 0.10.1 media timeline and evidence-integrity semantics

Authority: Star Language core.star, org.starintel/core@1, version 0.10.1.
The executable reference and locked fixture corpus live beside the source in
media_semantics.py and media-evidence-fixtures.json.

## Observed source-contract failure

The generated JSON Schema correctly identifies integer timestamps and other
field types, but cannot express relative ordering: a video frame at -1 ms or an
audio segment with endMs <= startMs passes structural validation. Similarly,
source and evidence-record may carry a payloadContentHash without a named hash
algorithm. Such records cannot support reliable chronology or reproducible
artifact identity. All negative cases in the fixture corpus are structurally
valid and must fail the additional semantic gate.

## Normative rules for current 0.10.1 producers

- Frame indexes and millisecond media offsets are nonnegative; offsets are
  relative to the linked audio/video asset, not Unix wall-clock timestamps.
- Audio-segment, speech-segment, speaker-observation and speaker-turn intervals
  are nonempty half-open windows [startMs, endMs). A speaker-turn index is
  nonnegative. No inference about speaker identity follows from a segment link.
- Explicit startMs/endMs pairs inside transcript wordTimings obey the same
  interval rule. Unknown historical/provider map shapes stay opaque; they are
  not silently normalized into the canonical timing pair.
- Transcript job completedAt cannot precede startedAt when both are supplied.
  Positive width/height/sample rate/channel/bit depth/frame rate and
  nonnegative frame count/bitrate/duration are checked when present.
- A source or evidence-record payloadContentHash requires a nonempty
  payloadHashAlgorithm, and vice versa. This pairs claims about hashes; it does
  not verify content bytes, a capture event, a source's independence or custody.
- Confidence, certainty, credibility and authenticity are separate evidence
  attributes. No schema validator may convert an inference into a verified
  fact. Original bytes, archive IDs, custody chain and disagreement survive
  any extraction, correction, redaction or downstream investigation.

First validate the concrete dtype using the StarLang-generated schema, then
call validate_media_evidence_semantics(document). This reference is part of
the version-locked release closure, not a downstream handwritten schema.
The source-owned fixtures must pass in each maintained consumer, with
language-native implementations of equivalent semantics.

## IR14 consumer handoff

IR14 should pin the final exact StarLang commit, vendor the complete release
(including media_semantics.py and media-evidence-fixtures.json), add a real
current-producer validation gate before StarIntel submission, and run both
positive and negative semantic fixtures through actual consumer runtimes.
Do not treat version-only repinning or a Python-only test as conformance for
Common Lisp, Nim, JS/TS, or other maintained consumers. Existing historical
0.9.x records remain immutable under their explicit reader profile; on
mismatch, preserve original evidence and quarantine the attempted migration.

## Deferred source issues

Typed word-level timeline objects, linked source-artifact/custody transfer
events, archive-content digest verification, cross-document parent-time bounds,
and claim/evidence/source/investigation-target graph consistency need separate
source-owned contracts and cross-runtime fixtures. Do not invent OCR/STT
execution semantics here (PA08/PA09 own actors).

## Inherited pixel metadata conformance

`picture` and `video-frame` extend `image` in the existing 0.10.1 StarLang
source. Their optional `width` and `height` fields consequently inherit the
existing image semantic gate requiring a positive integer **when present**.
The earlier reference validator inadvertently omitted these two inherited
kinds; structurally valid zero/negative dimensions passed semantic validation.
This patch restores that established rule without adding a wire field, creating
another document type, or asserting new evidentiary authenticity.

The source-owned fixtures include two positive and four negative cases for each
inherited kind. Structural validation must pass first. IR14 must exercise these
fixtures through *actual* TypeScript/JavaScript, Python, Nim and Common Lisp
consumers rather than interpreting this Python reference as runtime parity.
Frame timestamps and pixel dimensions are source-relative observations, not a
proof that the media source is genuine or that extracted identities are true.
