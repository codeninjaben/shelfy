import { chips } from '../content'

export function Native() {
  return (
    <section className="card card--padded native" data-snap-section="" data-offset="96" aria-labelledby="native-title">
      <h2 id="native-title" className="h2 reveal">
        Native, down to the glass.
      </h2>
      <ul className="chips reveal">
        {chips.map((chip) => (
          <li key={chip}>{chip}</li>
        ))}
      </ul>
    </section>
  )
}
