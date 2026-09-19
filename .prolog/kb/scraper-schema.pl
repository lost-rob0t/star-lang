% Scraper schema contract slice (star-lang#137, verified 2026-09-19).

% The website-scraper schema authority is the versioned .star vocabulary;
% star-scrape owns only contract compilation over compiled IR.
final_owner(scraper_schema_contracts, star_scrape).
schema_authority(scraper_vocabulary, 'fixtures/star-scrape-core.star').
vocabulary_identity('org.starscrape/scraper@1', '1.0.0').
scraper_manifest_schema('org.starscrape/scraper-manifest@1').

% Policy validation is two-stage: the generic portable-wire validator
% interprets the compiled vocabulary (types, required fields, unknown-field
% rejection, enums, integer min/max); the closed policy gate adds only the
% domain rules the vocabulary cannot express (SSRF deny-by-default, https
% bare-hostname origins, media types, selector shapes, pagination
% kind/selector cross-rules).
scraper_validation_order([generic_portable_wire_value, closed_policy_gate]).
generic_wire_validator_does_not_enforce_scalar_patterns(true).
ssrf_posture(private_network_forbid_by_default).

% Closed effect-capability allowlist lives in the .star enum; widening it
% is a vocabulary version change, never a code change.
capability_allowlist([net_https_fetch, parse_html, rate_limit_scheduler,
                      crawl_budget, starintel_documents]).

% star-scrape grew compiler/JSON dependencies for schema compilation; the
% graph stays acyclic because nothing depends on star-scrape.
asdf_dependency(star_scrape, [star_http_port, starlang_runtime,
                              star_actor_protocol, starlang_compiler,
                              star_canonical_json]).

% Runtime actor consumption of scraper manifests (manifest -> runtime
% scrape plan execution) is deliberately not in this slice.
scraper_runtime_consumption(follow_up_slice).
