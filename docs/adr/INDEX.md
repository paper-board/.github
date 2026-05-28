# ADR Registry

Single source of truth for ADRs in this coord repo. Each ADR file carries a `**Scope:**` line in its frontmatter (`system` for cross-cutting / org-level, `backend` for backend-only).

| ADR  | Title                                                                                        | Scope   | Status                                              |
| ---- | -------------------------------------------------------------------------------------------- | ------- | --------------------------------------------------- |
| 0001 | [Multi-repo microservices architecture](./0001-multi-repo-microservices.md)                  | system  | accepted                                            |
| 0002 | [Schema-per-service in single Postgres](./0002-schema-per-service.md)                        | backend | accepted                                            |
| 0003 | [Strict ban on cross-schema FK](./0003-no-cross-schema-fk.md)                                | backend | accepted                                            |
| 0004 | [Migrator: shared SDK library + per-service binary](./0004-migrator-shared-library.md)       | backend | accepted                                            |
| 0005 | [REST public + gRPC internal communication](./0005-rest-public-grpc-internal.md)             | backend | accepted                                            |
| 0006 | [Vertical (tracer-bullet) implementation](./0006-vertical-implementation.md)                 | system  | accepted                                            |
| 0007 | [Repository topology + naming convention](./0007-repo-topology-naming.md)                    | system  | accepted                                            |
| 0008 | [License, Code of Conduct, commit convention](./0008-license-coc-commit-conventions.md)      | system  | accepted                                            |
| 0009 | [Product-first sequencing](./0009-product-first-sequencing.md)                               | system  | superseded by ADR-0014                              |
| 0010 | [Go Service Architecture & Standards](./0010-go-service-architecture.md)                     | system  | accepted                                            |
| 0011 | [Standards Refresh: Decouple Phase Roadmap from Timeless Rules](./0011-standards-refresh.md) | system  | accepted                                            |
| 0012 | [Auth Flow (Phase 2)](./0012-auth-flow.md)                                                   | system  | accepted                                            |
| 0013 | [agent-manager coord repo layout](./0013-agent-manager-coord-repo-layout.md)                 | system  | accepted                                            |
| 0014 | [MVP-first sequencing](./0014-mvp-first-sequencing.md)                                       | system  | accepted (supersedes ADR-0009; amended by ADR-0015) |
| 0015 | [MVP launch phase rebalance](./0015-mvp-launch-phase-rebalance.md)                           | system  | accepted (amends ADR-0014; amended by ADR-0016)     |
| 0016 | [Phase 4 backend MVP-0 substrate re-sequence](./0016-phase-4-mvp0-substrate-resequence.md)   | system  | accepted (amends ADR-0015)                          |

Conventions for new ADRs: assign `**Scope:** system | backend`, add a row here, follow Conventional Commits + `pr_review_loop_workflow` for the implementing PR.
