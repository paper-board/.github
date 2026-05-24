#!/usr/bin/env node
// derive-glossary.js — Build content/docs/onboarding/glossary.md from CONTEXT-MAP.md.
//
// Source: CONTEXT-MAP.md lives in the agent-manager coord repo (coord root), not in
// paper-board/.github. In CI the coord repo is not checked out, so the source file
// is typically absent.
//
// Behaviour:
//   - If CONTEXT_MAP_PATH env var is set, use that path.
//   - Else look for the file two directories above the docs/ root (../../CONTEXT-MAP.md),
//     which resolves correctly when running from a local multi-repo checkout.
//   - If the file is not found at either location, log a warning and exit 0 (graceful
//     skip). The S2-authored static glossary at content/docs/onboarding/glossary.md
//     remains in place. This script is a Phase 5+ enhancement; missing source is not
//     a build failure.
//
// Integration deferred note: to enable in CI, either:
//   (a) Set CONTEXT_MAP_PATH to a path where the file has been checked out, or
//   (b) Ship a snapshot copy at docs/source-files/CONTEXT-MAP.snapshot.md and
//       set CONTEXT_MAP_PATH to that path in docs-deploy.yml.

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';

const FALLBACK = join(process.cwd(), '..', '..', 'CONTEXT-MAP.md');
const SOURCE = process.env.CONTEXT_MAP_PATH ?? FALLBACK;
const OUT = join(process.cwd(), 'content', 'docs', 'onboarding', 'glossary.md');

if (!existsSync(SOURCE)) {
  console.warn(`derive-glossary: source not found at ${SOURCE} — skipping (graceful). Static glossary unchanged.`);
  process.exit(0);
}

const src = readFileSync(SOURCE, 'utf8');

const entries = [];
let current = null;
for (const line of src.split('\n')) {
  const m = line.match(/^##\s+(.+)$/);
  if (m) {
    if (current) entries.push(current);
    current = { term: m[1].trim(), body: [] };
  } else if (current && line.trim()) {
    current.body.push(line);
  }
}
if (current) entries.push(current);

entries.sort((a, b) => a.term.localeCompare(b.term));

const today = new Date().toISOString().slice(0, 10);

const out = [
  '---',
  'title: Glossary',
  'description: Definitions of paperboard-specific terms, derived from CONTEXT-MAP.md.',
  'sidebar:',
  '  order: 4',
  'status: shipped',
  'owner: "@paper-board/docs-maintainers"',
  `updated: ${today}`,
  '---',
  '',
  '# Glossary',
  '',
  'Derived from `CONTEXT-MAP.md` in the agent-manager coord repo.',
  '',
];

for (const e of entries) {
  out.push(`## ${e.term}`);
  out.push('');
  out.push(e.body.join('\n').trim());
  out.push('');
}

writeFileSync(OUT, out.join('\n'));
console.log(`derive-glossary: wrote ${OUT} (${entries.length} terms)`);
