# 0005 — REST public + gRPC internal communication

**Status:** accepted
**Date:** 2026-04-30
**Related:** ADR-0001 (multi-repo)

## Context

Seven services need to communicate. The public surface is customer-facing (browsers, curl, OpenAPI consumers). Internal traffic is performance-sensitive (every prompt request can fan out to 5+ hops). plan/14 implicitly chose "HTTP :8080 public REST, HTTP :8081 internal admin gRPC"; we make it explicit and add streaming.

## Decision

**Public** (customer ↔ `gateway`): REST + JSON + SSE + OpenAPI. The OpenAPI spec is generated from proto using `option (google.api.http)` annotations + grpc-gateway.

**Internal** (service ↔ service): gRPC + Protobuf. `paper-board/proto` is the source of truth. `buf generate` produces Go + TS clients.

**Cross-cutting** (audit, usage emit):
- Phases 1-3: synchronous gRPC.
- Phase 4+: async event bus (Redis Streams) + outbox pattern.

**Service discovery:**
- Phases 1-5: k8s Service DNS (`identity.paper-board.svc.cluster.local:50051`).
- Phase 6+: client-side load balancing.

**mTLS:**
- Phases 1-4: plain HTTP/2 + NetworkPolicy default-deny.
- Phase 5+: cert-manager + mTLS.

**Versioning:** major version in proto package name (`identity.v1`, `identity.v2`); breaking changes ship as a new package. `buf breaking` blocks PRs that violate compatibility.

## Rejected alternatives

- **REST everywhere.** Internal performance is poor (HTTP/1.1 + JSON parse on every hop); type safety is weak (manual struct sync).
- **gRPC everywhere with grpc-gateway.** Public gRPC is hostile to customers; an extra REST translation layer adds bugs; admin debugging via curl becomes awkward.
- **Service mesh (Istio).** Operational complexity is overkill for Phase 1; sidecar overhead per pod is significant.
- **Async events from Phase 1.** Outbox + saga discipline added on day one with no traffic to justify it (YAGNI).

## Consequences

**Gain:**
- Aligned with plan/14 + plan/02.
- gRPC streaming is required for compute/runtime anyway (Phase 6); starting in the gRPC ecosystem avoids a later migration.
- Customer documentation is Stripe-style OpenAPI.
- Internal type safety is enforced at compile time via proto.

**Auth propagation:** the gateway (or the per-service middleware in Phases 1-2) verifies the JWT or API key once. Downstream gRPC metadata carries `x-user-id`, `x-org-id`, `x-roles`, `x-trace-id`. Internal trust is delivered by NetworkPolicy through Phase 4 and by mTLS from Phase 5.

**Risk and mitigation:**
- Two specs to maintain (proto + auto-generated OpenAPI) — proto is the single source of truth, not a duplicate.
- Two codegen pipelines (Go + TS) — `buf generate` runs both with one command.
- HTTP/2 ingress configuration (nginx ingress controller) — handled in Phase 5.
