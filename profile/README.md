# paperboard

Anthropic-style Managed Agents platform. Multi-tenant agent runtime with isolated sandboxes. Self-host or cloud.

## Status

Phases 1–3 shipped (agents + identity + runtime + compute). Phase 4 active — backend MVP-0 substrate: audit + metering + notifications + onboarding + environments + vaults + cli + outbox + e2e tests. Phase 5 = MVP-0 launch (frontend).

## Architecture

19 repos planned, 16 active. Single Postgres cluster, schema-per-service. Internal gRPC, public REST + SSE. See [docs/adr/](https://github.com/paper-board/.github/tree/main/docs/adr) for foundational decisions.

### Backend services (12)

| Service       | Repo                                  | Phase | Description                                          |
| ------------- | ------------------------------------- | ----- | ---------------------------------------------------- |
| identity      | `paper-board/identity` (private)      | 2 ✅  | Users, orgs, RBAC, JWT, MFA, API keys                |
| agents        | `paper-board/agents` (private)        | 1 ✅  | Agent CRUD, sessions, prompt, LLM, tools, memory     |
| runtime       | `paper-board/runtime` (private)       | 3 ✅  | Per-tenant data-plane pod (stateless)                |
| compute       | `paper-board/compute` (private)       | 3 ✅  | gVisor sandbox, code execution, workspace bridge     |
| audit         | `paper-board/audit` (private)         | 4     | gRPC ingest + query API, centralized event log       |
| metering      | `paper-board/metering` (private)      | 4     | Raw events → roll-ups; invoice basis                 |
| notifications | `paper-board/notifications` (private) | 4     | Outbound notification gateway (e-mail Phase 4)       |
| onboarding    | `paper-board/onboarding` (private)    | 4     | Cross-service orchestrator (user → org + agent seed) |
| environments  | `paper-board/environments` (private)  | 4     | Container config + non-sensitive env vars            |
| vaults        | `paper-board/vaults` (private)        | 4     | Encrypted credentials store (GCP KMS envelope)       |
| gateway       | `paper-board/gateway` (private)       | 8     | Public API entry, auth middleware, routing           |
| billing       | `paper-board/billing` (private)       | 6     | Subscriptions, multi-provider payments, invoices     |

## Public repos (MIT)

- **[sdk](https://github.com/paper-board/sdk)** — Go shared library: migrator, log, observability, outbox, inbox, retry
- **[proto](https://github.com/paper-board/proto)** — gRPC `.proto` + OpenAPI specs (cross-service contracts)
- **[cli](https://github.com/paper-board/cli)** — `agentctl` command-line interface
- **[.github](https://github.com/paper-board/.github)** — org-wide community files, reusable CI workflows, lint baseline

## Standards

Nine engineering standards docs are publicly hosted in this repo:

- [Go coding conventions](https://github.com/paper-board/.github/blob/main/docs/standards/go-coding-conventions.md)
- [Service directory layout](https://github.com/paper-board/.github/blob/main/docs/standards/go-service-layout.md)
- [HTTP API conventions](https://github.com/paper-board/.github/blob/main/docs/standards/http-api-conventions.md)
- [Database conventions](https://github.com/paper-board/.github/blob/main/docs/standards/database-conventions.md)
- [Testing](https://github.com/paper-board/.github/blob/main/docs/standards/testing.md)
- [Configuration](https://github.com/paper-board/.github/blob/main/docs/standards/configuration.md)
- [Observability](https://github.com/paper-board/.github/blob/main/docs/standards/observability.md)
- [Error handling](https://github.com/paper-board/.github/blob/main/docs/standards/error-handling.md)
- [Build + release](https://github.com/paper-board/.github/blob/main/docs/standards/build-release.md)

## License

Open core: **[sdk](https://github.com/paper-board/sdk)**, **[proto](https://github.com/paper-board/proto)**, and **[cli](https://github.com/paper-board/cli)** are MIT. Backend service repos are proprietary (private).

## Security

Vulnerability disclosure: security@paperboard.app. See [SECURITY.md](./SECURITY.md).

## Code of Conduct

[Contributor Covenant v2.1](./CODE_OF_CONDUCT.md).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).
