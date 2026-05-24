#!/usr/bin/env node
// generate-adr-index.js — Build content/docs/decisions/index.md from ADR files.
//
// Per design §7. Reads every *.md under content/docs/decisions/ (after aggregate
// mirrors docs/adr/ there), extracts metadata, groups by status, sorts by adr_number,
// and emits a Markdown table.
//
// ADR files in this repo use bold-field markdown style ("**Status:** accepted")
// rather than YAML frontmatter. The script handles both formats defensively:
//   1. Try to parse YAML frontmatter block (--- ... ---).
//   2. Fall back to bold-field extraction (**Key:** value).
//   3. Fall back to filename-derived adr_number if no frontmatter at all.

import { readdirSync, readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';

let yamlParse = null;
try {
  const yaml = await import('yaml');
  yamlParse = yaml.parse;
} catch {
  // yaml package not available; YAML frontmatter path will be skipped
}

const DECISIONS = join(process.cwd(), 'content', 'docs', 'decisions');

if (!existsSync(DECISIONS)) {
  console.error(`generate-adr-index: ${DECISIONS} not found — run aggregate-docs.sh first`);
  process.exit(1);
}

const files = readdirSync(DECISIONS)
  .filter(f => /^\d{4}-.*\.md$/.test(f))
  .sort();

function extractBoldField(content, key) {
  const re = new RegExp(`\\*\\*${key}:\\*\\*\\s*(.+)`, 'i');
  const m = content.match(re);
  return m ? m[1].trim() : null;
}

function filenameToNumber(filename) {
  const m = filename.match(/^(\d+)/);
  return m ? m[1] : '0000';
}

function extractTitle(content, filename) {
  const m = content.match(/^#\s+(.+)/m);
  if (m) return m[1].replace(/^\d+\s*[—–-]\s*/, '').trim();
  return filename.replace(/^\d+-/, '').replace(/-/g, ' ').replace('.md', '');
}

const adrs = files.map(file => {
  const raw = readFileSync(join(DECISIONS, file), 'utf8');

  let fm = null;
  const yamlBlock = raw.match(/^---\n([\s\S]*?)\n---/);
  if (yamlBlock && yamlParse) {
    try { fm = yamlParse(yamlBlock[1]); } catch { /* ignore */ }
  }

  const adr_number = fm?.adr_number ?? filenameToNumber(file);
  const title      = fm?.title ?? extractTitle(raw, file);
  const status     = fm?.status ?? extractBoldField(raw, 'Status') ?? 'accepted';
  const date       = fm?.date ?? extractBoldField(raw, 'Date') ?? '';
  const scope      = fm?.scope ?? extractBoldField(raw, 'Scope') ?? 'system';
  const supersedes = fm?.supersedes ?? [];
  const superseded_by = fm?.superseded_by ?? extractBoldField(raw, 'Superseded by') ?? null;

  return { file, adr_number: String(adr_number), title, status: status.toLowerCase(), date, scope, supersedes, superseded_by };
});

const KNOWN_STATUSES = ['accepted', 'proposed', 'superseded', 'deprecated'];

const byStatus = { accepted: [], proposed: [], superseded: [], deprecated: [] };
for (const a of adrs) {
  const bucket = byStatus[a.status] ? a.status : 'accepted';
  byStatus[bucket].push(a);
}
for (const status of KNOWN_STATUSES) {
  byStatus[status].sort((a, b) => a.adr_number.localeCompare(b.adr_number, undefined, { numeric: true }));
}

const today = new Date().toISOString().slice(0, 10);

const out = [
  '---',
  'title: Architecture Decision Records',
  'description: Index of all ADRs grouped by status.',
  'sidebar:',
  '  order: 0',
  'status: shipped',
  'owner: "@paper-board/docs-maintainers"',
  `updated: ${today}`,
  '---',
  '',
  '# Architecture Decision Records',
  '',
  'Auto-generated on each deploy from ADR files in `docs/adr/`. Do not edit directly.',
  '',
];

let total = 0;
for (const status of KNOWN_STATUSES) {
  const group = byStatus[status];
  if (group.length === 0) continue;
  total += group.length;
  const label = status.charAt(0).toUpperCase() + status.slice(1);
  out.push(`## ${label} (${group.length})`);
  out.push('');
  out.push('| # | Title | Date | Scope | Supersedes / Superseded by |');
  out.push('| --- | --- | --- | --- | --- |');
  for (const a of group) {
    const slug = a.file.replace(/\.md$/, '/');
    const link = `[${a.title}](./${slug})`;
    const replaceCol = a.superseded_by
      ? `superseded by ${a.superseded_by}`
      : (Array.isArray(a.supersedes) && a.supersedes.length > 0 ? `supersedes ${a.supersedes.join(', ')}` : '—');
    out.push(`| ${a.adr_number} | ${link} | ${a.date} | ${a.scope} | ${replaceCol} |`);
  }
  out.push('');
}

const outPath = join(DECISIONS, 'index.md');
writeFileSync(outPath, out.join('\n'));
console.log(`generate-adr-index: wrote ${outPath} (${total} ADRs)`);
