# bash-http-lab

`bash-http-lab` started as a small experiment: I wanted to see what it would
look like to build, in plain Bash, the pieces that a web framework normally
provides.

The result is a deliberately small HTTP/1.1 server that parses requests, matches
OpenAPI operations, validates input, runs middleware, invokes handlers, and
builds responses. It is meant for learning and exploration rather than as a
replacement for a real web framework.

It is not production-ready and must not be exposed to untrusted networks.

```text
client
  -> socat listener
  -> request parser
  -> OpenAPI router
  -> request validation
  -> middleware
  -> Bash handler
  -> content negotiation and response serialization
```

## Quick start

Docker Engine with the Compose plugin provides the shortest path to a supported
Linux runtime with all dependencies installed:

```bash
docker compose up --build --wait server
curl http://127.0.0.1:8080/health
```

The response body is:

```json
{"status":"ok"}
```

The bundled OpenAPI document also exposes a small users API:

```bash
curl http://127.0.0.1:8080/users
curl --request POST --header 'Content-Type: application/json' \
  --data '{"name":"Katherine Johnson"}' http://127.0.0.1:8080/users
curl --header 'Accept: application/yaml' http://127.0.0.1:8080/users/1
curl --request DELETE http://127.0.0.1:8080/users/2
```

Stop the sandbox with:

```bash
docker compose down
```

Set `PORT` to publish the server on a different host port:

```bash
PORT=9090 docker compose up --build --wait server
```

## What it demonstrates

- one HTTP/1.1 request per connection using a `socat` process;
- strict request-line, header, and body framing checks;
- routes and handler names discovered from OpenAPI 3.0;
- path, query, header, and body request context;
- a deliberately small OpenAPI request-validation subset;
- ordered request ID and structured logging middleware;
- JSON and YAML response negotiation;
- non-destructive handler generation and OpenAPI example mocking;
- explicit error propagation and response construction in Bash.

The example users API stores data in `data/users.json`. File replacement is
atomic, but concurrent updates are not coordinated and can be lost. This
persistence is intentionally simple and exists only to exercise the complete
request pipeline.

## Native usage

Linux and WSL are supported. The runtime requires:

- Bash 5.2 or newer;
- `socat`;
- `jq`;
- [Mike Farah `yq`](https://github.com/mikefarah/yq/releases) version 4.

On Ubuntu 24.04, install the packaged dependencies with:

```bash
sudo apt-get update
sudo apt-get install bash curl jq make shellcheck shfmt socat
```

Install `yq` from its official releases and verify that `yq --version` reports
major version 4. Other programs named `yq` are not compatible.

Start the server on its default `127.0.0.1:8080` address:

```bash
./bin/bash-http serve openapi.yaml
```

Select another address when needed:

```bash
./bin/bash-http serve openapi.yaml --host 127.0.0.1 --port 9090
```

Hosts must be IPv4 addresses or DNS hostnames. Ports must be integers from 1 to
65535.

## CLI

```text
bash-http serve OPENAPI_FILE [--host HOST] [--port PORT]
bash-http mock OPENAPI_FILE [--host HOST] [--port PORT]
bash-http routes OPENAPI_FILE
bash-http validate OPENAPI_FILE
bash-http generate OPENAPI_FILE
bash-http help
```

- `serve` runs operations through their Bash handlers.
- `mock` runs the same request pipeline but returns documented OpenAPI response
  examples instead of invoking handlers.
- `routes` lists operations discovered from the document.
- `validate` checks the supported OpenAPI subset without starting a listener.
- `generate` creates missing handler files and never overwrites existing files.

Mock mode chooses the lowest documented `2xx` status containing an example. If
none exists, it chooses the lowest documented status containing an example. A
direct `example` takes precedence over lexically ordered named `examples`.
External examples are unsupported.

## Development

GNU Make is the developer interface:

```bash
make                    # list public targets
make test-unit          # run tests without network infrastructure
make test-integration   # exercise the real socat listener with curl
make test               # run all tests
make lint               # run ShellCheck
make format             # format scripts with shfmt
make format-check       # verify formatting
make check              # run all native checks
make run                # run the server in the foreground
make container-check    # run the reproducible CI verification path
make container-up       # start the sandbox server
make container-down     # stop and remove sandbox containers
```

Integration tests accept `TEST_HOST` and `TEST_PORT`. `HOST`, `PORT`, and
`OPENAPI_FILE` configure `make run`.

## Limits

The server intentionally supports a narrow subset of HTTP and OpenAPI. Notable
non-goals include TLS, persistent connections, chunked bodies, HTTP/2 and
HTTP/3, WebSockets, arbitrary binary streaming, high concurrency, complete
OpenAPI or JSON Schema support, and production hardening.

See [Architecture](docs/architecture.md) for the runtime boundaries and
[Supported HTTP subset](docs/http-subset.md) for the exact protocol contract.

## License

This project is available under the [MIT License](LICENSE).
