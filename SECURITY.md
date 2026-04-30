# Security Policy

## Reporting a vulnerability

Send a detailed report to **security@paperboard.app**.

Include:
- Affected repo + version (commit hash, tag, or "latest main")
- Steps to reproduce
- Expected vs actual behavior
- Impact assessment (data exposure, privilege escalation, DoS, etc.)

**Do not open public GitHub issues** for security reports.

## Response timeline

| Severity | Acknowledge | Initial response | Patch + disclosure |
|----------|-------------|------------------|--------------------|
| Critical | < 24 hours  | < 48 hours       | < 7 days           |
| High     | < 48 hours  | < 5 days         | < 30 days          |
| Medium   | < 5 days    | < 14 days        | next release       |
| Low      | < 14 days   | next release     | next release       |

## Disclosure policy

We follow **coordinated disclosure**: 90 days from initial report, or upon patch release if sooner. Reporter credited in CHANGELOG (unless anonymity requested).

## Bug bounty

Currently informal — material rewards on case-by-case basis. Formal bounty program planned post-GA.

## Supported versions

Only the latest minor version of each repo receives security patches. Older versions: best-effort.

## Scope

In-scope: paper-board/* repos, paperboard.app domain + subdomains, GHCR images.
Out-of-scope: third-party dependencies (report upstream), social engineering, DoS without working exploit.
