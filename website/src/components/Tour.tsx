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

export function Tour() {
  return (
    <section
      id="tour"
      className="card card--panel tour"
      data-rest="0.25, 0.52, 0.9"
      data-hold="0.24 0.26, 0.46 0.57, 0.8 1"
      aria-label="Tour"
    >
      <div className="tour__stage">
        <div className="tour__text">
          <div className="tour__steps" aria-hidden="true">
            <span className="tour__step sc sc-step1">01 edge</span>
            <span className="tour__step sc sc-step2">02 menu bar</span>
            <span className="tour__step sc sc-step3">03 glass</span>
          </div>
          <div className="tour__copy">
            {scenes.map((scene, index) => (
              <div key={scene.title} className={`tour__scene sc sc-h${index + 1}`}>
                <h2>{scene.title}</h2>
                <p>{scene.text}</p>
              </div>
            ))}
          </div>
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

            <CursorIcon fill="#111111" className="tour__cursor sc sc-cursor" />
          </div>
        </div>
      </div>
    </section>
  )
}
