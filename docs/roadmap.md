# Implementation roadmap

## Delivery rules

The project is implemented in small, demonstrable phases. Work proceeds to the
next phase only when the current phase meets its acceptance criteria.

Every implementation phase must:

- keep the runtime in Bash;
- add tests for new observable behavior;
- pass the complete existing test suite;
- pass `shellcheck` and formatting checks;
- update documentation when a contract or supported subset changes;
- reject correctness-affecting unsupported input explicitly;
- avoid adding dependencies without a concrete benefit.

The order below is intentional, but a phase may be split into smaller pull
requests. A later feature must not be pulled into an earlier phase merely to
make the architecture look complete.

## Phase 0: Documentation

**Goal:** Establish scope, boundaries, protocol behavior, decisions, and
acceptance criteria before writing the runtime.

### Deliverables

- documentation index;
- architecture and component boundaries;
- initial HTTP subset;
- technical decision log;
- phased roadmap.

### Acceptance criteria

- The documents agree on platform, dependencies, CLI evolution, and phase
  boundaries.
- Phase 1 can be implemented without deciding its public behavior during the
  implementation.
- Future phases describe outcomes without prematurely fixing internal APIs.
- No runtime code or unused project structure is introduced.

## Phase 1: Minimal HTTP runtime

**Goal:** Demonstrate a complete TCP-to-handler-to-response cycle with one
endpoint and no OpenAPI routing.

### Scope

1. Create only the repository directories needed by this phase.
2. Add the `bin/bash-http` CLI with help and `serve` commands.
3. Validate the Bash version, host, port, and command-specific dependencies.
4. Start a loopback `socat` listener with a configurable host and port.
5. Delegate each connection to one private Bash connection operation.
6. Parse the Phase 1 request line and headers defined in
   [HTTP subset](http-subset.md).
7. Implement temporary routing for `GET /health`, including `404` and `405`.
8. Invoke a health handler returning `{"status":"ok"}`.
9. Serialize central HTTP responses with correct CRLF and byte length.
10. Add central errors for `400`, `404`, `405`, `500`, and `501`.
11. Add a small Bash test harness and deterministic unit tests.
12. Add integration tests that start the real listener and call it with
    `curl`.
13. Add a Makefile as the canonical developer interface.
14. Update the top-level README with setup and usage after behavior exists.

### Planned files

```text
bin/bash-http
lib/dependencies.sh
lib/server.sh
lib/request.sh
lib/response.sh
lib/errors.sh
handlers/health.sh
tests/test-helper.sh
tests/unit/*
tests/integration/*
Makefile
```

The exact split may become smaller if a file would contain only ceremonial
delegation. `router.sh` should be introduced in Phase 2 unless the Phase 1
implementation demonstrates a real need for it.

### Public CLI

```text
bash-http help
bash-http serve [--host HOST] [--port PORT]
```

Defaults:

```text
host: 127.0.0.1
port: 8080
```

`routes` and `validate` may be recognized but return a clear not-yet-available
message and non-zero exit status. They must not pretend to inspect a document.

### Test strategy

Unit tests cover the smallest boundary that can expose each defect:

- valid and invalid request lines;
- CRLF handling;
- header normalization and malformed headers;
- duplicate and excessive headers;
- unsupported body framing;
- path and query separation;
- status and required response headers;
- byte-accurate `Content-Length`;
- `404` versus `405` selection;
- dependency and CLI argument failures.

Integration tests keep the real collaboration between Bash, `socat`, and
`curl`:

- listener startup and readiness;
- successful `GET /health`;
- query string on `/health`;
- unknown path;
- unsupported method on `/health` and `Allow: GET`;
- response headers and exact body;
- diagnostics not corrupting the response;
- server cleanup after the test.

Tests use a configurable test port, bounded readiness retries, and `trap`-based
cleanup. They must not rely on arbitrary sleeps as the only readiness signal.

### Make targets

```text
make                    # dynamic help, the default target
make help               # list public targets
make test               # all tests
make test-unit          # unit tests only
make test-integration   # integration tests only
make lint               # shellcheck
make format             # shfmt write mode
make format-check       # shfmt verification only
make run                # local server
make check              # lint, format check, and tests
```

Targets must be non-interactive and deterministic except `run`, which is a
foreground development process. The Makefile must not install global tools.

### Acceptance criteria

- On Linux or WSL with required tools, `bash-http serve` listens on loopback by
  default.
