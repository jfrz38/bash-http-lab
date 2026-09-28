# Development

## Docker

Docker Engine with the Compose plugin provides reproducible Linux environments
for both the example server and the complete project checks.

Start the example server with:

```bash
docker compose up --build --wait server
```

Set `PORT` to publish it on a different host port:

```bash
PORT=9090 docker compose up --build --wait server
```

Stop the sandbox with:

```bash
docker compose down
```

## Native setup

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

## Make targets

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

Use `make check` when all native dependencies are available. The reproducible
CI path is:

```bash
make container-check
```
