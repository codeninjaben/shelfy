import { steps } from '../content'
import { CursorIcon } from './icons'

function Doc() {
  return (
    <div className="doc">
      <span />
      <span />
      <span />
    </div>
  )
}

const art = [
  <div key="download" className="tile__art t1" aria-hidden="true">
    <Doc />
    <div className="tray" />
  </div>,
  <div key="reach" className="tile__art t2" aria-hidden="true">
    <div className="edge" />
    <div className="tab" />
    <CursorIcon size={28} className="cursor" />
  </div>,
  <div key="drag" className="tile__art t3" aria-hidden="true">
    <div className="folder" />
    <div className="folder-tab" />
    <div className="shelf" />
    <Doc />
  </div>,
]

export function HowItWorks() {
  return (
    <section id="how" className="card card--padded" data-snap-section="" data-offset="96" aria-labelledby="how-title">
      <h2 id="how-title" className="h2 reveal">
        Download. Reach. Drag.
      </h2>
      <div className="tiles">
        {steps.map((step, i) => (
          <div key={step.label} className="tile reveal">
            {art[i]}
            <div className="tile__body">
              <p className="tile__label">
                0{i + 1} · {step.label}
              </p>
              <p className="tile__title">{step.title}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
