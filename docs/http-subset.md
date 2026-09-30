# Supported HTTP subset

## Purpose

This document defines the protocol behavior promised by `bash-http-lab`. The
runtime deliberately implements a small subset of HTTP/1.1 and OpenAPI 3.0. It
does not attempt complete compliance with HTTP, OpenAPI, or JSON Schema.

Correctness-affecting unsupported input is rejected rather than silently
approximated.

## Request grammar

Requests have this shape:

```text
METHOD SP REQUEST_TARGET SP HTTP/1.1 CRLF
HEADER_NAME ":" OWS HEADER_VALUE OWS CRLF
...
CRLF
OPTIONAL_BODY
```

Where:

- `METHOD` is a non-empty uppercase token;
- `REQUEST_TARGET` uses origin form and starts with `/`;
- `SP` is one ASCII space;
- `CRLF` is `\r\n`;
- `OWS` is optional spaces or tabs around a header value.

HTTP/1.0, absolute-form targets, authority-form targets, asterisk-form targets,
and HTTP/2 connection prefaces are unsupported.

The parser separates the raw target into a path and query string at the first
`?`. The query string does not participate in route matching.

## Headers

Header names are case-insensitive and normalized to lowercase. Surrounding
optional whitespace is removed from values; whitespace inside a value is
preserved.

The parser rejects the following with `400 Bad Request`:

- malformed header lines;
- obsolete folded headers;
- duplicate header names;
- control characters in names or values;
- empty header names;
- headers exceeding the documented count or size limits.

Rejecting duplicates is intentionally stricter than HTTP. The internal header
map stores one value per normalized name and does not silently apply first-wins
or last-wins behavior.

## Request framing and bodies

- No `Content-Length` means the request has no body.
- `Content-Length: 0` is accepted.
- A valid positive length up to 1 MiB is read exactly.
- A declared length over 1 MiB returns `413 Content Too Large`.
- Premature EOF returns `400 Bad Request`.
- Empty, signed, conflicting, or non-decimal lengths return `400 Bad Request`.
- Any `Transfer-Encoding` returns `501 Not Implemented`.
- Sending both `Content-Length` and `Transfer-Encoding` returns `400 Bad
  Request` because framing is ambiguous for this runtime.

A non-empty body requires `Content-Type`. The media type is compared
case-insensitively. This subset accepts zero or more unique parameters written
as `token=token`, separated by semicolons; malformed or quoted parameters are
rejected.

| Media type | Internal representation |
| --- | --- |
| `application/json` | Compact validated JSON file |
| `application/yaml`, `application/x-yaml` | JSON file converted by Mike Farah `yq` v4 |
| `text/yaml`, `text/x-yaml` | JSON file converted by Mike Farah `yq` v4 |
| `text/plain` | Byte-preserving text file |

JSON bodies must contain exactly one top-level JSON value, and YAML bodies must
contain exactly one document. Malformed JSON or YAML, multiple values or
documents, an invalid media type, or a non-empty body without `Content-Type`
returns `400 Bad Request`. A valid but unsupported media type returns `415
Unsupported Media Type`.

Raw and normalized bodies are stored in private temporary files and removed on
every handled exit path. Binary media types and chunked bodies are unsupported.

## Routes

Routes come exclusively from the supplied OpenAPI 3.0 document. The supported
path templates contain literal segments and parameters occupying a complete
segment:

```text
/users
/users/{userId}
/users/{userId}/posts/{postId}
```

Routing follows these rules:

- the complete path must match;
- static segments take precedence over parameterized segments;
- query strings do not participate in path matching;
- captured parameters are exposed by their template names;
- a known path with no operation for the method returns `405 Method Not
  Allowed` and an `Allow` header;
- an unknown path returns `404 Not Found`;
- ambiguous templates are rejected when the OpenAPI document is loaded.

Paths are not percent-decoded or normalized. Encoded slashes, repeated slashes,
dot segments, and trailing slashes remain distinct. `/users` and `/users/` are
therefore different paths.

The bundled `openapi.yaml` defines this example API:

