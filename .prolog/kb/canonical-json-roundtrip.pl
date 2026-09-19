% Canonical JSON round-trip testing facts (verified in star-scrape tests,
% star-lang#137, 2026-09-19).

% star-canonical-json is write-only: no in-tree JSON decoder exists.
% Round-trip tests decode with yason and re-encode through
% starcanonicaljson node constructors, comparing canonical bytes.
roundtrip_decoder(yason_parse).

% Decoder ambiguity rules that produced latent round-trip drift:
% - (listp nil) is true, so a decoded JSON false (NIL) collides with a
%   decoded empty array unless arrays are decoded as vectors.
% - Strings are vectors: test STRINGP before VECTORP or strings are
%   re-encoded as character arrays.
yason_roundtrip_rule(bind_parse_json_arrays_as_vectors_true).
yason_roundtrip_rule(test_nil_before_listp).
yason_roundtrip_rule(test_stringp_before_vectorp).
roundtrip_bug_symptom('"required":false re-encoded as []').
roundtrip_bug_symptom('manifest string re-encoded as character array').

% starlang-manifest-json-object drops plist keys with NIL values (except
% :required/:default/array keys), so canonical manifest JSON never
% contains null; decoded NIL in an object is always JSON false.
manifest_json_omits_nil_values(true).
