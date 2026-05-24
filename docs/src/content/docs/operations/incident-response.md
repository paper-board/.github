---
title: Incident response
description: Severity classification, escalation path, on-call rotation placeholder, and postmortem template for paper-board incidents.
sidebar:
  order: 5
status: shipped
owner: '@paper-board/docs-maintainers'
updated: '2026-05-24'
---

Incident response for paper-board follows a severity-gated flow: classify first, then execute
the matching playbook. On-call rotation and PagerDuty integration land in Phase 4; until then,
the engineering lead is the single point of contact.

## Severity matrix

| Severity | Condition                                                              | Response target | Comms channel                    |
| -------- | ---------------------------------------------------------------------- | --------------- | -------------------------------- |
| SEV-1    | Complete outage, data loss, or security breach                         | 15 min          | Slack `#incidents` + direct call |
| SEV-2    | Core feature broken for ≥ 1 tenant; no data loss; workaround unknown   | 1 hour          | Slack `#incidents`               |
| SEV-3    | Intermittent errors; workaround exists; no data loss                   | 4 hours         | Slack `#eng`                     |
| SEV-4    | Performance regression or cosmetic defect below user-visible threshold | next sprint     | Jira ticket                      |

Classify conservatively — downgrade during investigation if evidence supports it. Never
upgrade silently; announce the severity change in the incident channel.

## Incident lifecycle

```mermaid
stateDiagram-v2
  [*] --> Detected: alert fires or user report
  Detected --> Triaged: on-call classifies severity
  Triaged --> Investigating: runbook opened, timeline started
  Investigating --> Mitigated: impact stopped (not necessarily root-caused)
  Mitigated --> Resolved: root cause confirmed + fix deployed
  Resolved --> Postmortem: SEV-1 / SEV-2 mandatory; SEV-3 optional
  Postmortem --> [*]: action items filed in Jira

  classDef controlPlane fill:#10b981,stroke:#047857,color:#fff
  classDef dataPlane fill:#3b82f6,stroke:#1d4ed8,color:#fff
  classDef sandbox fill:#f97316,stroke:#c2410c,color:#fff
  classDef external fill:#ef4444,stroke:#b91c1c,color:#fff
  classDef persistence fill:#6b7280,stroke:#374151,color:#fff
```

## On-call rotation

_Placeholder — Phase 4 fills this section with PagerDuty schedule and escalation policy._

Current (pre-Phase 4):

| Role       | Contact                            |
| ---------- | ---------------------------------- |
| Primary    | engineering lead (direct Slack DM) |
| Escalation | repository owner                   |
| PagerDuty  | _not yet configured_               |

## First-response checklist

Run these immediately on any SEV-1 or SEV-2 alert.

```sh
# 1. Check service health
kubectl get pods -n paper-board
kubectl top pods -n paper-board

# 2. Check error rate (last 15 min)
# Grafana: {service="<svc>"} | json | level="error" | rate[15m]

# 3. Check DB connectivity
kubectl exec -n paper-board deploy/<svc> -- \
  pg_isready -h pgbouncer.paper-board.svc.cluster.local -p 6432

# 4. Check recent deployments
helm history agent-manager -n paper-board | tail -5

# 5. Capture trace_id from logs for cross-service correlation
kubectl logs -n paper-board -l app=<svc> --tail=50 | grep '"level":"error"'
```

If the service is unreachable: open the [Deployment runbook](./deployment.md) and follow the
pod crash / rollback procedure.

## Mitigation patterns

### Immediate rollback

```sh
helm rollback agent-manager <prev-revision> -n paper-board
kubectl rollout status deployment/<svc> -n paper-board
```

### Feature flag / service disable

```sh
# disable a specific service while preserving others
helm upgrade agent-manager paper-board/infra/helm/agent-manager \
  --reuse-values \
  --set agents.enabled=false \
  -n paper-board
```

### Scale to zero (SEV-1 isolation)

```sh
kubectl scale deployment/<svc> --replicas=0 -n paper-board
# restore after fix
kubectl scale deployment/<svc> --replicas=2 -n paper-board
```

### DB advisory lock stuck

```sql
-- identify holder
SELECT pid, query, state, wait_event_type
FROM pg_stat_activity
WHERE wait_event_type = 'Lock';

-- terminate (confirm with team first)
SELECT pg_terminate_backend(<pid>);
```

## Communication templates

### SEV-1 initial post (Slack `#incidents`)

```
:red_circle: SEV-1 INCIDENT — <service> — <short description>
Started: HH:MM UTC
Impact: <what is broken, who is affected>
IC: @<handle>
Status: investigating
Next update: HH:MM UTC (15 min)
```

### SEV-1 resolution post

```
:white_check_mark: RESOLVED — <service> — <short description>
Duration: X hours Y min
Root cause: <1 sentence>
Fix: <1 sentence>
Postmortem: <Confluence link or "scheduled for YYYY-MM-DD">
```

## Postmortem process

SEV-1 and SEV-2 require a postmortem within 48 hours of resolution.

1. Create a Confluence page under `paperboard / Postmortems / YYYY-MM-DD-<svc>-<slug>`.
2. Use the postmortem template from the [Runbook template](./runbook-template.md).
3. File action items as Jira Stories under the relevant Epic before publishing.
4. Schedule a 30-minute review call if ≥ 2 engineers were involved.
5. Link the Confluence page from the resolved Jira incident ticket.

Blameless postmortems only. The goal is system improvement, not attribution. Phrases like
"engineer failed to" are replaced with "the system did not prevent" or "the runbook did not
specify."
