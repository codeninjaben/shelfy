/**
 * Smooth scrolling with a gentle settle.
 *
 * - Wheel input is smoothed (each frame closes a fixed fraction of the gap to
 *   the target), a little faster than the browser default.
 * - Inside the pinned scenes, if the visitor stops mid-transition, the
 *   page keeps scrolling for them at the speed they were just going, with the
 *   same smoothing, until it rests on a fully revealed scene.
 * - Content cards settle below the nav, with room to scroll through tall content.
 * - The download card and the footer scroll freely.
 * - Arrow keys, Space and Page Up/Down step between scenes; in-page links glide.
 *
 * Scenes opt in with data attributes on their tracks:
 *   data-rest="0.36"        where keyboard steps and nav links land (fraction of the pinned range)
 *   data-hold="0.32 0.45"   the range where the scene is fully revealed; stopping inside it never snaps
 *   data-snap-section      a normal-flow section that settles below the nav
 *   data-snap-end           the element where free scrolling begins
 *   data-offset="90"        nav links land this many px above the element
 */

type Hold = [number, number]

const LERP = 0.12
const NAV_LERP = 0.09
const WHEEL_SPEED = 1.15

export function initScrollEngine(): () => void {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)')
  const pinned = window.matchMedia('(min-width: 900px) and (min-height: 620px)')

  let cur = window.scrollY
  let tgt = cur
  let k = LERP
  let dir = 0
  let auto: { to: number; v: number } | null = null
  let running = false
  let lastT = 0
  let raf = 0
  let lastInput = 0
  let snapTimer = 0
  const samples: { t: number; d: number }[] = []

  const viewH = () => window.innerHeight
  const maxY = () => Math.max(0, document.documentElement.scrollHeight - viewH())
  const clampY = (y: number) => Math.max(0, Math.min(maxY(), y))
  const pos = (el: Element) => el.getBoundingClientRect().top + window.scrollY
  const setY = (y: number) => window.scrollTo(0, y)

  function stopFor(el: HTMLElement): number {
    const rest = el.dataset.rest
    if (rest !== undefined && pinned.matches) return pos(el) + (el.offsetHeight - viewH()) * parseFloat(rest)
    const off = el.dataset.offset
    if (off !== undefined) return pos(el) - parseFloat(off)
    return pos(el)
  }

  function edge(): number {
    const n = document.querySelector<HTMLElement>('[data-snap-end]')
    return n ? Math.round(stopFor(n)) : Infinity
  }

  function stops(): number[] {
    const max = maxY()
    const list = [0]
    document.querySelectorAll<HTMLElement>('[data-rest], [data-snap-section]').forEach((n) => {
      const rests = (n.dataset.rest ?? '').split(',')
      if (rests.length > 1 && pinned.matches) {
        for (const rest of rests) list.push(pos(n) + (n.offsetHeight - viewH()) * parseFloat(rest))
      } else {
        list.push(stopFor(n))
      }
    })
    const end = edge()
    if (end !== Infinity) list.push(end)
    const clean = list.map((v) => Math.round(Math.max(0, Math.min(max, v)))).sort((a, b) => a - b)
    return clean.filter((v, i) => i === 0 || v - clean[i - 1] > 24)
  }

  function holds(): Hold[] {
    const max = maxY()
    const list: Hold[] = [[0, 0]]
    document.querySelectorAll<HTMLElement>('[data-hold]').forEach((n) => {
      const top = pos(n)
      const span = n.offsetHeight - viewH()
      for (const pair of (n.dataset.hold ?? '0 0').split(',')) {
        const [a, b] = pair.trim().split(/\s+/).map(parseFloat)
        list.push([top + span * a, top + span * b])
      }
    })
    document.querySelectorAll<HTMLElement>('[data-snap-section]').forEach((n) => {
      const start = stopFor(n)
      list.push([start, Math.max(start, pos(n) + n.offsetHeight - viewH())])
    })
    const end = edge()
    if (end !== Infinity) list.push([end, end])
    return list
      .map(([a, b]): Hold => [Math.max(0, Math.min(max, a)), Math.max(0, Math.min(max, b))])
      .sort((x, y) => x[0] - y[0])
  }

  function tick(t: number) {
    const ms = lastT ? Math.min(64, t - lastT) : 16.667
    lastT = t
    // Auto-scroll moves the target at a steady scrolling speed, exactly as if the
    // visitor kept scrolling, and the same smoothing follows it.
    if (auto) {
      const left = auto.to - tgt
      const stepPx = (auto.v * ms) / 1000
      if (Math.abs(left) <= stepPx) {
        tgt = auto.to
        auto = null
      } else {
        tgt += (left > 0 ? 1 : -1) * stepPx
      }
    }
    const f = 1 - Math.pow(1 - k, ms / 16.667)
    const d = tgt - cur
    if (!auto && Math.abs(d) < 0.4) {
      cur = tgt
      setY(cur)
      running = false
      return
    }
    cur += d * f
    setY(cur)
    raf = requestAnimationFrame(tick)
  }

  function start() {
    if (running) return
    running = true
    lastT = 0
    raf = requestAnimationFrame(tick)
  }

  function moveTo(y: number, factor: number) {
    cancelSnap()
    auto = null
    const target = clampY(y)
    if (reduced.matches) {
      setY(target)
      cur = tgt = target
      return
    }
    if (!running) cur = window.scrollY
    tgt = target
    k = factor
    start()
  }

  function autoTo(y: number, v: number) {
    cancelSnap()
    const target = clampY(y)
    if (reduced.matches) {
      setY(target)
      cur = tgt = target
      return
    }
    if (!running) {
      cur = window.scrollY
      tgt = cur
    }
    k = LERP
    auto = { to: target, v }
    start()
  }

  function cancelSnap() {
    if (snapTimer) {
      window.clearTimeout(snapTimer)
      snapTimer = 0
    }
  }

  function queueSnap(delay: number) {
    cancelSnap()
    if (reduced.matches || !pinned.matches) return
    snapTimer = window.setTimeout(snap, delay)
  }

  function recentSpeed(): number {
    if (!samples.length) return 0
    const end = samples[samples.length - 1].t
    let sum = 0
    for (const s of samples) if (end - s.t <= 300) sum += s.d
    return sum / 0.3
  }

  function snap() {
    snapTimer = 0
    const idle = performance.now() - lastInput
    if (idle < 150) {
      queueSnap(160 - idle)
      return
    }
    const y = running ? tgt : window.scrollY
    if (y >= edge() - 2) return
    let prev: Hold | null = null
    let next: Hold | null = null
    for (const h of holds()) {
      if (y >= h[0] - 1 && y <= h[1] + 1) return
      if (h[1] < y) prev = h
      if (h[0] > y && !next) next = h
    }
    let target: number
    if (!prev) target = next ? next[0] : y
    else if (!next) target = prev[1]
    else {
      const p = (y - prev[1]) / (next[0] - prev[1])
      const lean = dir > 0 ? 0.4 : dir < 0 ? 0.6 : 0.5
      target = p > lean ? next[0] : prev[1]
    }
    if (Math.abs(target - y) < 2) return
    // Carry on at the speed they were just scrolling (a bit gentler when settling
    // back against their direction), within a natural range.
    const along = (target > y ? 1 : -1) === dir
    const v = Math.max(900, Math.min(2400, recentSpeed() || 1300)) * (along ? 1 : 0.85)
    autoTo(target, v)
  }

  function onWheel(e: WheelEvent) {
    if (e.ctrlKey || reduced.matches) return
    if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return
    const el = e.target instanceof Element ? e.target : null
    if (el?.closest('textarea, select, [data-native-scroll]')) return
    e.preventDefault()
    const unit = e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? viewH() : 1
    const dy = e.deltaY * unit * WHEEL_SPEED
    if (!dy) return
    const now = performance.now()
    dir = dy > 0 ? 1 : -1
    lastInput = now
    samples.push({ t: now, d: Math.abs(dy) })
    while (samples.length && now - samples[0].t > 300) samples.shift()
    if (!running) cur = window.scrollY
    moveTo((running ? tgt : cur) + dy, LERP)
    queueSnap(160)
  }

  function onScroll() {
    if (running) return
    const y = window.scrollY
    if (Math.abs(y - cur) < 1) return
    dir = y > cur ? 1 : -1
    cur = y
    tgt = y
    lastInput = performance.now()
    samples.length = 0
    queueSnap(160)
  }

  function onKey(e: KeyboardEvent) {
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return
    if (!pinned.matches || reduced.matches) return
    const el = e.target instanceof HTMLElement ? e.target : null
    if (el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return
    if (e.key === ' ' && el?.closest('button, summary, [role="button"]')) return
    let d = 0
    if (e.key === 'ArrowDown' || e.key === 'PageDown' || (e.key === ' ' && !e.shiftKey)) d = 1
    else if (e.key === 'ArrowUp' || e.key === 'PageUp' || (e.key === ' ' && e.shiftKey)) d = -1
    if (!d) return
    const y = running ? tgt : window.scrollY
    const end = edge()
    if (y >= end - 2 && !(d < 0 && y <= end + 2)) return
    e.preventDefault()
    const list = stops()
    let target: number | null = null
    if (d > 0) {
      for (const s of list) {
        if (s > y + 6) {
          target = s
          break
        }
      }
    } else {
      for (let i = list.length - 1; i >= 0; i--) {
        if (list[i] < y - 6) {
          target = list[i]
          break
        }
      }
    }
    if (target !== null) {
      dir = d
      autoTo(target, 2000)
    }
  }

  function onClick(e: MouseEvent) {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    const a = e.target instanceof Element ? e.target.closest<HTMLAnchorElement>('a[href^="#"]') : null
    if (!a) return
    const id = a.getAttribute('href')?.slice(1) ?? ''
    const target = id ? document.getElementById(id) : null
    if (!target) return
    e.preventDefault()
    dir = 0
    moveTo(Math.round(stopFor(target)), NAV_LERP)
    if (id !== 'top') {
      if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1')
      target.focus({ preventScroll: true })
    }
    history.replaceState(null, '', id === 'top' ? location.pathname + location.search : `#${id}`)
  }

  function onResize() {
    if (!running) cur = tgt = window.scrollY
  }

  window.addEventListener('wheel', onWheel, { passive: false })
  window.addEventListener('scroll', onScroll, { passive: true })
  window.addEventListener('keydown', onKey)
  window.addEventListener('resize', onResize)
  document.addEventListener('click', onClick)

  // Honour a hash on first load (e.g. benbreslow.dev/#contact).
  const initial = location.hash ? document.getElementById(location.hash.slice(1)) : null
  if (initial) {
    requestAnimationFrame(() => {
      const y = clampY(stopFor(initial))
      setY(y)
      cur = tgt = y
    })
  }

  return () => {
    window.removeEventListener('wheel', onWheel)
    window.removeEventListener('scroll', onScroll)
    window.removeEventListener('keydown', onKey)
    window.removeEventListener('resize', onResize)
    document.removeEventListener('click', onClick)
    cancelAnimationFrame(raf)
    cancelSnap()
  }
}
