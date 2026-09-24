# Architecture

## Purpose

The runtime exists to make the responsibilities normally hidden by HTTP
frameworks visible and understandable. It favors small Bash modules, explicit
data flow, and limited protocol support over completeness or performance.

The architecture must demonstrate this lifecycle:

```text
TCP connection
    -> HTTP request parsing
    -> route matching
    -> request context creation
    -> validation
    -> middleware
    -> handler execution
    -> response construction
    -> HTTP response
```

The early phases implement only part of this lifecycle. A phase must reject an
unsupported feature explicitly when silently accepting it could produce an
incorrect result.

## System context

```text
curl or another HTTP client
            |
            v
     socat TCP listener
            |
            | stdin/stdout for one connection
            v
   Bash connection process
            |
            +-> request parser
            +-> router
            +-> validation       (Phase 4)
            +-> middleware       (Phase 5)
            +-> handler
            +-> response builder
```

`socat` owns TCP concerns. It starts one Bash process per accepted connection.
That process reads one request, writes one response, and exits. Persistent
connections and multiple requests per connection are deliberately unsupported
in the initial design.

## Architectural invariants

1. Bash is the application runtime.
2. HTTP response bytes are the only data written to stdout while handling a
   connection.
3. Logs, warnings, and diagnostics are written to stderr.
4. Client-controlled data is never evaluated as shell code or interpolated
   into a command string.
5. Transport code does not contain routing, handler, or OpenAPI rules.
6. Parsing code does not emit HTTP responses directly.
7. Handlers do not construct raw HTTP status lines or framing headers.
8. Starting in Phase 2, application routes are discovered from OpenAPI and are
   not registered a second time in Bash.
9. Unsupported protocol or OpenAPI features fail explicitly when ignoring
   them could change behavior.

## Planned repository structure

The structure will be introduced incrementally. Empty modules and directories
should not be created before a phase needs them.

```text
bin/
  bash-http              Public CLI entry point
lib/
  dependencies.sh        Command-specific dependency checks
  server.sh              Listener and connection orchestration
  request.sh             HTTP request parsing
  response.sh            HTTP response construction
  errors.sh              Central HTTP error responses
  openapi.sh             OpenAPI loading and route discovery
  router.sh              Route matching and handler resolution
  params.sh              Path, query, and header parameter context
  body.sh                Request body storage and normalization
  validation.sh          Supported schema constraints (Phase 4)
  middleware.sh          Synchronous middleware pipeline (Phase 5)
handlers/
  health.sh              Initial health handler
middleware/
  logging.sh             Structured request logging (Phase 5)
  request-id.sh          Request ID middleware (Phase 5)
tests/
  test-helper.sh
  unit/
  integration/
.github/workflows/checks.yaml  Containerized CI gate
Dockerfile               Runtime and test image targets
compose.yaml             Local sandbox orchestration
openapi.yaml             Application contract, starting in Phase 2
Makefile                 Canonical developer interface
```

The filenames describe responsibilities, not mandatory abstractions. A module
should remain a small group of related functions and should not imitate classes
or dependency injection containers.

## Development sandbox

The multi-stage Dockerfile has two roles built from the same pinned Debian
base. The `runtime` target contains only the application and runtime tools. The
`test` target adds Make, ShellCheck, shfmt, and the test sources. Both execute as
an unprivileged user.

Compose is the local orchestration layer. The server uses a read-only root
filesystem, a temporary `/tmp`, `no-new-privileges`, and a healthcheck against
`GET /health`. The test service applies the same restrictions and runs the
canonical `make check` target with real `socat` and `curl` processes.

`make container-check` builds and runs the test target, then starts and
health-checks the runtime target. GitHub Actions invokes only this Make target,
so local container verification and CI do not maintain separate command lists.
These images are an educational and verification sandbox, not a production
deployment definition or a published artifact.

## Runtime boundaries

### CLI

`bin/bash-http` is the public entry point. It parses commands and options,
checks only the dependencies needed by the selected command, and delegates to
library functions. It must not parse HTTP or contain endpoint behavior.

The current CLI exposes:

```text
bash-http serve OPENAPI_FILE [--host HOST] [--port PORT]
bash-http routes OPENAPI_FILE
bash-http validate OPENAPI_FILE
bash-http help
```

This is an intentional pre-1.0 CLI change rather than compatibility code for a
temporary interface.

### Dependency checks

Dependency checks are command-specific:

- `serve` requires Bash, `socat`, and Mike Farah `yq` v4.
- `routes` and `validate` require Mike Farah `yq` v4 but not `socat`.
- JSON request normalization requires `jq` only when a JSON body is received.
- Integration tests require `curl` and `socat`.
- `make lint` requires `shellcheck`.
- `make format` requires `shfmt`.

The health endpoint does not depend on `jq`. OpenAPI commands and server
startup require `yq`; a missing body parser produces an actionable error only
when that representation is received.

### Transport adapter

The transport adapter starts `socat`, binds to `127.0.0.1` by default, and
delegates each connection to a private CLI operation. The host and port are
configurable. The adapter is responsible for process startup, signal handling,
and forwarding connection streams, but it does not understand HTTP.

All paths and arguments passed to `socat` must be constructed from trusted
configuration and quoted safely. Request data must never become part of the
`EXEC` command.

The initial process model is intentionally simple:

- one listener;
- one child process per connection;
- one request per child;
- one response per child;
- connection close after the response.

This model is easy to inspect but is not efficient and offers no production
concurrency controls.

