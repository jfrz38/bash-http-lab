# Technical decisions

This is a lightweight decision log. It records choices that constrain multiple
modules or phases. Local implementation details should remain near the code and
should not be added here unless they affect a project-wide guarantee.

## D001: Bash is the application runtime

**Status:** Accepted

The server, routing, validation, middleware, handlers, and response generation
will be implemented in Bash. External Unix tools may provide focused parsing,
transport, or formatting capabilities, but another general-purpose language
must not host part of the application runtime.

**Rationale:** The purpose of the project is to expose framework mechanics
rather than produce the easiest or most robust HTTP implementation.

**Consequences:** Quoting, process boundaries, subshell behavior, byte handling,
and exit statuses must be designed explicitly. Readability is preferred over
shell tricks.

## D002: Support Linux and WSL

**Status:** Accepted

Linux and WSL are supported. Native Windows shells, MSYS2, BusyBox-only
environments, and macOS are not compatibility targets for the first versions.

The baseline runtime is Bash 5.2 or newer. This allows associative arrays and a
consistent modern Bash environment without maintaining fallbacks for old
versions.

**Rationale:** `socat`, process signaling, filesystem semantics, and standard
Unix tools behave consistently enough across Linux and WSL for the experiment.

**Consequences:** Development from Windows may run the project inside WSL or
the documented Docker sandbox. Native Windows shells remain unsupported.
Portable POSIX `sh` is not a goal.

## D003: Delegate TCP to socat

**Status:** Accepted

`socat` owns the TCP listener and starts a Bash connection process for each
accepted connection.

**Rationale:** Implementing sockets in Bash would distract from HTTP and
framework responsibilities and would require non-portable mechanisms.

**Consequences:** The transport remains isolated, but the first implementation
inherits `socat`'s process-per-connection model and operational limitations.
Replacing it later is possible but is not itself a project goal.

## D004: Handle one request per connection

**Status:** Accepted

The initial runtime reads one HTTP/1.1 request, writes one response with
`Connection: close`, and exits.

**Rationale:** Keep-alive requires a connection loop, response framing reuse,
timeout policy, and additional failure recovery that do not help demonstrate
the initial request lifecycle.

**Consequences:** Persistent connections and pipelining are unsupported. This
is intentionally inefficient.

## D005: Reserve stdout for HTTP

**Status:** Accepted

While handling a connection, stdout contains only the HTTP response. Logs,
warnings, tracing, and diagnostics go to stderr.

**Rationale:** `socat` forwards stdout to the client, so any diagnostic output
would corrupt the protocol response.

**Consequences:** Helper functions and external tools must redirect or capture
their incidental output deliberately.

## D006: Use command-specific dependency checks

**Status:** Accepted

Each CLI command checks only the tools it needs. Phase 1 serving requires
`socat`, but it does not require `jq` or `yq`. Development targets check their
own tools.

**Rationale:** An unused future dependency should not prevent a working health
server or an unrelated test from running.

**Consequences:** Dependency declarations remain centralized, while command
requirements are explicit.

## D007: Use OpenAPI 3.0 as the route source of truth

**Status:** Accepted for Phase 2

Starting in Phase 2, an OpenAPI 3.0.x document supplies application paths,
methods, and `operationId` values. Routes are not duplicated in Bash.

OpenAPI 3.1, remote references, callbacks, webhooks, and the full Schema Object
are unsupported until explicitly added.

**Rationale:** OpenAPI 3.0 provides the concepts needed by the experiment while
avoiding the broader JSON Schema semantics adopted by OpenAPI 3.1.

**Consequences:** Phase 1's hard-coded health route is temporary and must be
removed when OpenAPI routing is introduced.

## D008: Standardize on Mike Farah yq v4

**Status:** Accepted for Phase 2

All documented `yq` expressions target Mike Farah `yq` major version 4. Other
tools named `yq`, including Python wrappers around `jq`, are incompatible and
are not supported.

**Rationale:** The name `yq` describes multiple incompatible programs. Choosing
one implementation avoids ambiguous installation and query instructions.

**Consequences:** Dependency checks must verify the implementation and major
version, not merely the presence of a `yq` executable.

## D009: Keep OpenAPI queries in one adapter

**Status:** Accepted for Phase 2

