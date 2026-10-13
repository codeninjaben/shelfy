import icon from '../assets/shelfy-icon.png'
import { site } from '../content'
import { ArrowDownIcon } from './icons'
import '../styles/download.css'

export function GetShelfy() {
  return (
    <section id="download" className="card get" data-snap-end="" data-offset="96" aria-labelledby="get-title">
      <img className="get__icon reveal" src={icon} alt="Shelfy app icon" width={104} height={104} loading="lazy" />
      <h2 id="get-title" className="get__title">
        get {site.name}
      </h2>
      <p className="get__note">{site.note}</p>
      {!site.releaseDownload && (
        <p className="get__status">Build from source today. A packaged Mac download is coming soon.</p>
      )}
      <div className="get__actions">
        <a className="btn btn--lg btn--dark shine" href={site.releaseDownload ?? site.sourceArchive}>
          <span>{site.releaseDownload ? 'download for mac' : 'download source'}</span>
          <ArrowDownIcon />
        </a>
        <a className="btn btn--lg btn--plain" href={site.releaseDownload ? site.repo : site.buildGuide} target="_blank" rel="noreferrer">
          {site.releaseDownload ? 'source on GitHub ↗' : 'build instructions ↗'}
        </a>
      </div>
      {!site.releaseDownload && (
        <p className="get__build-note">Requires Xcode 26 or later. Choose your signing team in Xcode before building.</p>
      )}
    </section>
  )
}
