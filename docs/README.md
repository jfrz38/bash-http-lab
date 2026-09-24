# Project documentation

`bash-http-lab` is an educational project that explores how HTTP frameworks
work by implementing a deliberately small runtime in Bash. It is not intended
for production workloads or exposure to untrusted networks.

This directory is the source of truth for the project's technical direction:

- [Architecture](architecture.md) describes the runtime boundaries, request
  lifecycle, module responsibilities, and safety constraints.
- [HTTP subset](http-subset.md) defines the protocol behavior that each phase
  supports and how unsupported input is handled.
- [Decisions](decisions.md) records the important choices and their trade-offs.
- [Roadmap](roadmap.md) defines the implementation phases and their acceptance
  criteria.

## Current status

The project has implemented **Phase 4: OpenAPI validation subset**. OpenAPI
declares required path, query, and header parameters and top-level request
bodies. Supported scalar constraints and body types are checked after request
normalization and before handler execution.

## Fixed constraints

- The application runtime is Bash. No general-purpose language may implement
  part of the server.
- Standard Unix CLI tools may be used when they provide substantial value.
- Linux and WSL are the supported development and runtime environments.
- Docker provides a reproducible Linux sandbox for development and CI, not a
  production deployment artifact.
- TCP listening is delegated to `socat`; Bash does not implement sockets.
- OpenAPI becomes the source of truth for application routes in Phase 2.
- Readability and explicit behavior take priority over metaprogramming and
  minimizing line count.
- Every phase must be complete and tested before work proceeds to the next one.

## Documentation status language

The documents use the following terms:

- **Accepted**: a decision that implementation must follow.
- **Planned**: an intended direction whose detailed design is not complete.
- **Deferred**: explicitly outside the current phase.
- **Non-goal**: intentionally outside the project scope.
