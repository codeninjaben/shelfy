import type { CSSProperties } from 'react'

type Box = { left: number; top: number; width: number; height: number }

type Layout = {
  size: [number, number]
  radius: number
  docA: Box
  docB: Box
  photo: Box
  shadow: string
  photoShadow: string
  detailed: boolean
}

/** A photo on top of two documents, in the sizes the shelves and popovers use. */
const layouts: Record<'shelf' | 'popover' | 'miniShelf' | 'miniPopover', Layout> = {
  shelf: {
    size: [170, 124],
    radius: 11,
    docA: { left: 10, top: 14, width: 100, height: 108 },
    docB: { left: 60, top: 12, width: 100, height: 108 },
    photo: { left: 22, top: 8, width: 126, height: 96 },
    shadow: '0 6px 16px rgba(20, 30, 70, 0.22)',
    photoShadow: '0 10px 22px rgba(20, 30, 70, 0.3)',
    detailed: true,
  },
  popover: {
    size: [150, 104],
    radius: 10,
    docA: { left: 6, top: 12, width: 86, height: 92 },
    docB: { left: 56, top: 10, width: 86, height: 92 },
    photo: { left: 18, top: 6, width: 110, height: 82 },
    shadow: '0 6px 14px rgba(20, 30, 70, 0.22)',
    photoShadow: '0 8px 18px rgba(20, 30, 70, 0.3)',
    detailed: true,
  },
  miniShelf: {
    size: [104, 76],
    radius: 8,
    docA: { left: 4, top: 10, width: 60, height: 64 },
    docB: { left: 40, top: 8, width: 60, height: 64 },
    photo: { left: 14, top: 4, width: 76, height: 58 },
    shadow: '0 4px 10px rgba(20, 30, 70, 0.22)',
    photoShadow: '0 6px 12px rgba(20, 30, 70, 0.3)',
    detailed: false,
  },
  miniPopover: {
    size: [104, 72],
    radius: 8,
    docA: { left: 4, top: 10, width: 60, height: 62 },
    docB: { left: 40, top: 8, width: 60, height: 62 },
    photo: { left: 14, top: 4, width: 76, height: 56 },
    shadow: '0 4px 10px rgba(20, 30, 70, 0.22)',
    photoShadow: '0 6px 12px rgba(20, 30, 70, 0.3)',
    detailed: false,
  },
}

export function FileStack({ layout }: { layout: keyof typeof layouts }) {
  const l = layouts[layout]
  const box = (b: Box, shadow: string): CSSProperties => ({ ...b, borderRadius: l.radius, boxShadow: shadow })
  return (
    <div className="stack" style={{ width: l.size[0], height: l.size[1] }}>
      <div className="stack__doc stack__doc--a" style={box(l.docA, l.shadow)} />
      <div className="stack__doc stack__doc--b" style={box(l.docB, l.shadow)} />
      <div className="stack__photo" style={box(l.photo, l.photoShadow)}>
        <div className="stack__peak" />
        {l.detailed && <div className="stack__peak stack__peak--near" />}
      </div>
    </div>
  )
}
