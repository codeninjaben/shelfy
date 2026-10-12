import { useEffect, useId, useRef, useState } from 'react'
import { FileStack } from './FileStack'
import { TrayIcon } from './icons'
import '../styles/customize.css'

// A small interactive preview of Shelfy's settings.
type Mode = 'both' | 'edge' | 'menuBar'
type Edge = 'left' | 'right'
type Visibility = 'nearPointer' | 'always'
type Position = 'top' | 'middle' | 'bottom'
type Surface = 'edge' | 'menuBar'
type OpenPreview = { surface: Surface; source: 'hover' | 'press' } | null

type ControlProps<T extends string> = {
  label: string
  value: T
  options: readonly (readonly [T, string])[]
  onChange: (value: T) => void
  off?: boolean
}

function Control<T extends string>({ label, value, options, onChange, off }: ControlProps<T>) {
  const id = useId()
  return (
    <div className={`control${off ? ' is-off' : ''}`} role="group" aria-labelledby={id}>
      <span id={id} className="control__label">
        {label}
      </span>
      <div className="control__options">
        {options.map(([option, text]) => (
          <button
            key={option}
            type="button"
            className="seg"
            aria-pressed={option === value}
            disabled={off}
            onClick={() => onChange(option)}
          >
            {text}
          </button>
        ))}
      </div>
    </div>
  )
}