- `curl http://127.0.0.1:8080/health` receives `200`, the documented headers,
  and exactly `{"status":"ok"}`.
- `/health?probe=true` reaches the same handler.
- An unknown path returns `404`.
- A non-GET method on `/health` returns `405` with `Allow: GET`.
- Malformed request syntax returns `400` when a response can safely be sent.
- Unsupported body framing follows the rules in `http-subset.md`.
- Logs and diagnostics are absent from the HTTP response stream.
- The listener and test child processes are cleaned up reliably.
- `make`, `make help`, and every documented target behave as described.
- `make check` passes from a clean checkout with dependencies already installed.

### Explicitly deferred

- reading OpenAPI;
- application route discovery;
- request bodies;
- parameter decoding and validation;
- middleware and structured logging;
- content negotiation;
- users persistence.

## Phase 2: OpenAPI routing

**Goal:** Make an OpenAPI 3.0 document the source of truth for routes and
handler identifiers.

### Scope

- load a local OpenAPI YAML file with Mike Farah `yq` v4;
- validate the document version and required path operation fields;
- discover supported HTTP methods, path templates, and `operationId` values;
- reject duplicate operation IDs and ambiguous path templates;
- implement literal and whole-segment parameter matching;
- prioritize static routes over parameterized routes;
- expose captured path parameters to handlers;
- distinguish `404` from `405` using discovered paths and methods;
- resolve handler scripts and functions safely from `operationId`;
- return `501` when a declared operation has no handler in development mode;
- replace the temporary hard-coded health route with an OpenAPI operation;
- implement functional `routes` and structural `validate` commands.

### CLI

```text
bash-http serve OPENAPI_FILE [--host HOST] [--port PORT]
bash-http routes OPENAPI_FILE
bash-http validate OPENAPI_FILE
```

### Acceptance criteria

- No application route is registered in Bash independently of OpenAPI.
- `routes` prints deterministic method, path, and operation columns.
- Static and parameterized routes produce the expected precedence.
- Multiple path parameters are captured under their documented names.
- Unknown paths and unsupported methods retain correct `404`/`405` behavior.
- Invalid and unsupported OpenAPI definitions produce distinct actionable
  errors before the listener starts.
- A malicious `operationId` cannot select an arbitrary path or execute shell
  syntax.
- The Phase 1 HTTP tests remain green after routing is replaced.

### Adopted implementation decisions

- paths are matched literally without normalization or percent decoding;
- the standard OpenAPI 3.0 HTTP operation keys are recognized;
- handlers live in the runtime's fixed `handlers/` directory;
- routes use direct Bash arrays rather than generated code.

## Phase 3: Complete request context

**Goal:** Build the request context needed by realistic handlers.

**Status:** Complete.

### Scope

- normalized request headers and helper access;
- query parsing with common percent decoding;
- path, query, and header parameter maps;
- `Content-Length` body reading with bounded size;
- premature EOF and invalid length handling;
- media type parsing;
- JSON validation through `jq`;
- YAML-to-JSON normalization through Mike Farah `yq` v4;
- plain text bodies;
- `415 Unsupported Media Type`.

### Acceptance criteria

- The parser reads exactly the declared body byte count.
- Structured bodies have a consistent internal JSON representation.
- Malformed JSON or YAML returns a client error before the handler runs.
- Required parsing tools are checked only for operations that need them.
- Temporary body resources are private and always cleaned up.

### Adopted implementation decisions

- request bodies are limited to 1 MiB and stored in private temporary files;
- over-limit bodies return `413`, unsupported media types return `415`, and
  malformed framing or representations return `400`;
- query decoding supports `+` and `%HH`, while paths remain literal;
- repeated decoded query names are rejected rather than silently collapsed;
- JSON and YAML share a normalized JSON-file representation for handlers.

## Phase 4: OpenAPI validation subset

**Goal:** Validate request values against a deliberately small documented
subset before invoking handlers.

**Status:** Complete.

### Initial subset

- parameter locations: path, query, and header;
- required parameters and request bodies;
- types: string, integer, number, boolean, object, and array;
- constraints: `enum`, `minimum`, `maximum`, `minLength`, and `maxLength`;
- declared request media types.

### Acceptance criteria

- Invalid values produce stable `400` responses and do not invoke handlers.
- Unsupported schema keywords that could affect correctness fail validation of
  the OpenAPI document instead of being ignored.
