import { Fragment } from 'react'
import { statement } from '../content'

export function Statement() {
  return (
    <section className="card statement" data-rest="0.9" data-hold="0.8 1" aria-label="Every download, one reach away">
      <div className="statement__stage">
        <p className="statement__text">
          {statement.map((word, i) => (
            <Fragment key={word}>
              {i > 0 && ' '}
              <span className={`ws-word ws${i + 1}${word === 'reach' ? ' ws-accent' : ''}`}>{word}</span>
            </Fragment>
          ))}
        </p>
      </div>
    </section>
  )
}
