# Raw JSON wire conformance

Object member names must be unique by decoded JSON string identity within each
object. Duplicate keys are ambiguous and must be rejected at the first raw-text
boundary, even when both values are equal or deeply equal. An escaped spelling
of a name is the same key, including non-BMP surrogate-pair escapes. Sibling
objects and objects in separate array elements have separate scopes. Do not
apply Unicode normalization: `é` and `e` followed by a combining accent are
different JSON keys.

`raw-json-unique-keys.json` holds 27 named cases as **wire strings**, rather than
already-parsed documents: 18 duplicates and 9 valid controls. Pass each `wire`
value verbatim into the SDK's raw parser. Parsing a document before running the
case discards the evidence. The controls retain exact numbers, Unicode, null,
false, literal JSON-looking strings, and ordinary `__proto__` extension keys.

Run the reference gate with:

```sh
python3 tools/test-starintel-raw-json.py
```

Run any canonical SDK CLI against the same raw corpus with one or more
`--adapter NAME=COMMAND` options. Commands consume a canonical `roundtrip`
request on stdin and return its JSON response. The runner concatenates the raw
document into the request without first parsing it. A rejected case must report
a duplicate-key error; a crashed/missing dependency cannot pass the gate.
`--report PATH` writes machine-readable results. For example:

```sh
python3 tools/test-starintel-raw-json.py \
  --adapter 'python=python3 -m starintel_doc.conformance_adapter' \
  --adapter 'nim=/path/to/starintel_canonical'
```

SDK-local fixture copies must remain byte-identical to this authority corpus.
This wire corpus is separate from the frozen 0.10.1 generated release artifacts;
it does not republish or silently alter the schema release. Parsed in-memory
object APIs cannot diagnose duplicate keys already lost by another decoder.
