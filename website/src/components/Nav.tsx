import { useState } from 'react'
import icon from '../assets/shelfy-icon.png'
import { site } from '../content'
import { GitHubIcon } from './icons'

export function Nav() {
  const [open, setOpen] = useState(false)
  return (
    <header className="nav" onKeyDown={(event) => {
      if (event.key === 'Escape') {
        setOpen(false)
        document.getElementById('menu-toggle')?.focus()
      }
    }}>
      <div className="nav__inner">
        <a className="nav__brand" href="#top" onClick={() => setOpen(false)}>
          <img src={icon} alt="" width={34} height={34} />
          <span>{site.name}</span>
        </a>
        <button id="menu-toggle" className="nav__toggle" type="button" aria-expanded={open}
          aria-controls="main-navigation" onClick={() => setOpen(!open)}>{open ? 'close ×' : 'menu +'}
        </button>
        <nav id="main-navigation" className={`nav__links${open ? ' is-open' : ''}`} aria-label="Main">
          <a className="nav__text" href="#tour" onClick={() => setOpen(false)}>tour</a>
          <a className="nav__text" href="#customize" onClick={() => setOpen(false)}>customize</a>
          <a className="nav__text" href="#faq" onClick={() => setOpen(false)}>faq</a>
          <span className="nav__divider" aria-hidden="true" />
          <a className="nav__icon" href={site.repo} target="_blank" rel="noreferrer" aria-label="Shelfy source on GitHub">
            <GitHubIcon />
          </a>
          <a className="pill" href="#download" onClick={() => setOpen(false)}>download</a>
        </nav>
      </div>
    </header>
  )
}
