# bash-http-lab

`bash-http-lab` is an experiment to implement in plain Bash some of the features
normally provided by a web framework.

It is a small HTTP server that accepts requests, finds routes, validates input,
runs middleware, calls handlers, and sends responses. The goal is to understand
what usually happens behind a framework, not to replace one.

This is a learning experiment, not a production server. Please do not put it on
the internet.

## What is in here

- an HTTP/1.1 server written in Bash;
- `socat` handling the TCP connections;
- an OpenAPI document defining the available routes;
- validation, middleware, and handlers implemented as shell scripts;
- JSON and YAML responses;
- a tiny users API with interchangeable JSON and SQLite persistence.

It deliberately supports only a small part of HTTP and OpenAPI. That keeps the
experiment understandable and, more importantly, finite.

## Try it

The quickest way to run it is with Docker:

```bash
docker compose up --build --wait server
curl http://127.0.0.1:8080/health
```

You should get:

```json
{"status":"ok"}
```

There is also a small users API to play with:

```bash
curl http://127.0.0.1:8080/users
curl http://127.0.0.1:8080/users/1
curl --request POST --header 'Content-Type: application/json' \
  --data '{"name":"Katherine Johnson"}' http://127.0.0.1:8080/users
```

When you are finished:

```bash
docker compose down
```

## Roughly how it works

```text
HTTP client -> socat -> Bash runtime -> Bash handler -> HTTP response
```

The OpenAPI file says which routes exist and which handler belongs to each one.
The Bash runtime does the plumbing around them: reading the request, checking
the input, running middleware, and building the response.

## Deliberate shortcuts

- each connection handles one request and then closes;
- native runs store users in `data/users.json` by default;
- the JSON backend does not coordinate concurrent writes;
- only a documented subset of HTTP, OpenAPI, and JSON Schema is supported.

Those choices make the code easier to inspect, but they also make the project
unsuitable for production use.

## More detail

- [Architecture](docs/architecture.md) explains the runtime, its components,
  and the repository structure.
- [Supported HTTP subset](docs/http-subset.md) describes the exact protocol and
  OpenAPI behavior.
- [Development](docs/development.md) covers native setup, CLI commands, tests,
  and other development tasks.

## License

This project is available under the [MIT License](LICENSE).