export function Customize() {
  const [mode, setMode] = useState<Mode>('both')
  const [edge, setEdge] = useState<Edge>('right')
  const [visibility, setVisibility] = useState<Visibility>('nearPointer')
  const [position, setPosition] = useState<Position>('middle')
  const [open, setOpen] = useState<OpenPreview>(null)
  const [edgeRevealed, setEdgeRevealed] = useState(false)
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const previewRef = useRef<HTMLDivElement>(null)
  const previewId = useId()

  function cancelClose() {
    if (closeTimer.current !== null) clearTimeout(closeTimer.current)
    closeTimer.current = null
  }

  function closePreview() {
    cancelClose()
    setOpen(null)
    setEdgeRevealed(false)
  }

  function showOnHover(surface: Surface) {
    cancelClose()
    setOpen((current) => current?.surface === surface ? current : { surface, source: 'hover' })
  }

  function leaveSurface(surface: Surface) {
    cancelClose()
    closeTimer.current = setTimeout(() => {
      setOpen((current) => current?.surface === surface && current.source === 'hover' ? null : current)
    }, 180)
  }

  function toggleSurface(surface: Surface) {
    cancelClose()
    setOpen((current) => current?.surface === surface && current.source === 'press' ? null : { surface, source: 'press' })
  }

  useEffect(() => {
    closePreview()
    return cancelClose
  }, [mode, edge, visibility, position])

  useEffect(() => {
    function dismissOutside(event: PointerEvent) {
      if (event.target instanceof Node && !previewRef.current?.contains(event.target)) closePreview()
    }
    document.addEventListener('pointerdown', dismissOutside)
    return () => document.removeEventListener('pointerdown', dismissOutside)
  }, [])

  const menuBarOnly = mode === 'menuBar'
  const hint = open
    ? 'your downloads, within reach'
    : menuBarOnly
      ? 'try the menu bar icon'
      : visibility === 'always'
        ? 'hover or tap the edge tab'
        : `hover or tap the ${edge} edge`
  const miniClass = [
    'screen mini',
    `mode-${menuBarOnly ? 'menubar' : mode}`,
    `edge-${edge}`,
    visibility === 'always' ? 'vis-always' : 'vis-near',
    `pos-${position}`,
    edgeRevealed || open?.surface === 'edge' ? 'is-edge-revealed' : '',
    open ? `is-${open.surface === 'menuBar' ? 'menu' : 'edge'}-open` : '',
  ].join(' ')

  return (
    <section
      id="customize"
      className="card card--padded customize"
      data-snap-section=""
      data-offset="96"
      aria-labelledby="customize-title"
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          event.preventDefault()
          closePreview()
        }
      }}
    >
      <div className="customize__row">
        <div className="customize__controls">
          <h2 id="customize-title" className="h2 reveal">
            Make it yours.
          </h2>
          <p className="mono-note">a few settings. a shelf that feels like you.</p>
          <div className="controls">
            <Control
              label="show shelfy in"
              value={mode}
              onChange={setMode}
              options={[
                ['both', 'edge + menu bar'],
                ['edge', 'edge'],
                ['menuBar', 'menu bar'],
              ]}
            />
            <Control
              label="edge"
              value={edge}
              onChange={setEdge}
              off={menuBarOnly}
              options={[
                ['left', 'left'],
                ['right', 'right'],
              ]}
            />
            <Control
              label="show tab"
              value={visibility}
              onChange={setVisibility}
              off={menuBarOnly}
              options={[
                ['nearPointer', 'near pointer'],
                ['always', 'always'],
              ]}
            />
            <Control
              label="position"
              value={position}
              onChange={setPosition}
              off={menuBarOnly}
              options={[
                ['top', 'top'],
                ['middle', 'middle'],
                ['bottom', 'bottom'],
              ]}
            />
          </div>
        </div>

        <div className="customize__preview">
          <div
            className={miniClass}
            ref={previewRef}
            role="group"
            aria-label="Interactive Shelfy preview"
            aria-describedby={`${previewId}-instructions`}
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget)) closePreview()
            }}
          >
            <div className="shape m1" aria-hidden="true" />
            <div className="shape m2" aria-hidden="true" />
            <div className="shape m3" aria-hidden="true" />

            <div className="menubar">
              <div className="menubar__menus" aria-hidden="true">
                <span>Finder</span>
                <span>File</span>
                <span>Edit</span>
                <span>View</span>
              </div>
              <div className="menubar__status">
                {mode !== 'edge' && (
                  <button
                    type="button"
                    className="mini-tray"
                    aria-label="Toggle menu bar shelf preview"
                    aria-expanded={open?.surface === 'menuBar'}
                    aria-controls={`${previewId}-menu`}
                    onClick={() => toggleSurface('menuBar')}
                    onPointerEnter={(event) => { if (event.pointerType === 'mouse') showOnHover('menuBar') }}
                    onPointerLeave={() => leaveSurface('menuBar')}
                  >
                    <TrayIcon size={14} />
                  </button>
                )}
                <span aria-hidden="true">Mon 9:41</span>
              </div>
            </div>

            <div
              id={`${previewId}-menu`}
              className="mini-pop"
              role="region"
              aria-label="Menu bar shelf: three example downloads"
              aria-hidden={open?.surface !== 'menuBar'}
              onPointerEnter={cancelClose}
              onPointerLeave={() => leaveSurface('menuBar')}
            >
              <div className="pop-title">Downloads</div>
              <FileStack layout="miniPopover" />
              <span className="count">3 Files</span>
            </div>

            <div
              className="mini-zone"
              onPointerEnter={(event) => {
                if (event.pointerType === 'mouse') { cancelClose(); setEdgeRevealed(true) }
              }}
              onPointerLeave={() => { setEdgeRevealed(false); leaveSurface('edge') }}
            >
              {!menuBarOnly && (
                <button
                  type="button"
                  className="mini-edge-trigger"
                  aria-label={`Toggle ${edge} edge shelf preview`}
                  aria-expanded={open?.surface === 'edge'}
                  aria-controls={`${previewId}-edge`}
                  onFocus={() => setEdgeRevealed(true)}
                  onClick={() => toggleSurface('edge')}
                  onPointerEnter={(event) => { if (event.pointerType === 'mouse') showOnHover('edge') }}
                >
                  <span className="mini-tab" aria-hidden="true" />
                </button>
              )}
              <div
                id={`${previewId}-edge`}
                className="mini-shelf"
                role="region"
                aria-label="Edge shelf: mountains.jpg and two more example downloads"
                aria-hidden={open?.surface !== 'edge'}
              >
                <span className="grabber" />
                <FileStack layout="miniShelf" />
                <span className="file-name">mountains.jpg</span>
              </div>
            </div>

            <span className="mini__hint" aria-live="polite">{hint}</span>
          </div>
          <p id={`${previewId}-instructions`} className="customize__instructions">
            Hover or tap to open. With a keyboard, use Tab and Enter. Escape closes the preview.
          </p>
        </div>
      </div>
    </section>
  )
}