| Method | Path | Operation |
| --- | --- | --- |
| `GET` | `/health` | Runtime health |
| `GET` | `/users` | List users |
| `POST` | `/users` | Create a user |
| `GET` | `/users/{userId}` | Read one user |
| `DELETE` | `/users/{userId}` | Delete one user |

Other documents matching the supported subset may define a different
application. The users persistence adapter is loaded only when the document
uses a bundled users operation ID.

### OpenAPI document loading

The CLI validates this runtime's supported OpenAPI 3.0 subset, not full OpenAPI
conformance. At the document root it accepts `openapi`, `info`, `paths`, `tags`,
and `externalDocs`. Path items may contain operations, `parameters`, `summary`,
and `description`.

Supported operation methods are `GET`, `PUT`, `POST`, `DELETE`, `OPTIONS`, and
`PATCH`. `HEAD` and `TRACE` are rejected because their special HTTP semantics
are not implemented. Operations may contain `tags`, `summary`, `description`,
`externalDocs`, `deprecated`, `operationId`, `parameters`, `requestBody`,
`responses`, and `x-middlewares`. Each operation must declare at least one
supported response.

Other root, path-item, or operation fields are rejected. This includes
behavioral features the runtime would otherwise ignore, such as `security`,
`servers`, and `callbacks`. References and component-based schemas are also
outside the subset.

## Request context

Handlers consume separate associative maps for:

- path parameters captured by the router without percent decoding;
- decoded query parameters;
- lowercase headers with normalized surrounding whitespace.

Query names and values decode `+` as a space and valid `%HH` octets. Decoded
names may contain ASCII letters, digits, `_`, `.`, `~`, and `-`. Empty or unsafe
names, malformed escapes, NUL escapes, empty `&` segments, and repeated decoded
names return `400 Bad Request`.

One value is retained per query name. Undeclared query and header values remain
available to handlers.

## OpenAPI request validation

Validation runs after routing and request normalization and before middleware or
the handler. Parameters can be declared at path-item or operation level. An
operation declaration with the same location and name overrides the path-item
declaration. Header names match case-insensitively.

Every path placeholder requires a corresponding `required` path parameter.

| Input | Supported schema types |
| --- | --- |
| Path, query, or header parameter | `string`, `integer`, `number`, `boolean` |
| Top-level request body | `string`, `integer`, `number`, `boolean`, `object`, `array` |

`text/plain` request bodies support only a top-level `string` schema because no
numeric, boolean, object, or array coercion is performed.

Integer and number parameters use JSON number syntax. Boolean parameters must
be exactly `true` or `false`. Strings remain decoded strings. Object and array
parameters are unsupported because the request context stores one scalar value
per parameter.

Inline schemas may use:

- `type`;
- `enum`;
- `minimum` and `maximum` for numeric values;
- `minLength` and `maxLength` for strings;
- `description` and `example` as annotations.

Enum members must have the declared type. References, composition, formats,
patterns, nested properties, array items, defaults, nullable values, and other
unsupported correctness-affecting keywords cause document validation to fail.

Request bodies use an inline schema for each declared media type. A non-empty
body without a matching declared media type returns `415 Unsupported Media
Type`. Missing required values, conversion failures, type mismatches, enum
mismatches, and failed bounds return the central `400 Bad Request` response.

Full OpenAPI and JSON Schema validation, nested object validation, collection
parameters, coercion aliases such as `1` for boolean, and field-level validation
error responses are unsupported.

## Middleware

An operation selects ordered middleware with an extension such as:

```yaml
x-middlewares: [requestId, logging]
```

Only `requestId` and `logging` are supported. The value must be a sequence of
unique string names. Malformed, duplicate, or unknown entries make the OpenAPI
document invalid or unsupported before the listener starts.

Middleware runs only after successful routing, normalization, and validation.
Before and after hooks both follow declaration order. There is no
application-level short-circuit response. An internal hook failure selects `500
Internal Server Error`; a failed before hook skips the handler while completed
middleware can still receive its applicable after hook.

