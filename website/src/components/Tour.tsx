import { useEffect, useRef, useState } from 'react'
import { FileStack } from './FileStack'
import { CursorIcon, TrayIcon } from './icons'

const scenes = [
  {
    title: 'Lives at the edge of your screen.',
    text: 'Head for the edge and the tab slides out. Rest on it and the shelf opens.',
  },
  {
    title: 'Or up in your menu bar.',
    text: 'The same shelf, one click away. Open one and the other steps aside.',
  },
  {
    title: 'Made of Liquid Glass.',
    text: 'It bends and blurs whatever sits behind it, just like the rest of macOS.',
  },
]

const pinnedQuery = '(min-width: 1100px) and (min-height: 700px) and (prefers-reduced-motion: no-preference)'
const rests = [0.25, 0.52, 0.9]

export function Tour() {
  const section = useRef<HTMLElement>(null)
  const [active, setActive] = useState(0)
  const [pinned, setPinned] = useState(false)

  useEffect(() => {
    const media = window.matchMedia(pinnedQuery)
    let frame = 0
    const update = () => {
      const enabled = media.matches && CSS.supports('animation-timeline: view()')
      setPinned(enabled)
      if (!enabled || !section.current) return
      const rect = section.current.getBoundingClientRect()
      const progress = Math.max(0, -rect.top) / Math.max(1, rect.height - window.innerHeight)
      setActive(progress < 0.34 ? 0 : progress < 0.66 ? 1 : 2)
    }
    const onScroll = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(update)
    }
    update()
    window.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('resize', onScroll)
    media.addEventListener('change', update)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', onScroll)
      window.removeEventListener('resize', onScroll)
      media.removeEventListener('change', update)
    }
  }, [])

  function selectScene(index: number) {
    if (pinned && section.current) {
      const element = section.current
      const top = element.getBoundingClientRect().top + window.scrollY
      window.scrollTo({ top: top + (element.offsetHeight - window.innerHeight) * rests[index], behavior: 'smooth' })
    } else {
      setActive(index)
    }
  }

  return (
    <section
      ref={section}
      id="tour"
      data-scene={active}
      data-pinned={pinned}
      className="card card--panel tour"
      data-rest="0.25, 0.52, 0.9"
      data-hold="0.235 0.265, 0.46 0.57, 0.8 1"
      aria-label="Tour"
    >
      <div className="tour__stage">
        <div className="tour__text">
          <div className="tour__steps" role="group" aria-label="Explore Shelfy">
            {['01 edge', '02 menu bar', '03 glass'].map((label, index) => (
              <button key={label} type="button" className="tour__step" aria-pressed={active === index}
                aria-controls="tour-scene" onClick={() => selectScene(index)}>{label}</button>
            ))}
          </div>
          <div id="tour-scene" className="tour__copy">
            <div className="tour__scene" key={active}>
              <h2>{scenes[active].title}</h2>
              <p>{scenes[active].text}</p>
            </div>
          </div>
          <p className="tour__instruction">{pinned ? 'scroll to explore, or choose a scene ↑' : 'choose a scene to take a look ↑'}</p>
        </div>

        <div className="tour__visual" aria-hidden="true">
          <div className="screen tour__screen">
            <div className="tour__shapes sc sc-shapes">
              <div className="shape s1" />
              <div className="shape s2" />
              <div className="shape s3" />
              <div className="shape s4" />
              <div className="shape s5" />
            </div>

            <div className="menubar">
              <div className="menubar__menus">
                <span>Finder</span>
                <span>File</span>
                <span>Edit</span>
                <span>View</span>
              </div>
              <div className="menubar__status">
                <span className="menubar__tray sc sc-tray">
                  <TrayIcon size={15} />
                </span>
                <span>Mon 9:41</span>
              </div>
            </div>

            <div className="tour__tab sc sc-tab" />

            <div className="tour__shelf sc sc-shelf">
              <span className="grabber" />
              <FileStack layout="shelf" />
              <div className="file-name">mountains.jpg</div>
              <span className="count">3 Files</span>
            </div>

            <div className="tour__pop sc sc-pop">
              <div className="pop-title">Downloads</div>
              <FileStack layout="popover" />
              <span className="count">3 Files</span>
            </div>

            <CursorIcon className="tour__cursor sc sc-cursor" />
          </div>
        </div>
      </div>
    </section>
  )
}
