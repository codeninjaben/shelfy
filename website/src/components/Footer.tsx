import { site } from '../content'

export function Footer() {
  return (
    <footer className="footer">
      <span>© {new Date().getFullYear()} shelfy · free and open source</span>
      <a href={site.authorSite}>made by {site.author} ↗</a>
    </footer>
  )
}