`requestId` preserves `X-Request-Id` when it matches
`[A-Za-z0-9._-]{1,128}`. Missing or invalid values are replaced with a Linux
UUID. The value is exposed to handlers, returned in exactly one
`X-Request-Id` response header, and included in request logs.

`logging` writes one compact JSON object to stderr after final status selection
and representation serialization, but before the response bytes are written.
It contains `requestId`, `method`, `path`, numeric
`status`, and non-negative integer `durationMs`. It excludes query values,
headers, and request bodies. Failures before operation middleware starts do not
produce this request log.

## Responses and content negotiation

Handlers return one structured value represented internally as JSON. The
response builder validates and compacts it before selecting an output:

| Media type | Serialization |
| --- | --- |
| `application/json` | Compact JSON |
| `application/yaml` | YAML generated from the JSON value |
| `text/yaml` | The same YAML serialization with the requested alias |

Missing or empty `Accept` selects `application/json`. The supported `Accept`
subset includes comma-separated exact ranges, `application/*`, `text/*`,
`*/*`, and optional `q` values from zero through one with at most three decimal
places.

Matching is case-insensitive. A representation's most specific matching range
determines its quality. Higher non-zero quality wins, then specificity, then
the server preference `application/json`, `application/yaml`, and `text/yaml`.
A specific `q=0` excludes that representation even if a wildcard permits it.
Malformed alternatives and unsupported parameters do not match.

If no representation is acceptable, the server returns a JSON `406 Not
Acceptable`. Other central errors participate in negotiation.

Every response contains a status line, headers, one empty CRLF line, and its
body. The response builder guarantees:

- CRLF line endings;
- byte-accurate `Content-Length`;
- an appropriate `Content-Type`;
- `Connection: close`;
- exactly one response per connection;
- no diagnostic output on stdout.

The OpenAPI adapter accepts only statuses that the response writer can emit:
`200`, `201`, `400`, `404`, `405`, `406`, `413`, `415`, `500`, and `501`. A
handler may select an undocumented supported status, but the runtime writes a
development warning to stderr. OpenAPI `default` responses and response-schema
validation are unsupported.

Response content declarations are inspected for mock examples. They do not
restrict live handler negotiation: structured handler output is always offered
as the runtime's fixed JSON and YAML representations.

## Central errors

Central errors use a stable structured shape:

```json
{"error":"Bad Request"}
```

The runtime defines these status codes:

| Code | Reason phrase | Use |
| --- | --- | --- |
| `400` | Bad Request | Invalid syntax, framing, representation, or declared input |
| `404` | Not Found | Unknown route or missing example resource |
| `405` | Method Not Allowed | Known path with an unsupported method |
| `406` | Not Acceptable | No supported response representation matches |
| `413` | Content Too Large | Declared body exceeds 1 MiB |
| `415` | Unsupported Media Type | Valid but unsupported request media type |
| `500` | Internal Server Error | Unexpected runtime, handler, or middleware failure |
| `501` | Not Implemented | Recognized unsupported framing or missing handler |

Successful handlers in the bundled API return `200 OK` or `201 Created`.

## Limits

| Limit | Default |
| --- | --- |
| Request line | 8 KiB |
| Individual header line | 8 KiB |
| Header count | 100 |
| Total header bytes | 64 KiB |
| Request body | 1 MiB |
| Connection inactivity timeout | 10 seconds |

Exceeding a syntactic size or count limit returns `400 Bad Request` when a
response can still be sent safely. A timeout may close an incomplete connection
without a response.

These limits are educational safety checks, not complete resource controls.
Bash may allocate a line before checking its size, and the process-per-
connection listener remains vulnerable to resource exhaustion.

## Explicit non-goals

The project does not support:

- HTTPS or TLS;
- HTTP/2 or HTTP/3;
- persistent connections or pipelining;
- chunked request or response bodies;
- WebSockets;
- arbitrary binary streaming;
- transparent proxy behavior;
- high concurrency or performance optimization;
- complete HTTP, OpenAPI, or JSON Schema compliance;
- production-grade request smuggling or denial-of-service defenses.
