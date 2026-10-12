import { useEffect } from 'react'
import { Customize } from './components/Customize'
import { Faq } from './components/Faq'
import { Footer } from './components/Footer'
import { GetShelfy } from './components/GetShelfy'
import { Hero } from './components/Hero'
import { HowItWorks } from './components/HowItWorks'
import { Native } from './components/Native'
import { Nav } from './components/Nav'
import { OpenSource } from './components/OpenSource'
import { Statement } from './components/Statement'
import { Tour } from './components/Tour'
import { initScrollEngine } from './lib/scrollEngine'

export default function App() {
  useEffect(() => initScrollEngine(), [])

  return (
    <div className="page">
      <a className="skip" href="#tour">
        Skip to the tour
      </a>
      <Nav />
      <main>
        <Hero />
        <Statement />
        <Tour />
        <HowItWorks />
        <Customize />
        <Native />
        <OpenSource />
        <Faq />
        <GetShelfy />
      </main>
      <Footer />
    </div>
  )
}
