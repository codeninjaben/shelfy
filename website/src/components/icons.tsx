import type { SVGProps } from 'react'

type IconProps = SVGProps<SVGSVGElement> & { size?: number }

function Icon({ size = 20, strokeWidth = 2.2, children, ...rest }: IconProps) {
  return (
    <svg
      aria-hidden="true"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...rest}
    >
      {children}
    </svg>
  )
}

export const GitHubIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4" />
    <path d="M9 18c-4.51 2-5-2-7-2" />
  </Icon>
)

export const ArrowDownIcon = (p: IconProps) => (
  <Icon size={18} strokeWidth={2.6} {...p}>
    <path d="M12 4v15" />
    <path d="M5 12l7 7 7-7" />
  </Icon>
)

export const PlusIcon = (p: IconProps) => (
  <Icon size={16} strokeWidth={3.2} {...p}>
    <path d="M12 4v16" />
    <path d="M4 12h16" />
  </Icon>
)

export const LinkIcon = (p: IconProps) => (
  <Icon size={22} strokeWidth={2.4} {...p}>
    <path d="M9 17H7A5 5 0 0 1 7 7h2" />
    <path d="M15 7h2a5 5 0 1 1 0 10h-2" />
    <path d="M8 12h8" />
  </Icon>
)

export const OfflineIcon = (p: IconProps) => (
  <Icon size={22} strokeWidth={2.4} {...p}>
    <path d="M12 20h.01" />
    <path d="M8.5 16.43a5 5 0 0 1 7 0" />
    <path d="M5 12.86a10 10 0 0 1 5.17-2.69" />
    <path d="M19 12.86a10 10 0 0 0-2-1.52" />
    <path d="M2 8.82a15 15 0 0 1 4.18-2.64" />
    <path d="M22 8.82a15 15 0 0 0-11.29-3.76" />
    <path d="M2 2l20 20" />
  </Icon>
)

export const LockIcon = (p: IconProps) => (
  <Icon size={22} strokeWidth={2.4} {...p}>
    <rect x="3" y="11" width="18" height="11" rx="2" />
    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
  </Icon>
)

/** The menu bar's tray glyph, filled like the real status item. */
export const TrayIcon = ({ size = 16, ...p }: IconProps) => (
  <svg aria-hidden="true" width={size + 1} height={size} viewBox="0 0 24 22" fill="currentColor" {...p}>
    <path d="M3 12.5 5.4 3.6A2 2 0 0 1 7.3 2.1h9.4a2 2 0 0 1 1.9 1.5l2.4 8.9v6.4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM5.6 12h3.6l1.3 2.2h3l1.3-2.2h3.6L16.8 4H7.2z" />
  </svg>
)

export const CursorIcon = ({ size = 26, ...p }: IconProps) => (
  <svg aria-hidden="true" width={size} height={(size * 36) / 26} viewBox="0 0 26 36" {...p}>
    <path d="M2 2v27l7-6.5 4.6 10.6 4.6-2-4.5-10.4h9.6z" fill={p.fill ?? "#121316"} stroke="#ffffff" strokeWidth="2" strokeLinejoin="round" />
  </svg>
)