- The supported subset is documented with examples and boundary tests.
- Full OpenAPI and JSON Schema compliance is still an explicit non-goal.

### Adopted implementation decisions

- path, query, and header parameters are scalar; object and array schemas are
  supported only for top-level request bodies;
- path-item parameters are inherited and operation parameters override them by
  location and name;
- request schemas are inline and flat, with unsupported correctness-affecting
  keywords rejected during document validation;
- validation metadata uses direct Bash arrays keyed by operation ID, while
  `jq` performs runtime type and constraint checks only for operations that
  declare validation rules;
- undeclared query and header values remain available to handlers, while a
  non-empty body with no matching declared media type returns `415`.

## Phase 5: Middleware and request observability

**Goal:** Demonstrate a simple synchronous middleware pipeline.

**Status:** Complete.

### Scope

- resolve ordered middleware from `x-middlewares`;
- add `logging` and `requestId` middleware;
- preserve a valid client `X-Request-Id` or generate one;
- expose the request ID to handlers;
- return `X-Request-Id` in the response;
- emit one JSON request log to stderr using `jq`;
- include request ID, method, path, status, and duration in milliseconds.

### Acceptance criteria

- Middleware order follows the OpenAPI extension.
- Unknown middleware fails clearly during startup or validation.
- Logs are valid JSON and never appear in the response stream.
- Request IDs are stable across context, response, and log entry.
- The pipeline remains synchronous and understandable in Bash.

### Adopted implementation decisions

- `x-middlewares` is an operation-level sequence containing only `requestId`
  and `logging`; malformed, duplicate, and unknown entries fail document
  validation;
- before and after hooks run in declaration order after successful request
  validation, with no application short-circuit contract;
- valid request IDs match `[A-Za-z0-9._-]{1,128}`; otherwise Linux supplies a
  UUID through `/proc/sys/kernel/random/uuid`;
- logging emits one compact `jq`-built object after handler status selection and
  before response serialization.

## Phase 6: Representation and content negotiation

**Goal:** Support multiple input and output representations without rewriting
handlers.

**Status:** Complete.

### Scope

- JSON, `application/yaml`, `text/yaml`, and `text/plain` input as applicable;
- internal JSON representation for structured values;
- JSON and YAML output serialization;
- basic `Accept` negotiation;
- `406 Not Acceptable` when no supported response representation matches;
- awareness of documented OpenAPI response status codes;
- development warnings for undocumented handler status codes.

### Acceptance criteria

- Handlers can return one structured result for JSON or YAML serialization.
- Negotiation behavior and fallback rules are documented and tested.
- Unsupported request and response media types have distinct errors.
- Response-schema validation remains deferred.

### Adopted implementation decisions

- handlers submit one JSON structured value and do not choose an output media
  type;
- missing or empty `Accept` selects JSON, while exact ranges, `type/*`, `*/*`,
  and quality values select between `application/json`, `application/yaml`, and
  `text/yaml`;
- a more specific range determines a representation's quality, and ties use
  the stable server preference JSON, `application/yaml`, then `text/yaml`;
- `q=0` excludes a representation and no acceptable representation selects the
  central JSON `406` response;
- OpenAPI response metadata tracks explicit three-digit statuses; an
  undocumented handler status emits a warning but is still served;
- response schemas and OpenAPI `default` responses remain unsupported.

## Phase 7: Developer tooling and example API

**Goal:** Add tools that depend on a stable core and exercise the complete
runtime with a small users API.

### Scope

- `generate` missing handler files without overwriting existing files by
  default;
- `mock` documented responses from OpenAPI examples;
- users API operations for health, list, read, create, and delete;
- intentionally primitive JSON-file persistence in `data/users.json`;
- complete integration scenarios for the example API.

### Acceptance criteria

- Generation is deterministic and non-destructive by default.
- Mock mode selects only documented examples and requires no handler.
- The example API exercises routing, parameters, bodies, validation,
  middleware, and representations.
- Persistence limitations and concurrent-write risks are explicit.
- Tooling remains secondary to the runtime and does not duplicate its parsing
  or routing logic.

## Project non-goals

The roadmap intentionally excludes:

- production readiness;
- HTTPS and certificate management;
- HTTP/2 and HTTP/3;
- WebSockets;
- high concurrency and performance optimization;
- complete OpenAPI or JSON Schema support;
- manually implemented TCP sockets;
- replacement of real application frameworks.
