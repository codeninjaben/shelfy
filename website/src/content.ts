export const site = {
  name: 'shelfy',
  tagline: 'your downloads, tucked at the edge of your screen',
  note: 'free and open source · macOS 26 or later',
  repo: 'https://github.com/codeninjaben/shelfy',
  // Set this to a packaged Mac release URL when one is available.
  releaseDownload: 'https://github.com/codeninjaben/shelfy/releases/download/v1.0.0/Shelfy-1.0.0-universal.zip' as string | null,
  sourceArchive: 'https://github.com/codeninjaben/shelfy/archive/refs/heads/main.zip',
  buildGuide: 'https://github.com/codeninjaben/shelfy#build-and-run',
  author: 'ben breslow',
  authorSite: 'https://benbreslow.dev',
} as const

export const statement = ['every', 'download', 'lands', 'on', 'a', 'shelf,', 'one', 'reach', 'away.'] as const

export const steps = [
  { label: 'download', title: 'It lands on the shelf.' },
  { label: 'reach', title: 'The tab slides out.' },
  { label: 'drag', title: 'It goes where you need it.' },
] as const

export const chips = [
  'free & open source',
  'Swift + SwiftUI',
  'Liquid Glass',
  'any browser',
  'left or right edge',
  'menu bar shelfy',
  'any display',
  'Reduce Motion',
  'Reduce Transparency',
  'VoiceOver',
  'launch at login',
] as const

export const facts = [
  { icon: 'link', color: 'sun', title: 'References, not copies.', text: 'Clearing the shelf never moves or deletes a file.' },
  { icon: 'offline', color: 'sky', title: 'No network access.', text: 'Its sandbox has no way online, so nothing leaves your Mac.' },
  { icon: 'lock', color: 'mint', title: 'Read-only.', text: 'It can see your Downloads folder, never change it.' },
] as const

export type Faq = { q: string; a: string; link?: { label: string; href: string } }

export const faqs: readonly Faq[] = [
  { q: 'Is it really free?', a: 'Yes. Shelfy is free and open source, and all of the code is on', link: { label: 'GitHub', href: site.repo } },
  { q: 'Does it move my files?', a: 'Never. The shelf only keeps references, so clearing it leaves the originals right where they are.' },
  { q: 'What about half-finished downloads?', a: 'They never show up. A file only lands on the shelf once the download is complete.' },
  {
    q: 'Which browsers does it work with?',
    a: 'All of them. Shelfy watches the folder, not the browser, so Safari, Chrome, Firefox, Arc and anything else that saves to Downloads just works.',
  },
  { q: 'Can it watch a different folder?', a: 'Yes. Pick any folder in Settings and new files there land on the shelf instead.' },
  { q: 'What do I need?', a: 'A Mac running macOS 26 or later. Building it yourself takes Xcode 26 or later.' },
]
