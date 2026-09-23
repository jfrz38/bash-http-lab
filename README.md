# bash-http-lab

Experimental HTTP server built with Bash and Unix tools to expose the work that
web frameworks normally hide. The current runtime implements one HTTP/1.1
request per connection and a temporary `GET /health` endpoint. OpenAPI-driven
routing begins in Phase 2.

This is an educational project. It is not production-ready and should not be
exposed to untrusted networks.

## Requirements

The supported environments are Linux and WSL. Runtime requirements are:

- Bash 5.2 or newer;
- `socat`.

Development and tests additionally use `curl`, GNU Make, `shellcheck`, and
`shfmt`. On Ubuntu 24.04 these tools can be installed with:

```bash
sudo apt-get update
sudo apt-get install bash curl make shellcheck shfmt socat
```

## Usage

Start the server on the default loopback address and port:

```bash
./bin/bash-http serve
```

Select another host or port when needed:

```bash
./bin/bash-http serve --host 127.0.0.1 --port 9090
```

Hosts must be IPv4 addresses or DNS hostnames. Ports must be integers from 1 to
65535. The server binds to `127.0.0.1:8080` by default.

With the server running:

```bash
curl http://127.0.0.1:8080/health
```

The response body is exactly:

```json
{"status":"ok"}
```

Use `./bin/bash-http help` for the current CLI. The `routes` and `validate`
commands are reserved for Phase 2 and currently return a non-zero status.

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
```

Integration tests use `TEST_HOST` and `TEST_PORT` when those environment
variables are set. Startup uses bounded readiness probes, and all listener
processes and temporary files are cleaned up when the test exits.

## Current HTTP subset

- one HTTP/1.1 request and response per connection;
- strict CRLF request lines and headers;
- no request bodies except `Content-Length: 0`;
- `GET /health`, including requests with a query string;
- central `400`, `404`, `405`, `500`, and `501` responses;
- `Connection: close` on every response.

See [`docs/`](docs/README.md) for architecture, exact protocol behavior,
technical decisions, and the phased roadmap.
