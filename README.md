# bash-http-lab

Experimental HTTP server built with Bash and Unix tools to expose the work that
web frameworks normally hide. The current runtime implements one HTTP/1.1
request per connection, discovers routes from OpenAPI 3.0, builds a bounded
request context, and validates a small OpenAPI request-schema subset before
handlers run. Operations can also declare ordered request ID and structured
logging middleware. Handlers return one structured JSON value that the response
builder can serialize as JSON or YAML through `Accept` negotiation. Developer
commands can generate missing handlers or serve documented OpenAPI examples,
and the included users API persists its demonstration data in a JSON file.

This is an educational project. It is not production-ready and should not be
exposed to untrusted networks.

## Requirements

The supported environments are Linux and WSL. Runtime requirements are:

- Bash 5.2 or newer;
- `socat`;
- `jq` for structured responses and JSON request bodies;
- Mike Farah `yq` version 4.

Development and tests additionally use `curl`, GNU Make, `shellcheck`, and
`shfmt`. On Ubuntu 24.04 these tools can be installed with:

```bash
sudo apt-get update
sudo apt-get install bash curl jq make shellcheck shfmt socat
```

Install `yq` from the official
[Mike Farah releases](https://github.com/mikefarah/yq/releases) and verify that
`yq --version` identifies major version 4. Other programs named `yq` are not
compatible.

Docker Engine with the Compose plugin is an alternative development sandbox.
It supplies the supported Linux runtime and every project tool, including
`socat` and the pinned Mike Farah `yq` binary. The container image is for local
development and CI verification only; it is not a production deployment
artifact.

## Usage

Start the server on the default loopback address and port:

```bash
./bin/bash-http serve openapi.yaml
```

Select another host or port when needed:

```bash
./bin/bash-http serve openapi.yaml --host 127.0.0.1 --port 9090
```

Hosts must be IPv4 addresses or DNS hostnames. Ports must be integers from 1 to
65535. The server binds to `127.0.0.1:8080` by default.

With the server running:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/users
curl --request POST --header 'Content-Type: application/json' \
  --data '{"name":"Katherine Johnson"}' http://127.0.0.1:8080/users
curl --header 'Accept: application/yaml' http://127.0.0.1:8080/users/1
```

The response body is exactly:

```json
{"status":"ok"}
```

Inspect or validate the contract without starting the listener:

```bash
./bin/bash-http routes openapi.yaml
./bin/bash-http validate openapi.yaml
```

Generate only handlers that do not already exist, or run the same request
pipeline using documented OpenAPI response examples instead of handlers:

```bash
./bin/bash-http generate openapi.yaml
./bin/bash-http mock openapi.yaml
```

`generate` never overwrites an existing handler. Mock mode chooses the lowest
documented `2xx` status with an example, falling back to the lowest documented
status with an example. A direct `example` wins over named `examples`; named
examples are considered in lexical order. External examples are unsupported.

The example contract exposes health plus list, read, create, and delete user
operations. User data is stored directly in `data/users.json`. Each update is
written to a temporary file and renamed into place, so readers do not observe a
partially written file. There is no locking or conflict detection: concurrent
writes can allocate the same ID or overwrite one another. This intentionally
primitive persistence is only suitable for the educational example.

## Development

GNU Make is the canonical developer interface:

```bash
make                    # list public targets
make test-unit          # run tests without network infrastructure
make test-integration   # start the real socat listener and call it with curl
make test               # run all tests
make lint               # run shellcheck
make format             # format scripts with shfmt
make format-check       # verify formatting
make check              # run every required check
make run                # run the server in the foreground
make container-build    # build the runtime and test images
make container-check    # run every check and smoke-test the runtime image
make container-up       # start the sandbox server on PORT (default 8080)
make container-down     # stop and remove sandbox containers
```

With Docker, `make container-check` is the reproducible verification path used
by CI. It runs lint, formatting checks, unit tests, and the real `socat` network
integration test inside the test image before health-checking the minimal
runtime image. After `make container-up`, the example API is available at
`http://127.0.0.1:8080`; use `PORT=9090 make container-up` to change the host
port.

Integration tests use `TEST_HOST` and `TEST_PORT` when those environment
variables are set. Startup uses bounded readiness probes, and all listener
processes and temporary files are cleaned up when the test exits.

## Current HTTP subset

- one HTTP/1.1 request and response per connection;
- strict CRLF request lines and headers;
- request bodies up to 1 MiB using `Content-Length`;
- JSON validation, YAML-to-JSON normalization, and byte-preserving plain text;
- separate path, decoded query, and normalized header parameter maps;
- required OpenAPI parameters and bodies with scalar constraints and top-level
  body type validation;
- OpenAPI-discovered routes with literal and whole-segment parameter matching;
- static-segment precedence and captured path parameters;
- health plus list, read, create, and delete users from the example contract;
- JSON and YAML response serialization with basic quality and wildcard
  negotiation;
- central `400`, `404`, `405`, `406`, `413`, `415`, `500`, and `501` responses;
- operation-level `x-middlewares` with `requestId` and `logging`;
- stable `X-Request-Id` correlation and one JSON request log on stderr;
- `Connection: close` on every response.

See [`docs/`](docs/README.md) for architecture, exact protocol behavior,
technical decisions, and the phased roadmap.
