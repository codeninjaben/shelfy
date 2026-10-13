import icon from '../assets/shelfy-icon.png'
import { site } from '../content'
import { GitHubIcon } from './icons'

export function Nav() {
  return (
    <header className="nav">
      <div className="nav__inner">
        <a className="nav__brand" href="#top">
          <img src={icon} alt="" width={34} height={34} />
          <span>{site.name}</span>
        </a>
        <nav className="nav__links" aria-label="Main">
          <a className="nav__text" href="#tour">tour</a>
          <a className="nav__text" href="#customize">customize</a>
          <a className="nav__text" href="#faq">faq</a>
          <span className="nav__divider" aria-hidden="true" />
          <a className="nav__icon" href={site.repo} target="_blank" rel="noreferrer" aria-label="Shelfy source on GitHub">
            <GitHubIcon />
          </a>
          <a className="pill" href="#download">download</a>
        </nav>
      </div>
    </header>
  )
}
