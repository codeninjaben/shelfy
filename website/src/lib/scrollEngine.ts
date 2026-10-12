/** Keep native scrolling and keyboard behavior; enhance only in-page navigation. */
export function initScrollEngine(): () => void {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)')
  const pinned = window.matchMedia('(min-width: 1100px) and (min-height: 700px) and (prefers-reduced-motion: no-preference)')
  const canAnimate = () => pinned.matches && CSS.supports('animation-timeline: view()')
  let initialFrame = 0

  function position(target: HTMLElement) {
    const top = target.getBoundingClientRect().top + window.scrollY
    if (target.dataset.rest && canAnimate()) {
      return top + (target.offsetHeight - window.innerHeight) * parseFloat(target.dataset.rest)
    }
    return top - 96
  }

  function onClick(event: MouseEvent) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const link = event.target instanceof Element ? event.target.closest<HTMLAnchorElement>('a[href^="#"]') : null
    const id = link?.getAttribute('href')?.slice(1)
    const target = id ? document.getElementById(id) : null
    if (!target) return
    event.preventDefault()
    window.scrollTo({ top: id === 'top' ? 0 : position(target), behavior: reduced.matches ? 'instant' : 'smooth' })
    if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1')
    target.focus({ preventScroll: true })
    history.pushState(null, '', id === 'top' ? location.pathname + location.search : `#${id}`)
  }

  const initial = location.hash ? document.getElementById(location.hash.slice(1)) : null
  if (initial) initialFrame = requestAnimationFrame(() => window.scrollTo(0, position(initial)))
  document.addEventListener('click', onClick)
  return () => {
    document.removeEventListener('click', onClick)
    cancelAnimationFrame(initialFrame)
  }
}
