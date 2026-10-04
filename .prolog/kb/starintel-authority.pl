% Verified StarIntel schema authority and artifact workflow.

starintel_authority_library('org.starintel/core@1', '0.10.1').
starintel_authority_source('specs/starintel/0.10.1/core.star').
starintel_compatibility_source('specs/starintel/0.10.1/compatibility.json').
starintel_release_lock('specs/starintel/0.10.1/release-lock.json').
starintel_canonical_wire_key_style(lower_camel_case).
starintel_legacy_key_style_is_input_only(snake_case).

% Exact decimals are strings on the wire. Range validation must parse them to
% exact rationals; numberp alone skips minimum/maximum enforcement.
exact_decimal_range_validation(exact_rational_parse).

starintel_release_generator('tools/generate-starintel-release.lisp').
starintel_release_finalizer('tools/finalize-starintel-release.py').
