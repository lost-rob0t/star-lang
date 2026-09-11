% Shared RFC STAR URI architecture (durable knowledge, verified 2026-09-11).
% Normative sources:
%   - STAR-SERVER-041 "RFC 3986 STAR URI Authority Routing Extension"
%     (roam/design/star-server/STAR-SERVER-041-star-uri-authority-routing-protocol.org)
%   - STAR-LANG-004 amendment "STAR Service URI Discovery and Dispatch"
%     (roam/design/star-lang/STAR-LANG-004-star-service-uri-discovery.org)
%   - lost-rob0t/star-lang issue #52 (tuple canonical ownership superseded)

% Grammar (STAR-SERVER-041 v1):
%   star-uri = "star://" authority "/" resource-kind [ "/" resource-path ]
%   authority = RFC 3986 reg-name, lowercase; userinfo and transport ports
%   forbidden. Path segments use pchar; percent-encoded unreserved chars
%   normalize; remaining escapes serialize uppercase hex; "."/".." segments
%   rejected before and after percent normalization; query and fragment
%   rejected; resource kind must be reviewed.
star_uri_grammar(star_server_041_v1).
star_uri_resource_kinds([actor, service, document, target, dataset, relation, job]).
star_uri_value_model([authority, path_segments]).   % no domain/address/actor-name fields

% Authoritative implementation inside this repository:
%   star-actor-protocol/src/star-uri.lisp (canonical authority; the shared
%   StarLang STAR URI library that starintel-server's temporary
%   :star.star-uri layer must be replaced by) and
%   star-actor-protocol/src/service-uri.lisp (explicit legacy tuple
%   compatibility API only).
uri_implementation_files(['star-actor-protocol/src/star-uri.lisp',
                          'star-actor-protocol/src/service-uri.lisp']).

% Legacy compatibility invariants (STAR-SERVER-041 / STAR-LANG-004):
%   - parse-star-uri REJECTS the legacy tuple;
%   - the tuple parses only through parse-star-service-uri / the prototype
%     compatibility shell;
%   - migrate-legacy-star-uri requires an explicit :to canonical target or
%     an explicit :map; the result normalizes immediately into the canonical
%     representation;
%   - the legacy domain is never reused as an authority and no
%     legacy.<domain> authority is invented (star-bbpd's legacy.<domain>
%     rewrite is a BBPD application choice, not this model);
%   - new code never emits the tuple form.
legacy_tuple(input_only).
legacy_tuple_accepted_at([star_actor_protocol_service_uri_module,
                          prototype_service_uri_shell]).
legacy_migration_rule(explicit_to_or_map_only).
legacy_domain_never_becomes_authority(true).

% Conformance fixtures are shared with the reviewed starintel-server suite
% (t/star-uri-test.lisp, t/star-actor-identity-test.lisp): the fixture set
% in star-actor-protocol/tests/star-actor-protocol-tests.lisp is ported from
% there and must not fork a second grammar.
conformance_fixture_provenance(starintel_server_star_uri_suite).
second_uri_parser_forbidden(true).

% Compiler/runtime projections:
%   - actor :service-uri must be a canonical actor URI whose terminal
%     resource-path segment equals the actor contract name (one- and
%     multi-segment actor paths are both valid; leading segments have no
%     domain semantics);
%   - starlang-runtime defaults undeclared actors to
%     star://<starlang-runtime-authority>/actor/<name> with
%     *star-runtime-authority* initially "local";
%   - runtime-directory entries validate canonical actor URIs plus
%     optional :authority/:resource-kind/:resource-path metadata;
%     :domain/:address are no longer validated fields;
%   - the wire dispatcher translates malformed or legacy-tuple URI targets
%     into wire-dispatcher-invalid-actor-error.
actor_uri_name_rule(terminal_resource_path_segment_equals_actor_name).
runtime_default_authority('local').
runtime_directory_metadata_fields([authority, resource_kind, resource_path]).
dispatcher_uri_route_error(wire_dispatcher_invalid_actor_error).