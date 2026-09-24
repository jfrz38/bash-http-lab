# Supported HTTP subset

## Purpose

This document defines the protocol behavior that the runtime promises. It is a
deliberately small subset of HTTP/1.1, not an attempt to implement RFC 9110 and
RFC 9112 completely.

Behavior is cumulative unless a later phase explicitly changes it.

## Phase support matrix

| Capability | First phase | Notes |
| --- | --- | --- |
| One HTTP/1.1 request per connection | Phase 1 | The response always closes the connection. |
| Request line parsing | Phase 1 | Method, origin-form target, and version. |
| Header parsing and case normalization | Phase 1 | Needed for safe framing decisions. |
| `GET /health` | Phase 1 | Temporary route before OpenAPI routing. |
| Central response serialization | Phase 1 | Status line, required headers, and body. |
| OpenAPI route and method matching | Phase 2 | Includes path parameters and `404`/`405`. |
| Query and header parameters | Phase 3 | Includes common percent decoding. |
| `Content-Length` request bodies | Phase 3 | JSON, YAML, and text are introduced incrementally. |
| OpenAPI parameter and body validation | Phase 4 | Deliberately limited schema subset. |
| Request ID and structured logging | Phase 5 | Logs go to stderr. |
| Content negotiation | Phase 6 | JSON and YAML responses. |
| Chunked request or response bodies | Deferred | No committed phase. |
| Persistent connections | Deferred | No committed phase. |

## Phase 1 request grammar

Phase 1 accepts a request shaped as follows:

```text
METHOD SP REQUEST_TARGET SP HTTP/1.1 CRLF
HEADER_NAME ":" OWS HEADER_VALUE OWS CRLF
...
CRLF
```

Where:

- `METHOD` is a non-empty uppercase token.
- `REQUEST_TARGET` uses origin form and starts with `/`.
- `SP` is one ASCII space.
- `CRLF` is `\r\n`.
- `OWS` is optional spaces or tabs around a header value.

HTTP/1.0, absolute-form targets, authority-form targets, asterisk-form targets,
and HTTP/2 connection prefaces are unsupported in Phase 1.

The parser separates the raw target into path and raw query string at the first
`?`. Phase 1 does not decode or validate query parameters. Route matching uses
the path only, so `GET /health?probe=true` matches `/health`.

## Request headers

Header names are case-insensitive and are normalized to lowercase for internal
lookup. Surrounding optional whitespace is removed from values; whitespace
inside a value is preserved.

Phase 1 applies these explicit restrictions:

- malformed header lines return `400 Bad Request`;
- obsolete folded header lines are rejected with `400 Bad Request`;
- duplicate header names are rejected with `400 Bad Request` rather than being
  merged incorrectly;
- control characters in names or values are rejected;
- an empty header name is rejected;
- the parser stops at the first empty CRLF line.

The duplicate-header rule is intentionally stricter than HTTP. It may be
revisited when a real use case requires list-valued fields, but Phase 1 must not
silently use first-wins or last-wins behavior.

## Request bodies and framing

- No `Content-Length` means the request has no body.
- `Content-Length: 0` is accepted.
- A valid positive `Content-Length` up to 1 MiB is read exactly.
- A declared length over 1 MiB returns `413 Content Too Large`.
- Premature EOF returns `400 Bad Request`.
- An empty, signed, conflicting, or non-decimal content length returns
  `400 Bad Request`.
- Any `Transfer-Encoding` header returns `501 Not Implemented`.
- A request containing both `Content-Length` and `Transfer-Encoding` returns
  `400 Bad Request` because its framing is ambiguous for this runtime.

Chunked encoding remains deferred. Bodies are stored in private temporary
files so Bash variables do not alter byte content; the files are removed after
the request on success and failure.

## Phase 1 routes

Phase 1 knows one path and one method:

| Method | Path | Status | Body |
| --- | --- | --- | --- |
| `GET` | `/health` | `200 OK` | `{"status":"ok"}` |

The body has no trailing newline and uses `Content-Type: application/json`.

Routing outcomes are:

- `GET /health` returns `200 OK`;
- another method on `/health` returns `405 Method Not Allowed` and `Allow: GET`;
- any other path returns `404 Not Found` regardless of method.

Phase 2 removes the hard-coded rule and obtains `/health` and all other
application routes from OpenAPI.

## Responses

Every Phase 1 response contains at least:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15
Connection: close

{"status":"ok"}
```

Requirements:

- line endings are CRLF;
- `Content-Length` is the exact body byte count;
- exactly one empty line separates headers and body;
- the process exits after writing the complete response;
- response helpers do not emit logs to stdout;
- error bodies have a stable JSON shape and a suitable JSON content type;
- a no-content response, when introduced, has an empty body and length zero.

Phase 1 error bodies use the HTTP reason phrase in this exact shape, without a
trailing newline:

```json
{"error":"Bad Request"}
```

The value changes with the status, for example `Not Found`, `Method Not
Allowed`, `Internal Server Error`, or `Not Implemented`.

The initial central status table includes:

| Code | Reason phrase | Initial use |
| --- | --- | --- |
| 200 | OK | Successful health request. |
| 400 | Bad Request | Invalid request syntax or framing. |
| 413 | Content Too Large | Declared request body exceeds 1 MiB. |
| 404 | Not Found | No matching path. |
| 405 | Method Not Allowed | Known path with unsupported method. |
| 415 | Unsupported Media Type | Introduced with request bodies. |
| 500 | Internal Server Error | Unexpected runtime failure. |
| 501 | Not Implemented | Recognized but unsupported capability or missing handler. |

`401` and `403` are reserved for later authorization work and are not emitted
by the initial runtime.

## Parsing limits

Phase 1 should enforce the following defaults:

| Limit | Default |
| --- | --- |
| Request line | 8 KiB |
| Individual header line | 8 KiB |
| Header count | 100 |
| Total header bytes | 64 KiB |
| Request body | 1 MiB |
| Connection inactivity timeout | 10 seconds |

Exceeding a syntactic size or count limit returns `400 Bad Request` when a
response can still be sent safely. A timeout may close the connection without a
response because the request can be incomplete.

These are educational safety limits, not strong resource controls. Bash line
reading may allocate input before checking its size, and the process-per-
connection listener remains vulnerable to resource exhaustion.

## Phase 2 routing semantics

The first OpenAPI routing subset supports literal segments and whole-segment
path parameters:

```text
/users
/users/{id}
/users/{userId}/posts/{postId}
```

Rules:

- the entire path must match;
- static segments take precedence over parameter segments;
- parameter names come from the template;
- each captured value is exposed once under its parameter name;
- query strings do not participate in path matching;
- a known path with no operation for the request method returns `405`;
- an unknown path returns `404`;
- ambiguous templates are rejected during OpenAPI validation rather than being
  resolved according to document order.

Phase 2 does not percent-decode or normalize paths. Encoded slashes, repeated
slashes, dot segments, and trailing slashes remain literal and distinct;
`/users` therefore differs from `/users/`. Path parameters must occupy an
entire segment and use names that are valid Bash associative-array keys.

The bundled educational contract exposes `GET /health`, collection and detail
routes for books, and collection and detail routes for authors. Its fixed
responses demonstrate routing only; persistence and relationships between
resources are not part of Phase 2.

## Phase 3 request context

Handlers consume three separate associative maps:

- path parameters captured by the router, without percent decoding;
- query parameters parsed from the raw query string;
- lowercase header names with normalized surrounding whitespace.

Query names and values decode `+` as a space and valid `%HH` octets. Decoded
names are limited to ASCII letters, digits, `_`, `.`, `~`, and `-` so they are
safe Bash associative-array keys. Empty or unsafe names, malformed escapes, NUL
escapes, empty `&` segments, and repeated decoded names return `400 Bad
Request`. Repeated headers remain rejected by the request parser, so no map
silently applies first-wins or last-wins behavior.

A non-empty body requires `Content-Type`. The media type is compared
case-insensitively and may include parameters. Supported representations are:

| Media type | Internal representation |
| --- | --- |
| `application/json` | Compact validated JSON file. |
| `application/yaml`, `application/x-yaml` | JSON file converted by Mike Farah `yq` v4. |
| `text/yaml`, `text/x-yaml` | JSON file converted by Mike Farah `yq` v4. |
| `text/plain` | Byte-preserving text file. |

Malformed JSON or YAML, an invalid media type, or a non-empty body without
`Content-Type` returns `400 Bad Request` before the handler runs. A valid but
unsupported media type returns `415 Unsupported Media Type`. `jq` is checked
only when a JSON body needs normalization.

## Phase 4 OpenAPI request validation

After routing and request-context normalization, the runtime validates declared
parameters and request bodies before invoking the handler. Parameters may be
declared at path-item or operation level; an operation declaration with the
same `in` and `name` overrides the path-item declaration. Header names are
matched case-insensitively. Every path placeholder must have a matching
required `in: path` parameter. Undeclared query and header values are allowed.

The supported parameter locations and types are:

| Input | Supported schema types |
| --- | --- |
| Path, query, or header parameter | `string`, `integer`, `number`, `boolean` |
| Top-level request body | `string`, `integer`, `number`, `boolean`, `object`, `array` |

Conversions are intentionally strict. Integer and number parameter values use
JSON number syntax, and boolean parameters are exactly `true` or `false`.
Strings remain decoded strings. Object and array parameters are unsupported
because the request context stores one scalar value per name.

Inline schemas may contain only `type`, `enum`, `minimum`, `maximum`,
`minLength`, `maxLength`, `description`, and `example`. Numeric bounds apply
only to `integer` and `number`; length bounds apply only to `string`. Enum
members must have the declared type. References, composition, formats,
patterns, nested `properties`, array `items`, defaults, nullable values, and
additional JSON Schema or OpenAPI schema keywords are rejected by `validate`
and before `serve` starts rather than ignored.

Request bodies use an inline schema for each declared media type. The supported
declarations are `application/json`, `application/yaml`,
`application/x-yaml`, `text/yaml`, `text/x-yaml`, and `text/plain`. A non-empty
body for an operation without a matching declared media type returns `415
Unsupported Media Type`. A missing required value or body, failed conversion,
type mismatch, enum mismatch, or failed bound returns the central `400 Bad
Request` response. In every case validation finishes before the handler runs.

Full OpenAPI and JSON Schema validation, nested object validation, collection
parameters, coercion aliases such as `1` for boolean, and per-field validation
error responses are explicit non-goals of this phase.

## Phase 5 middleware and request observability

An operation may declare an ordered `x-middlewares` sequence:

```yaml
x-middlewares: [requestId, logging]
```

Only `requestId` and `logging` are supported. The extension must be a sequence
of unique string names; malformed, duplicate, or unknown values make the
OpenAPI document invalid or unsupported before the listener starts. Middleware
runs only after routing, request normalization, and validation succeed.

Before and after hooks both follow declaration order. The pipeline is
synchronous and has no application-level short-circuit response. An internal
hook failure selects `500 Internal Server Error`; a failed before hook skips the
handler while applicable completed hooks still receive their after phase.

`requestId` preserves `X-Request-Id` when it matches
`[A-Za-z0-9._-]{1,128}`. Missing or invalid values are replaced with a UUID from
the supported Linux runtime. The same value is available to handlers as
`REQUEST_ID`, returned in exactly one `X-Request-Id` response header, and used
by logging. Handlers cannot override the middleware-owned header.

`logging` emits one compact JSON object to stderr after response status
selection and before serialization. It contains `requestId`, `method`, `path`,
numeric `status`, and non-negative integer `durationMs`. The path excludes the
query string, and logs never include request bodies or arbitrary header values.
Parse, route, normalization, and validation failures do not run operation
middleware.

## Explicit non-goals

The project does not plan to implement:

- HTTPS or TLS;
- HTTP/2 or HTTP/3;
- WebSockets;
- production-grade request smuggling defenses;
- high concurrency or performance optimization;
- transparent proxy behavior;
- complete HTTP compliance;
- arbitrary binary streaming.