Only the OpenAPI adapter invokes `yq`. It converts the supported document subset
to a small internal representation consumed by routing and validation.

**Rationale:** Spreading YAML queries through the runtime would couple routing,
handlers, and validation to document traversal details.

**Consequences:** The adapter is a boundary, not a generic repository or object
mapping layer.

## D010: Resolve handlers from validated operationId values

**Status:** Accepted for Phase 2

An `operationId` identifies a handler function and its script in the trusted
handlers directory. The identifier must be validated before constructing a
name or path. Missing handlers return `501 Not Implemented` in development.

**Rationale:** The mapping is easy to understand and demonstrates how a
framework connects declarative routes to application code.

**Consequences:** The runtime must never use `eval`, source an arbitrary path,
or permit path traversal through an `operationId`.

## D011: Use explicit Bash error handling

**Status:** Accepted

Executable boundaries may use `set -euo pipefail` where its effects are tested,
but expected request failures use explicit statuses and owned result state.

**Rationale:** `set -e` changes behavior in functions, conditionals, pipelines,
command substitutions, and subshells. Treating it as an exception mechanism
would make request handling difficult to reason about.

**Consequences:** Functions that can fail need documented return behavior, and
tests must exercise failure paths.

## D012: Use a small Bash test harness first

**Status:** Accepted for Phase 1

Tests use Bash scripts, shared assertion helpers, and process cleanup utilities.
No dedicated test framework is added initially.

**Rationale:** The first suite is small, and avoiding another dependency keeps
the mechanics visible. A framework may be considered if the harness starts
accumulating runner behavior unrelated to the tests.

**Consequences:** The harness must provide deterministic failure output and
must not grow into a custom general-purpose testing framework.

## D013: Use Make as the developer interface

**Status:** Accepted for Phase 1

The Makefile is the canonical entry point for help, tests, linting, formatting,
and local execution. Its default target is dynamic help.

**Rationale:** Contributors need one discoverable interface without copying
long commands between documentation and automation.

**Consequences:** README instructions and future CI should call public Make
targets instead of duplicating their implementation.

## D014: Delay compatibility code before 1.0

**Status:** Accepted

Temporary Phase 1 interfaces may change when Phase 2 introduces the actual
OpenAPI contract. The project will not maintain aliases or ignored arguments
unless a real external consumer needs them.

**Rationale:** Preserving experimental interfaces would obscure the runtime and
add code unrelated to its educational purpose.

**Consequences:** Intentional CLI changes must be documented in the roadmap and
release notes once releases exist.

## D015: Match Phase 2 paths without normalization

**Status:** Accepted for Phase 2

Routing compares the parsed request path to OpenAPI templates without percent
decoding or normalization. Trailing slashes, repeated slashes, dot segments,
and encoded characters remain distinct input.

**Rationale:** Normalization changes routing and security behavior. Deferring it
is safer than silently choosing incomplete URL semantics during the routing
phase.

**Consequences:** `/books` and `/books/` are different paths. Templates support
only literal segments and parameters that occupy a complete segment.

## D016: Use a direct Bash route representation

**Status:** Accepted for Phase 2

The OpenAPI adapter loads methods, path templates, and operation IDs into
parallel Bash arrays. The router splits paths into segments when matching and
stores captured values in an associative array.

**Rationale:** The route set is deliberately small, and a direct representation
keeps the routing mechanics visible without generated code or an object model.

**Consequences:** Each connection process reloads the trusted OpenAPI document.
The `serve` command still validates it before starting the listener so invalid
configuration cannot begin accepting traffic.

## D017: Keep Phase 2 handler resolution conventional

**Status:** Accepted for Phase 2

Phase 2 accepts lowercase snake-case `operationId` values. An operation named
`get_book` resolves to `handlers/get_book.sh` and the function
`handle_get_book`. The handler directory is fixed relative to the runtime and
is not configurable through request data or OpenAPI.

**Rationale:** A strict convention demonstrates declarative handler resolution
while making traversal and shell evaluation unnecessary.

**Consequences:** Missing scripts or functions produce `501 Not Implemented`.
Applications needing configurable handler roots or broader identifier syntax
must introduce that behavior explicitly in a later phase.

## D018: Use one containerized verification sandbox

**Status:** Accepted for Phase 2

