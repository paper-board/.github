import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://docs.paperboard.app',
  integrations: [
    starlight({
      title: 'paperboard',
      description: 'Internal documentation for the paperboard platform.',
      logo: { src: './public/images/logo.svg', replacesTitle: false },
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
        tr: { label: 'Türkçe', lang: 'tr' },
      },
      pagefind: true,
      components: {
        PageFrame: './src/components/FallbackBanner.astro',
      },
      sidebar: [
        { label: 'Onboarding', items: [{ autogenerate: { directory: 'onboarding' } }] },
        { label: 'Architecture', items: [{ autogenerate: { directory: 'architecture' } }] },
        { label: 'Services', items: [{ autogenerate: { directory: 'services' } }], collapsed: false },
        { label: 'Standards', items: [{ autogenerate: { directory: 'standards' } }] },
        { label: 'Operations', items: [{ autogenerate: { directory: 'operations' } }] },
        { label: 'Decisions', items: [{ autogenerate: { directory: 'decisions' } }] },
      ],
      customCss: ['./src/styles/custom.css'],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/paper-board' },
      ],
      lastUpdated: true,
      pagination: true,
    }),
  ],
  markdown: {
    syntaxHighlight: 'shiki',
    shikiConfig: { theme: 'github-dark' },
  },
});
