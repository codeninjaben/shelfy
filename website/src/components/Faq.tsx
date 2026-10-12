import { faqs } from '../content'
import { PlusIcon } from './icons'

export function Faq() {
  return (
    <section id="faq" className="card card--padded card--panel" data-snap-section="" data-offset="96" aria-labelledby="faq-title">
      <h2 id="faq-title" className="h2 reveal">
        Good questions.
      </h2>
      <div className="faqs">
        {faqs.map((faq) => (
          <details key={faq.q} className="faq">
            <summary>
              <span>{faq.q}</span>
              <span className="faq__icon" aria-hidden="true">
                <PlusIcon />
              </span>
            </summary>
            <p className="faq__a">
              {faq.a}
              {faq.link && (
                <>
                  {' '}
                  <a href={faq.link.href} target="_blank" rel="noreferrer">
                    {faq.link.label}
                  </a>
                  .
                </>
              )}
            </p>
          </details>
        ))}
      </div>
    </section>
  )
}
