import { facts, site } from '../content'
import { LinkIcon, LockIcon, OfflineIcon } from './icons'

const icons = { link: LinkIcon, offline: OfflineIcon, lock: LockIcon } as const

export function OpenSource() {
  return (
    <section id="open" className="card card--padded" data-snap-section="" data-offset="96" aria-labelledby="open-title">
      <h2 id="open-title" className="h2 reveal">Built in the open.</h2>
      <div className="open__row">
        <div className="term">
          <div className="term__bar" aria-hidden="true">
            <span className="term__dot" style={{ background: '#ff5f57' }} />
            <span className="term__dot" style={{ background: '#febc2e' }} />
            <span className="term__dot" style={{ background: '#28c840' }} />
            <span className="term__title">~ — zsh</span>
          </div>
          <div className="term__body">
            <div className="term__line type type1"><span className="term__prompt">$</span> git clone {site.repo}</div>
            <div className="term__line type type2"><span className="term__prompt">$</span> cd shelfy</div>
            <div className="term__line type type3"><span className="term__prompt">$</span> scripts/run.sh</div>
            <div className="term__line term__ok type type--out type4">** BUILD SUCCEEDED **</div>
            <div className="term__line term__muted type type--out type5">Launched Shelfy.app<span className="caret" aria-hidden="true" /></div>
          </div>
        </div>
        <ul className="facts">
          {facts.map((fact) => {
            const Icon = icons[fact.icon]
            return (
              <li key={fact.title} className="fact reveal">
                <span className={`fact__icon fact__icon--${fact.color}`} aria-hidden="true"><Icon /></span>
                <div><p className="fact__title">{fact.title}</p><p className="fact__text">{fact.text}</p></div>
              </li>
            )
          })}
        </ul>
      </div>
    </section>
  )
}
