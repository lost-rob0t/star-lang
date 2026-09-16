# StarLang HTTP systems

`star-http-port` owns only the backend-neutral synchronous request/response contract.
Concrete HTTP implementations live in separate ASDF systems and return the same
`starhttpport:http-response` values.

| ASDF system | Backend | Ownership |
| --- | --- | --- |
| `star-http-port` | injected function | request/response types, validation, client port, typed transport-error taxonomy |
| `star-http-dexador` | Dexador | synchronous concrete HTTP execution and Dexador condition mapping |

Loading or testing `star-http-port` alone must not load Dexador. Consumers should
accept a `starhttpport:http-client`; composition code that selects Dexador loads
`star-http-dexador` and calls `starhttpdexador:make-dexador-http-client`.

## Dexador client policy

`make-dexador-http-client` makes connection policy explicit per client instead of
inheriting Dexador's mutable process defaults. With no options it uses a direct
connection (`:proxy nil`), verifies TLS (`:tls-policy :verify`), and disables
Dexador's process-global connection pool.

Callers may supply `:proxy` and may select `:tls-policy :insecure` only when that
policy is intentionally chosen by composition code. Callers that need connection
reuse may supply `:pool` with a Dexador connection-pool object. The client executes
requests with that exact pool; the caller that supplied the pool owns its lifetime
and cleanup. Separate clients therefore do not silently share the default mutable
Dexador pool.

Valid HTTP responses remain responses even when their status is 4xx or 5xx.
Transport failures are signaled as `starhttpport:http-transport-error` with a
backend-neutral `http-transport-error-kind`. Error reports intentionally omit the
request URL, headers, nested backend condition text, credentials, cookies, and
query values.

Dexador treats an exhausted redirect budget as the final HTTP response rather
than a transport exception. The adapter preserves that response and its final URL;
higher layers decide whether that status is acceptable.

## Response body representation

This slice deliberately preserves the existing Dexador body representation for
compatibility instead of introducing a second normalization contract. Text
responses may be Dexador-decoded Common Lisp strings; binary responses remain
`(vector (unsigned-byte 8))`. `star-http-dexador` passes that body through
unchanged into `starhttpport:http-response`. A future canonical-body migration is
separate scope and must not be inferred from this compatibility behavior.