### Connection orchestration

The connection entry point coordinates the request lifecycle:

1. Initialize request, parameter, body, and response state.
2. Parse stdin and capture the declared body bytes.
3. Resolve the request to an operation and path parameters.
4. Build query and header maps and normalize the request body.
5. Invoke the selected handler when appropriate.
6. Build exactly one response.
7. Write the response to stdout.
8. Clean up temporary resources and exit.

It may select a central error response after another component reports an
error, but it must not duplicate parser, router, or response formatting logic.

### Request parser

The parser turns the connection input into request state or a typed failure. It
owns request-line and header syntax but does not decide whether a route exists.

The initial state is expected to use explicitly named Bash variables and
associative arrays, for example:

```text
REQUEST_METHOD
REQUEST_TARGET
REQUEST_PATH
REQUEST_QUERY_STRING
REQUEST_HTTP_VERSION
REQUEST_HEADERS[name]
REQUEST_CONTENT_LENGTH
```

Only the parser populates raw HTTP request state. `params.sh` derives separate
`REQUEST_PATH_PARAMS`, `REQUEST_QUERY_PARAMS`, and `REQUEST_HEADER_PARAMS` maps
after routing. Handlers use those maps rather than router-owned state.

Bash state should remain in the current process when practical. Pipelines and
subshells must not be used where losing array or variable mutations would alter
the request lifecycle.

### Router

The router receives route definitions discovered from OpenAPI and
returns one of these outcomes:

- matching operation and extracted path parameters;
- known path with unsupported method;
- unknown path;
- invalid route definition detected during startup.

Static route segments take precedence over parameterized segments. Routing is
independent of handler loading.

### OpenAPI adapter

`openapi.sh` uses Mike Farah `yq` v4 to read the supported
OpenAPI 3.0 subset. It converts document data into a small internal route
representation. No other module should contain `yq` queries.

The adapter validates required structural rules before serving traffic. It
must distinguish an invalid document from a valid document that uses an
unsupported feature.

### Handlers

A handler is a Bash function contained in a script. Its function and file are
resolved from a validated lowercase snake-case OpenAPI `operationId`. For
example, `get_book` maps to `handlers/get_book.sh` and `handle_get_book`.
Handler scripts are
sourced from a trusted project directory; client input never selects an
arbitrary filesystem path.

Handlers consume request context and use response helpers. They must not:

- read directly from the connection;
- write response bytes directly to stdout;
- parse OpenAPI;
- perform route matching;
- calculate HTTP framing headers.

The initial health handler returns a stable JSON body without requiring `jq`:

```json
{"status":"ok"}
```

### Response builder

The response builder is the sole owner of response serialization. It receives
status, headers, and body state and emits:

```text
status line + headers + empty line + body
```

It guarantees `Content-Length`, `Content-Type`, and `Connection: close` in
Phase 1. Content length is the byte length under a byte-oriented locale, not a
character count. Error helpers select response data but still delegate final
serialization to this module.

Later content negotiation belongs in this boundary so handlers can continue to
return a transport-neutral structured representation.

### Validation and middleware

These boundaries are planned, not designed in detail yet:

- Validation receives parsed values and the supported OpenAPI constraints. It
  returns validated values or structured errors before handler execution.
- Middleware is a synchronous, ordered pipeline selected by the OpenAPI
  `x-middlewares` extension. It runs before the handler and may contribute to
  response state, but it will not imitate asynchronous callback semantics.

Their detailed interfaces will be decided when their phases begin.

## Error propagation

Bash exit status is used deliberately, not as an implicit exception system.
Functions that can fail should return a documented status and place expected
result data in clearly owned variables. Expected client errors must not depend
on `set -e` terminating the process.

Strict mode may be enabled at executable boundaries where its behavior is
understood. Libraries must still quote expansions, check commands explicitly,
and handle pipelines and conditionals correctly. `set -euo pipefail` is not a
substitute for error design.

The connection orchestrator is responsible for converting known failures to
one central HTTP response. An unexpected internal failure should produce a
minimal `500` response if no response has started, and always produce a
diagnostic on stderr.

## Temporary data

Request bodies use per-connection temporary files because shell variables
cannot preserve arbitrary bytes safely. `body.sh` creates a mode-700 directory
with `mktemp -d`, stores raw and normalized representations separately, and
removes the directory on normal completion, handled failures, and process exit
through the connection trap.

## Security and operational posture

This project is not a secure or production-ready HTTP server. Nevertheless,
the implementation should avoid teaching unnecessarily dangerous patterns:

- default to loopback instead of all network interfaces;
- never use `eval` for request or OpenAPI data;
- never source a client-controlled path;
- validate numeric options such as ports and content lengths;
- apply documented parsing limits and an inactivity timeout;
- keep stdout free of diagnostics;
- clean up child processes and temporary files;
- report unsupported framing instead of guessing.

The line and header limits described in [HTTP subset](http-subset.md) are
behavioral checks, not complete denial-of-service protection. Bash may allocate
a line before its length can be rejected, and `socat,fork` has no global child
limit in this design.

## Deferred architecture

The following mechanisms must not be introduced before a concrete phase needs
them:

- dependency injection containers or object systems;
- plugin or hook frameworks;
- asynchronous middleware semantics;
- generic transport abstractions beyond keeping `socat` isolated;
- worker pools or prefork supervisors;
- persistence repositories for the example JSON file;
- schema compilers or generated Bash routing code;
- backward-compatibility layers for pre-1.0 internal interfaces.
