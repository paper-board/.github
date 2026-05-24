# paperboard page frontmatter schema

Required for every Markdown page published under `content/docs/`. Validated by
`scripts/validate-frontmatter.sh` on every docs PR. Missing required fields or invalid enum
values fail the build.

**Exception:** ADR mirror pages use the ADR frontmatter schema (see below) — the aggregator
rewrites them into the page schema at build time.

______________________________________________________________________

## Page frontmatter schema

```yaml
---
title: "Agents service"            # required — string; becomes H1 + browser title
description: "REST + SSE agent..." # required — string; ≤ 160 chars; SEO meta + sidebar tooltip
sidebar:
  order: 1                         # required — int; ordering within parent sidebar group
  label: "Agents"                  # optional — string; sidebar label override (omit to use title)
status: "shipped"                  # required — enum: shipped | draft | placeholder | deprecated
owner: "@paper-board/<team>"       # required — GitHub team handle of page maintainer
updated: "2026-05-24"              # required — ISO date YYYY-MM-DD of last substantive edit
phase_introduced: "1.1"           # optional — enum: 1.0 | 1.1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10
toc: true                          # optional — default true; per-page TOC generation
---
```

### Field rules

| Field              | Type    | Required | Constraints                                                                    |
| ------------------ | ------- | -------- | ------------------------------------------------------------------------------ |
| `title`            | string  | yes      | non-empty                                                                      |
| `description`      | string  | yes      | ≤ 160 chars                                                                    |
| `sidebar.order`    | int     | yes      | positive integer                                                               |
| `sidebar.label`    | string  | no       | omit to inherit `title`                                                        |
| `status`           | enum    | yes      | `shipped` \| `draft` \| `placeholder` \| `deprecated`                          |
| `owner`            | string  | yes      | must start with `@paper-board/`                                                |
| `updated`          | string  | yes      | ISO date `YYYY-MM-DD`                                                          |
| `phase_introduced` | string  | no       | `1.0` \| `1.1` \| `2` \| `3` \| `4` \| `5` \| `6` \| `7` \| `8` \| `9` \| `10` |
| `toc`              | boolean | no       | default `true`                                                                 |

### Status enum semantics

| Value         | Meaning                                            |
| ------------- | -------------------------------------------------- |
| `shipped`     | content reflects live, merged code                 |
| `draft`       | work in progress; may contain gaps or TODOs        |
| `placeholder` | service not yet shipped; stub page with phase link |
| `deprecated`  | content superseded; left for historical reference  |

### Owner team handles

Cross-cutting pages: `@paper-board/docs-maintainers`

Per-service pages: `@paper-board/<svc>-maintainers` (e.g. `@paper-board/agents-maintainers`)

______________________________________________________________________

## ADR frontmatter schema

ADR pages in `paper-board/.github/docs/adr/` use a separate schema. The aggregator converts
them to the page schema above at build time for the Decisions section.

```yaml
---
adr_number: "0015"                   # required — 4-digit zero-padded string
title: "MVP launch phase rebalance"  # required — string
status: "accepted"                   # required — enum: proposed | accepted | superseded | deprecated
date: "2026-05-21"                   # required — ISO date of acceptance
scope: "system"                      # required — enum: system | backend
supersedes:                          # optional — list of ADR numbers this one replaces
  - "0009"
superseded_by: null                  # optional — ADR number that replaces this one
amends:                              # optional — list of ADR numbers this one modifies
  - "0014"
---
```

______________________________________________________________________

## validate-frontmatter.sh exit codes

| Code | Meaning                                             |
| ---- | --------------------------------------------------- |
| `0`  | all pages valid                                     |
| `1`  | at least one missing required field or invalid enum |
| `2`  | script invocation error (bad args, missing workdir) |

Error format (stderr): `<level>: <md-path>:<line> — <message>`

Example:

```
MISSING_FIELD: content/docs/services/agents/api-reference.md:1 — required field 'status' missing
INVALID_ENUM: content/docs/services/agents/index.md:6 — status='wip' not in [shipped, draft, placeholder, deprecated]
```