A multi-stage Dockerfile builds a minimal runtime image and a test image with
the complete development toolchain. Compose defines their local execution, and
`make container-check` is the only containerized verification entry point used
by GitHub Actions.

The Debian base is pinned by digest. The Mike Farah `yq` version and supported
architecture checksums are fixed in the Dockerfile. Both services run as a
non-root user with a read-only root filesystem, a temporary `/tmp`, and
`no-new-privileges`.

**Rationale:** The supported tools were split between native Git Bash and WSL,
which prevented the real network integration test from running in one local
environment. A shared Linux sandbox makes local and CI results reproducible
without replacing the native Make workflow.

**Consequences:** Docker and the Compose plugin are required only for
containerized verification. The image is not published or presented as a
production deployment artifact. Native `make check` remains supported when the
host provides all required tools.

## D019: Reject repeated query values in the initial context

**Status:** Accepted for Phase 3

Query names and values use form-style `+` and `%HH` decoding, but repeated
decoded names are rejected with `400 Bad Request`. Header names remain unique
under the existing duplicate-header rule, and path parameter names are unique
within a route template.

**Rationale:** Bash associative arrays cannot preserve repeated values without
another representation. Rejecting them avoids silently choosing first-wins or
last-wins semantics before the project has a concrete list-valued use case.

**Consequences:** Clients must send at most one value for each query name. A
future phase may introduce ordered multi-value storage as an explicit contract
change.

## D020: Store request bodies in private temporary files

**Status:** Accepted for Phase 3

Each connection stores raw and normalized body data in a private temporary
directory. Structured JSON and YAML bodies are exposed to handlers as a
normalized JSON file; plain text is copied without command substitution.

**Rationale:** Bash variables cannot represent NUL bytes and command
substitution removes trailing newlines. Files preserve the declared byte stream
and let external parsers operate without loading the complete body into shell
state.

**Consequences:** Every parsed connection creates short-lived filesystem state
that must be cleaned on every exit path. Binary media types remain unsupported.

## D021: Keep the Phase 4 schema subset flat and explicit

**Status:** Accepted for Phase 4

Parameters support one scalar value with an inline schema. Top-level request
bodies additionally support object and array types, but nested properties,
array items, references, composition, and other undeclared schema keywords are
rejected during OpenAPI validation.

**Rationale:** The existing Bash request context intentionally stores one value
per parameter name. A flat subset demonstrates contract-driven validation
without silently approximating collection serialization or implementing a
general JSON Schema engine.

**Consequences:** Path-item parameters are inherited and operation parameters
override them by location and name. Extra query and header values are allowed.
Applications requiring nested validation must wait for an explicit expansion
of the supported subset.

## D022: Use jq only on validated operations

**Status:** Accepted for Phase 4

The OpenAPI adapter stores compact inline schemas in direct Bash arrays keyed
by operation ID. After request normalization, `validation.sh` invokes `jq` only
when the selected operation declares parameter or body validation metadata.

**Rationale:** `jq` provides reliable JSON types, Unicode string lengths, enum
comparison, and numeric bounds without turning Bash into a schema evaluator.
Keeping schema discovery in `openapi.sh` preserves the OpenAPI adapter boundary.

**Consequences:** Operations without request schemas, including `/health`, do
not gain a runtime `jq` dependency. Validation failures use generic central
`400` or `415` responses and never expose schema internals to clients.

## D023: Keep middleware synchronous and operation-scoped

**Status:** Accepted for Phase 5

OpenAPI operations select ordered middleware through `x-middlewares`. The
runtime executes explicit before and after hooks in declaration order only
after request validation succeeds. Phase 5 middleware cannot intentionally
short-circuit into an application response; hook failure is an internal error.

**Rationale:** Two direct loops expose ordering and lifecycle mechanics without
callback chains, continuations, or a generic plugin framework. Applying the
pipeline only to validated operations gives middleware and handlers the same
normalized request assumptions.

**Consequences:** `requestId` and `logging` are the only accepted names.
Middleware failures select `500`; before failures skip the handler. Request
logs cover middleware and handler execution but not parsing, validation, or
socket write time.

## Deferred decisions

The following decisions should be made when their implementation phase begins:

- content negotiation precedence and fallback behavior;
- persistence concurrency for the example users file;
- generated handler formatting and overwrite policy flags;
- mock response selection when multiple examples or status codes exist.
