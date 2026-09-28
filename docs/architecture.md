# Architecture

## Purpose

`bash-http-lab` makes the responsibilities normally hidden by HTTP frameworks
visible and understandable. It favors explicit data flow, small Bash modules,
and narrow protocol support over completeness or performance.

The runtime implements this lifecycle:

```text
TCP connection
    -> HTTP request parsing
    -> route matching
    -> request context creation
    -> OpenAPI validation
    -> middleware
    -> handler execution
    -> representation negotiation
    -> HTTP response construction
```

Unsupported behavior fails explicitly when silently accepting it could produce
an incorrect result.

## System context

```text
HTTP client
    |
    v
socat TCP listener
    |
    | stdin/stdout for one connection
    v
Bash connection process
    |
    +-> request parser
    +-> OpenAPI adapter and router
    +-> validation
    +-> middleware
    +-> handler
    +-> response builder
```

`socat` owns TCP concerns and starts one Bash process for each accepted
connection. That process reads one request, writes one response, and exits.
Every response includes `Connection: close`; persistent connections and
pipelining are unsupported.

This process model is intentionally easy to inspect. It is inefficient and has
no production concurrency controls.

## Invariants

1. Bash is the application runtime.
2. HTTP response bytes are the only data written to stdout while handling a
   connection.
3. Logs, warnings, and diagnostics are written to stderr.
4. Client-controlled data is never evaluated as shell code or interpolated
   into a command string.
5. Transport code does not contain routing, handler, or OpenAPI rules.
6. Parsing code does not emit HTTP responses directly.
7. Handlers do not construct raw status lines or framing headers.
8. Application routes are discovered from OpenAPI and are not registered a
   second time in Bash.
9. Unsupported protocol or OpenAPI features fail explicitly when ignoring them
   could change behavior.

## Repository structure

```text
bin/bash-http             Public CLI entry point
lib/dependencies.sh       Command-specific dependency checks
lib/server.sh             Listener and connection orchestration
lib/request.sh            HTTP request parsing
lib/response.sh           Response construction and negotiation
lib/errors.sh             Central HTTP error responses
lib/openapi.sh            OpenAPI loading and route discovery
lib/router.sh             Route matching and handler resolution
lib/params.sh             Path, query, and header parameter context
lib/body.sh               Request body storage and normalization
lib/validation.sh         Supported schema validation
lib/middleware.sh         Synchronous middleware pipeline
lib/generator.sh          Non-destructive handler generation
handlers/                 Example API handlers and JSON data access
middleware/               Request ID and logging middleware
data/users.json           Example API data
tests/unit/               Module-level behavior tests
tests/integration/        Real listener and client tests
openapi.yaml              Bundled application contract
Dockerfile                Runtime and test image targets
compose.yaml              Local sandbox orchestration
Makefile                  Developer interface
```

The filenames describe responsibilities, not object-oriented abstractions.
State remains in explicitly named Bash variables and associative arrays when
practical.

## Request lifecycle

The private connection entry point coordinates one request:

1. Initialize request, parameter, body, middleware, and response state.
2. Parse stdin and capture the declared body bytes.
3. Resolve the request to an OpenAPI operation and capture path parameters.
4. Build query and header maps and normalize the request body.
5. Validate declared parameters and request bodies.
6. Run selected middleware before hooks in declaration order.
7. Invoke the selected handler, or select a documented example in mock mode.
8. Negotiate the output representation and run applicable after hooks.
9. Finalize and write exactly one response to stdout.
10. Clean temporary resources and exit.

The orchestrator may select a central error response after another component
reports an error, but it does not duplicate parser, router, validation, or
serialization logic.

## Runtime boundaries

### CLI and dependencies

`bin/bash-http` parses commands and trusted options, checks only the
dependencies required by the selected command, and delegates to library
functions. It contains no endpoint behavior or HTTP parsing.

Serving and mocking require Bash, `socat`, `jq`, and Mike Farah `yq` v4.
OpenAPI inspection and handler generation require `yq` but not the listener.
Development checks additionally use `curl`, GNU Make, ShellCheck, and shfmt.

### Transport

The transport starts `socat`, binds to `127.0.0.1` by default, and delegates
each connection to a private CLI operation. It owns process startup, signal
handling, and stream forwarding, but does not understand HTTP.

All values passed to `socat` come from validated, trusted configuration.
Request data never becomes part of its `EXEC` command.

### Request parser and context

The parser owns request-line and header syntax and reports typed failures. It
populates raw request state but does not decide whether a route exists. After
routing, the parameter and body modules derive separate path, query, header,
and normalized body representations for validation and handlers.

