import { site } from '../content'

export function Footer() {
  return (
    <footer className="footer">
      <span>© {new Date().getFullYear()} {site.author} · free and open source</span>
      <a href={site.authorSite}>source on GitHub ↗</a>
    </footer>
  )
}
