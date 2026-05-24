---
title: Cloudflare Pages + Access setup record
description: Manual steps performed to provision the docs portal infrastructure.
sidebar:
  order: 10
status: shipped
owner: '@paper-board/docs-maintainers'
updated: 2026-05-24
---

This page records the manual Cloudflare dashboard steps for the docs portal. Reproduce these only if rebuilding from scratch.

## Pages project

- Name: `paperboard-docs`
- Source: `github.com/paper-board/.github` on GitHub (branch `main`)
- Build command: `cd docs && npm run build`
- Build output: `docs/dist`
- Custom domain: `docs.paperboard.app`

### Steps

1. Cloudflare dashboard → Workers & Pages → Create application → Pages → Connect to Git.
2. Select `paper-board/.github` repo, branch `main`.
3. Set project name: `paperboard-docs`.
4. Production branch: `main`.
5. Build settings: framework preset = Astro, build command = `cd docs && npm run build`, build output = `docs/dist`.
6. Click Save and Deploy. First build takes ~3-5 min.

## Custom domain

1. Pages project → Custom domains → Set up custom domain.
2. Enter `docs.paperboard.app`.
3. Cloudflare auto-creates a CNAME from `docs.paperboard.app` → `paperboard-docs.pages.dev`.
4. Wait for DNS propagation (~30 sec).
5. Verify: `curl -I https://docs.paperboard.app` returns 200 OK (before SSO is active).

## Access policy

- IdP: Google OAuth
- Allow rule: emails ending in `@kovankaya.com` + per-email guest whitelist
- Session duration: 24 hours

### Steps

1. Cloudflare dashboard → Zero Trust → Access → Applications → Add an application → Self-hosted.
2. Application name: `paperboard docs`.
3. Session duration: 24 hours.
4. Application domain: `docs.paperboard.app`.
5. Add Identity Provider: Google → enter Google OAuth client ID + secret (create via console.cloud.google.com if needed).
6. Add policy: Name `paperboard team + guests`. Action: Allow. Include rule: `Emails ending in @kovankaya.com` OR `Emails in: <guest-email-list>`.
7. Save.
8. Verify: incognito browser → `https://docs.paperboard.app` → redirects to Google SSO → after sign-in renders docs.

## Secrets

| Secret                  | Scope      | Description                                                        |
| ----------------------- | ---------- | ------------------------------------------------------------------ |
| `CLOUDFLARE_API_TOKEN`  | org secret | Single permission: Account / Cloudflare Pages / Edit               |
| `CLOUDFLARE_ACCOUNT_ID` | org secret | Cloudflare Account ID (dashboard → Account → Account ID)           |
| `DOCS_DISPATCH_PAT`     | org secret | Fine-grained PAT, repository_dispatch:write on paper-board/.github |

`CLOUDFLARE_ACCESS_AUD` is deferred to Phase 5+ (Access JWT verification for API endpoints behind the SSO gate).
