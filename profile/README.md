# paper-board

AI agent platform — multi-tenant SaaS for building, running, and orchestrating LLM agents.

## Public repos (open source — MIT)

- **[sdk](https://github.com/paper-board/sdk)** — Go shared library: migrator, log, observability, common errors
- **[proto](https://github.com/paper-board/proto)** — gRPC `.proto` + OpenAPI specs (cross-service contracts)
- **[cli](https://github.com/paper-board/cli)** — `agentctl` customer command-line interface

## Architecture

12 GitHub repos, microservices, schema-per-service in single Postgres. See [docs/adr/](https://github.com/paper-board/.github/tree/main/docs/adr) for foundational decisions.

| Service   | Repo                                                 | Description                          |
|-----------|------------------------------------------------------|--------------------------------------|
| gateway   | `paper-board/gateway` (private)                     | Public API entry, auth middleware    |
| identity  | `paper-board/identity` (private)                    | Users, orgs, RBAC, JWT, MFA          |
| agents    | `paper-board/agents` (private)                      | Agent CRUD, sessions, prompt, LLM    |
| billing   | `paper-board/billing` (private)                     | Subscriptions, Stripe, metering      |
| platform  | `paper-board/platform` (private)                    | Audit, notify, webhook               |
| runtime   | `paper-board/runtime` (private)                     | Per-tenant data plane                |
| compute   | `paper-board/compute` (private)                     | gVisor sandbox, code execution       |

## Status

Pre-launch. Phase 1 in progress (schema foundation). See individual repos for details.

## Security

Vulnerability disclosure: security@paperboard.app. See [SECURITY.md](./SECURITY.md).

## Code of Conduct

[Contributor Covenant v2.1](./CODE_OF_CONDUCT.md).
