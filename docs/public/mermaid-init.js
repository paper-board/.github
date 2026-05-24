// Client-side Mermaid renderer for Starlight + expressive-code.
//
// expressive-code emits mermaid blocks as:
//   <pre data-language="mermaid">
//     <code>
//       <div class="ec-line"><div class="code"><span>...line text...</span></div></div>
//       ...
//     </code>
//   </pre>
//
// Mermaid wants <div class="mermaid">graph source</div>. This script extracts
// the line text (joined with \n) and replaces each <pre> with a mermaid div.

import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11.15.0/dist/mermaid.esm.min.mjs';

const THEME = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default';
mermaid.initialize({ startOnLoad: false, theme: THEME, securityLevel: 'strict' });

const extractSource = (pre) => {
  const lines = pre.querySelectorAll('.ec-line');
  if (lines.length > 0) {
    return Array.from(lines).map((l) => l.textContent ?? '').join('\n');
  }
  // Fallback: plain <pre><code>... layout
  const code = pre.querySelector('code');
  return (code ?? pre).textContent ?? '';
};

const render = async () => {
  const pres = document.querySelectorAll('pre[data-language="mermaid"]');
  if (pres.length === 0) return;
  pres.forEach((pre) => {
    const src = extractSource(pre);
    const div = document.createElement('div');
    div.className = 'mermaid';
    div.textContent = src;
    pre.replaceWith(div);
  });
  try {
    await mermaid.run({ querySelector: '.mermaid' });
  } catch (err) {
    console.error('[mermaid] render error', err);
  }
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', render);
} else {
  render();
}
