# Contributing

Contributions that keep the HTTP and OpenAPI subset small, explicit, and
educational are welcome.

## Setup

The supported native environment and required tools are documented in
[`docs/development.md`](docs/development.md). The containerized path requires
Docker Engine and Docker Compose 2.17 or newer.

## Checks

Run the native checks when all dependencies are installed:

```bash
make check
```

Run the same containerized verification used by CI before opening a pull
request:

```bash
make container-check
```

Behavior changes should include the smallest test that demonstrates the public
contract or regression. Update the supported-subset documentation when a
change affects HTTP, OpenAPI, validation, or response behavior.

Keep generated data, local configuration, databases, logs, editor settings,
and agent metadata out of commits.
