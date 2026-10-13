# Shelfy website

The marketing website for Shelfy, a native macOS downloads shelf. Built with React, TypeScript, and Vite. The page is a static build with no server or environment variables.

## Develop

From this directory:

```sh
npm ci
npm run dev
```

The development server runs at `http://127.0.0.1:5174`.

## Build and preview

```sh
npm run build
npm run preview
```

The build checks TypeScript and writes the site to `dist/`. The preview server runs at `http://127.0.0.1:4174`.

## Edit

- `src/content.ts` contains the shared copy, repository URL, source archive, optional packaged release URL, and FAQ answers.
- `src/components/` contains the page sections and interactive demos.
- `src/styles/` contains the layout, color tokens, and motion rules.
- `index.html` contains the canonical URL, search description, and social metadata.
- `public/og.png` is the 1200 × 630 social preview. `public/` also contains the browser icons, `robots.txt`, and `sitemap.xml`.

The Anybody and DM Mono fonts load from Google Fonts. System fonts are available as fallbacks. Motion respects the visitor's reduced-motion preference.

## Hosting

The production domain is `https://getshelfy.app/`. `wrangler.jsonc` configures Cloudflare Workers static assets with `dist/` as the output directory and a custom domain binding. Cloudflare manages the DNS record and TLS certificate for that binding. The domain and zone must exist in the target Cloudflare account before deployment.

Run the build before deploying the static output through the chosen hosting workflow. If the production domain changes, update `index.html`, `public/robots.txt`, `public/sitemap.xml`, and `wrangler.jsonc` together.

The site links directly to the Mac disk image (the signed and notarized universal app) on GitHub Releases. Update `site.releaseDownload` in `src/content.ts` when publishing a new version. Setting it to `null` enables the source ZIP and build instructions as a fallback. Distribution and copyright ownership are under Zazen Technology Group LLC.

## Design and scrolling

The rendered copy, tour artwork, and animation keyframes follow the [Claude draft](https://claude.ai/artifact/FtktCvdQq9fLztgVNfCDgG#page-dcb81aee8d83). Keep display text identical to that draft, except where the app has changed since (1.1.0's Move to Trash replaced the read-only fact and the FAQ answer about moving files); download and source URLs point to the real release and repository.

`src/lib/scrollEngine.ts` uses the deployed benbreslow.dev scroll engine’s interpolation, wheel speed, idle delay, directional settling, and keyboard navigation. It supports comma-separated rest points and hold ranges for the three scenes within Shelfy’s single tour. Reduced Motion retains native scrolling.
