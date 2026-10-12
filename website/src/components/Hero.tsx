import { site } from '../content'
import { ArrowDownIcon } from './icons'

export function Hero() {
  return (
    <section id="top" className="hero" aria-labelledby="hero-title">
      <h1 id="hero-title" className="hero__title">
        {site.name}
      </h1>
      <p className="hero__tagline">{site.tagline}</p>
      <div className="hero__actions">
        <a className="btn btn--accent shine" href={site.releaseDownload ?? '#download'}>
          <span>{site.releaseDownload ? 'download for mac' : 'get shelfy for mac'}</span>
          <ArrowDownIcon />
        </a>
        <a className="btn btn--plain" href={site.repo} target="_blank" rel="noreferrer">
          source on GitHub ↗
        </a>
      </div>
      <p className="hero__note">{site.note}</p>
    </section>
  )
}