Request bodies use private per-connection temporary files. Shell variables
cannot preserve arbitrary byte sequences, and command substitution removes
trailing newlines. Raw and normalized representations remain separate and are
removed on normal completion, handled failures, and process exit.

Bash state remains in the current process where mutation matters. Pipelines and
subshells are avoided when losing array or variable updates would change the
request lifecycle.

### OpenAPI adapter and router

`lib/openapi.sh` is the only module that traverses the OpenAPI document. It uses
Mike Farah `yq` v4 and converts the supported OpenAPI 3.0 subset into direct
Bash arrays consumed by routing and validation.

The adapter validates structural requirements before the listener starts and
distinguishes invalid documents from valid documents containing unsupported
features.

The router matches literal and whole-segment parameter paths. Static segments
take precedence over parameters, and ambiguous templates are rejected during
document validation. A result identifies a matching operation, a known path
with an unsupported method, or an unknown path. Routing is independent of
handler loading.

### Validation and middleware

Validation receives normalized request state and the flat metadata produced by
the OpenAPI adapter. It performs supported type, enum, and bound checks before
application code runs. It neither formats responses nor invokes handlers.

Operations select ordered middleware through `x-middlewares`. Before hooks run
after validation and before the handler. After hooks run after the final status
and representation have been selected but before the response is written.

The request ID middleware preserves a valid client value or generates a Linux
UUID. Logging emits one compact JSON object to stderr containing the request
ID, method, path, status, and duration. It does not record query values,
headers, or request bodies.

### Handlers

Each handler is a Bash function in a script resolved from a validated lowercase
snake-case OpenAPI `operationId`. For example, `get_user` maps to
`handlers/get_user.sh` and `handle_get_user`.

Scripts are loaded only from the trusted handlers directory. Handlers consume
normalized request context and select structured response data. They do not:

- read directly from the connection;
- write response bytes to stdout;
- parse OpenAPI;
- perform route matching;
- calculate framing headers.

The generator uses the same validated operation identifiers and creates only
missing handler scripts. It has no overwrite mode.

### Response builder

The response builder owns representation selection, serialization, framing
headers, and the final write to stdout. Application handlers provide a status
and one JSON structured value. The builder validates and compacts that value,
then negotiates JSON or YAML from the request's `Accept` header.

Central error helpers select response state but still delegate final
serialization to the response builder. Content length is calculated in bytes
under a byte-oriented locale.

## Error propagation

Bash exit statuses are used deliberately rather than as an exception system.
Functions that can fail return documented statuses and place expected results
in clearly owned variables. Known request failures do not depend on `set -e`
terminating the process.

Executable boundaries may enable strict shell options where their effects are
understood. Libraries still quote expansions and handle commands, conditions,
pipelines, and cleanup explicitly.

The connection orchestrator converts known failures into central responses. An
unexpected failure produces a minimal `500` when no response has started and a
diagnostic on stderr.

## Example persistence

The users example reads and writes `data/users.json`. Updates are rendered to a
temporary file in the same directory and renamed over the data file, preventing
readers from observing a partially written document.

There is no locking, versioning, or transaction support. Concurrent creates or
deletes can read the same prior state, allocate the same ID, or overwrite an
update. Compose mounts `/workspace/data` as a writable named volume while
keeping the rest of the runtime filesystem read-only.

## Development sandbox

The multi-stage Dockerfile builds a runtime image and a test image from the
same pinned Debian base. The runtime image contains the application and runtime
tools. The test image adds Make, ShellCheck, shfmt, and the test suite. Both run
as an unprivileged user.

Compose applies a read-only root filesystem, a temporary `/tmp`,
`no-new-privileges`, and a healthcheck against `GET /health`.
`make container-check` runs the same containerized verification used by GitHub
Actions, including the real `socat` and `curl` integration test.

These images are development and verification sandboxes, not production
deployment artifacts.

## Security posture

This project is neither a secure nor a production-ready HTTP server. It still
avoids teaching unnecessarily dangerous patterns:

- bind to loopback by default;
- never evaluate request or OpenAPI data;
- never load a client-controlled path;
- validate host, port, content length, and generated identifiers;
- apply bounded request sizes and an inactivity timeout;
- reserve stdout for protocol output;
- clean temporary files and child processes;
- reject unsupported framing instead of guessing.

The documented limits are behavioral checks, not complete denial-of-service
protection. Bash may allocate a line before its length can be rejected, and the
`socat,fork` listener has no global child-process limit.

See [Supported HTTP subset](http-subset.md) for the exact protocol behavior and
limits.
