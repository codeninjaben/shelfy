import { facts, site } from '../content'
import { LinkIcon, LockIcon, OfflineIcon } from './icons'

const icons = { link: LinkIcon, offline: OfflineIcon, lock: LockIcon } as const

const clone = `git clone ${site.repo}`

export function OpenSource() {
  return (
    <section id="open" className="card card--padded" data-snap-section="" data-offset="96" aria-labelledby="open-title">
      <h2 id="open-title" className="h2 reveal">
        Built in the open.
      </h2>
      <div className="open__row">
        <div className="open__build">
          <div className="term">
            <div className="term__bar" aria-hidden="true">
              <span className="term__dot" style={{ background: '#ff5f57' }} />
              <span className="term__dot" style={{ background: '#febc2e' }} />
              <span className="term__dot" style={{ background: '#28c840' }} />
              <span className="term__title">~ — zsh</span>
            </div>
            <div className="term__body">
              <div className="term__line type type1">
                <span className="term__prompt">$</span> {clone}
              </div>
              <div className="term__line type type2">
                <span className="term__prompt">$</span> cd shelfy
              </div>
              <div className="term__line type type3">
                <span className="term__prompt">$</span> open Shelfy.xcodeproj
                <span className="caret" aria-hidden="true" />
              </div>
            </div>
          </div>
          <p className="open__build-note">
            macOS 26+ and Xcode 26+. Select your signing team in Xcode, then run the Shelfy scheme.{' '}
            <a href={site.buildGuide} target="_blank" rel="noreferrer">Read the build guide ↗</a>
          </p>
        </div>

        <ul className="facts">
          {facts.map((fact) => {
            const Icon = icons[fact.icon]
            return (
              <li key={fact.title} className="fact reveal">
                <span className={`fact__icon fact__icon--${fact.color}`} aria-hidden="true">
                  <Icon />
                </span>
                <div>
                  <p className="fact__title">{fact.title}</p>
                  <p className="fact__text">{fact.text}</p>
                </div>
              </li>
            )
          })}
        </ul>
      </div>
    </section>
  )
}
