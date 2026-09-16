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

Valid HTTP responses remain responses even when their status is 4xx or 5xx.
Transport failures are signaled as `starhttpport:http-transport-error` with a
backend-neutral `http-transport-error-kind`. Error reports intentionally omit the
request URL, headers, nested backend condition text, credentials, cookies, and
query values.

Dexador treats an exhausted redirect budget as the final HTTP response rather
than a transport exception. The adapter preserves that response and its final URL;
higher layers decide whether that status is acceptable.
