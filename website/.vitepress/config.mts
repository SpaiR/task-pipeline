import { defineConfig } from 'vitepress'

const gh = 'https://github.com/SpaiR/task-pipeline'

// Absolute URL for the social card — link unfurlers can't resolve a relative path.
const ogImage = 'https://spair.github.io/task-pipeline/og-image.png'
const description =
  'Grill the plan, capture it at the depth you pick, then implement in any session — a chat-first task pipeline for Claude Code.'

export default defineConfig({
  title: 'task-pipeline',
  description,
  lang: 'en-US',

  // Project Pages are served under /<repo>/ — keep this in sync with the repo name.
  base: '/task-pipeline/',

  cleanUrls: true,
  lastUpdated: true,

  // changelog.md includes the repo's CHANGELOG.md verbatim; its repo-relative
  // links (CLAUDE.md, CONTRIBUTING.md, docs/contract.md) resolve on GitHub, not
  // on the site. No site page lives at these paths, so ignoring them is safe.
  ignoreDeadLinks: [/\/CONTRIBUTING$/, /\/CLAUDE$/, /\/docs\/contract$/],

  head: [
    // Head links are emitted verbatim (no base prefixing) — spell out the base.
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/task-pipeline/favicon.svg' }],
    ['link', { rel: 'icon', type: 'image/png', href: '/task-pipeline/favicon.png' }],
    ['meta', { name: 'theme-color', content: '#8A2BE2' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'task-pipeline' }],
    ['meta', { property: 'og:description', content: description }],
    ['meta', { property: 'og:image', content: ogImage }],
    ['meta', { property: 'og:image:width', content: '1200' }],
    ['meta', { property: 'og:image:height', content: '630' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['meta', { name: 'twitter:title', content: 'task-pipeline' }],
    ['meta', { name: 'twitter:description', content: description }],
    ['meta', { name: 'twitter:image', content: ogImage }],
  ],

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: 'Guide', link: '/guide/what-is-task-pipeline', activeMatch: '/guide/' },
      { text: 'Reference', link: '/reference/commands', activeMatch: '/reference/' },
      {
        text: 'v3.2.0',
        items: [
          { text: 'Changelog', link: '/changelog' },
          { text: 'Contributing', link: `${gh}/blob/main/CONTRIBUTING.md` },
        ],
      },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'What is task-pipeline?', link: '/guide/what-is-task-pipeline' },
            { text: 'Getting started', link: '/guide/getting-started' },
            { text: 'First win in 5 minutes', link: '/guide/first-win' },
            { text: 'Core concepts', link: '/guide/core-concepts' },
          ],
        },
        {
          text: 'Workflows',
          items: [
            { text: 'Capture a single task', link: '/guide/single-task' },
            { text: 'Grill before you capture', link: '/guide/grill' },
            { text: 'Roadmaps', link: '/guide/roadmaps' },
            { text: 'Autopilot a roadmap', link: '/guide/autopilot' },
            { text: 'Specs', link: '/guide/specs' },
            { text: 'Returning to a task later', link: '/guide/returning-later' },
          ],
        },
        {
          text: 'More',
          items: [
            { text: 'Why you can trust this', link: '/guide/trust' },
            { text: 'Comparison with alternatives', link: '/guide/comparison' },
            { text: 'FAQ', link: '/guide/faq' },
            { text: 'Troubleshooting', link: '/guide/troubleshooting' },
          ],
        },
      ],
      '/reference/': [
        {
          text: 'Reference',
          items: [
            { text: 'Commands overview', link: '/reference/commands' },
            { text: 'grill', link: '/reference/grill' },
            { text: 'to-task', link: '/reference/to-task' },
            { text: 'to-plan', link: '/reference/to-plan' },
            { text: 'to-roadmap', link: '/reference/to-roadmap' },
            { text: 'to-spec', link: '/reference/to-spec' },
            { text: 'roadmap-to-workflow', link: '/reference/roadmap-to-workflow' },
            { text: 'validate', link: '/reference/validate' },
          ],
        },
        {
          text: 'Project',
          items: [
            { text: 'Configuration', link: '/reference/configuration' },
            { text: '.task/ layout', link: '/reference/task-layout' },
          ],
        },
      ],
    },

    socialLinks: [{ icon: 'github', link: gh }],

    search: { provider: 'local' },

    editLink: {
      pattern: `${gh}/edit/main/website/:path`,
      text: 'Edit this page on GitHub',
    },

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © SpaiR',
    },
  },
})
