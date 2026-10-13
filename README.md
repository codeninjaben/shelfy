# Shelfy

Shelfy gives recently downloaded files a small home at the edge of your screen and in the menu bar.
A file finishes downloading → the glass tab peeks out from the screen edge → hover the tab → drag
the file wherever you need it → the shelf tucks itself away.

Native Swift/SwiftUI with AppKit for the floating panel, pointer tracking, drag-and-drop and the
menu bar. Targets macOS 26+ and uses the system Liquid Glass APIs (`glassEffect`, Icon Composer icon).

## Download

Download the [signed and notarized universal Mac app](https://github.com/codeninjaben/shelfy/releases/download/v1.1.0/Shelfy-1.1.0.dmg),
open it, and drag Shelfy into Applications. Requires macOS 26 or later. The
[release](https://github.com/codeninjaben/shelfy/releases/tag/v1.1.0) also has a ZIP of the same app.

## Build and run

Requirements: macOS 26 or later, Xcode 26 or later (developed with Xcode 27 on macOS 27.2).

```bash
open Shelfy.xcodeproj        # then Product ▸ Run (scheme "Shelfy")
```

or from the command line:

```bash
scripts/run.sh             # builds Debug and (re)launches Shelfy
scripts/build.sh Release   # prints the path to the built Shelfy.app
xcodebuild test -project Shelfy.xcodeproj -scheme Shelfy -destination 'platform=macOS'
```

- **Signing:** the project signs automatically with Zazen Technology Group LLC’s Apple
  team `BZB8682VMH`. Use another team by changing `DEVELOPMENT_TEAM` in `project.yml` (or
  in Xcode's Signing & Capabilities). A stable signature matters: macOS ties the Downloads
  permission to it, and ad-hoc builds get asked again after every rebuild.
- **Project file:** `Shelfy.xcodeproj` is generated from `project.yml` with XcodeGen. `scripts/build.sh`
  regenerates it when `xcodegen` is installed; the checked-in project works without it.
- **First launch:** macOS asks *"Shelfy" would like to access files in your Downloads folder*.
  Choose Allow. Shelfy starts with an empty shelf and only collects files that arrive afterwards.
- **Launch at Login** works from any location, but it's best to copy the Release build to
  `/Applications` first so the login item points somewhere permanent.
- **Renamed from Tuck:** the app was called Tuck until the domain question settled it on Shelfy
  (`getshelfy.app`). The bundle ID changed to `com.benbreslow.Shelfy`, so macOS treats it as a
  new app: it asks for Downloads access again, starts with an empty shelf and default settings, and
  a Launch at Login item made by Tuck doesn't carry over. Tuck's old data can be removed with
  `rm -rf ~/Library/Containers/com.benbreslow.Tuck`. The project folder is still `~/dev/tuck`.

## Using Shelfy

| Do this | Result |
| --- | --- |
| Move the pointer to the screen edge near the tab | The tab slides out (with Show Tab ▸ Near Pointer, the default) |
| Move the pointer clearly toward the tab | It sticks out a little further, or slides out if hidden. It never opens by itself |
| Rest the pointer on the edge tab | The shelf grows out of the tab (delay set by Hover Sensitivity) |
| Click the tab | Opens immediately and takes keyboard focus |
| Drag the tab up/down, or the shelf's grab handle | Moves the tab along the edge |
| Drag a thumbnail or the stack out | Drops the real file(s) into Finder, Mail, upload fields… (a copy; the original stays put) |
| Click the "3 Files ›" capsule or the stack | Switches between the stack and a scrollable grid |
| Double-click / Return / ⌘O | Opens the file, then the shelf tucks away |
| Space / ⌘Y | Quick Look |
| Right-click an item | Open, Open With, Quick Look, Show in Finder, Copy, Remove from Shelf, Move to Trash |
| Hover a file ▸ ✕ (top left) / Delete | Removes it from the shelf; the file stays where it is |
| Hover a file ▸ trash can (top right) / ⌘⌫ | Moves the file itself to the Trash; **Put Back** is offered for 6 seconds (also ⌘Z) |
| ✕ in the corner | Clears the shelf; **Undo Clear** is offered for 6 seconds (also ⌘Z) |
| Esc / › button / move the pointer away | Tucks the shelf away |
| Menu bar icon | The same shelf in a popover; right-click for Settings and Quit |
| Right-click the tab | Open Shelf, Clear Shelf, Settings…, Quit Shelfy |

The shelf opened by hover doesn't take keyboard focus; your app keeps it. Clicking inside the
shelf (or opening it by clicking the tab) moves focus to Shelfy, which is when Space, Esc, arrow
keys and the ⌘ shortcuts work. Focus returns to your app when the shelf closes.

**Settings** (menu bar icon ▸ right-click, the tab's menu, or launch Shelfy again): Show Shelfy
(Edge Tab & Menu Bar / Edge Tab Only / Menu Bar Only), edge, position, display, hover
sensitivity, arrival animation, watched folder, launch at login, plus:

- **Show Tab:** *Near Pointer* (default) keeps the tab out of sight until the pointer reaches the
  screen edge within about 100 pt of it. New downloads still make it peek out for a few seconds.
  *Always* keeps the tab on screen.
- **Hide When Shelf Is Empty:** removes the tab from the edge entirely while there's nothing in the
  shelf. It comes back when a download arrives.

## How it works

| Area | Files |
| --- | --- |
| Shared model: references, not copies (bookmark + inode, persisted as JSON) | `Model/FileCollection.swift`, `BasketItem.swift`, `FileLocator.swift` |
| Download detection (FSEvents, settle and partial-file rules) | `Files/DownloadObserver.swift`, `DownloadNaming.swift` |
| Watched folder, sandbox access, privacy prompt off the main thread | `Files/WatchedFolder.swift` |
| Thumbnails (Quick Look, cached, on device) | `Files/ThumbnailProvider.swift` |
| Edge tab and shelf: non-activating panel, hover state machine, glass morph | `Presentation/Edge/*` |
| Menu bar icon and popover | `Presentation/MenuBar/StatusItemController.swift` |
| Shelf content shared by both surfaces, drag source, Quick Look, menus | `Presentation/Basket/*` |
| Coordination (one shelf open at a time), system events | `App/AppModel.swift` |

**Download detection.** New top-level entries in the watched folder become candidates. A candidate
is reported once its size and modification date have been stable for about 0.9 s, it no longer
carries the Finder "busy" date, and no partial sibling (`name.part`, `name.crdownload`,
`name.download`, …) exists. Temporary artifacts (`.crdownload`, `.part`, `.download` bundles,
`.opdownload`, `.partial`, hidden files, `.sb-` atomic-save files, Office lock files) are never shown.
The rename from a temporary name to the final name is what completes Chrome and Firefox downloads.
Renaming or editing a file that was already there doesn't count as a download. When Shelfy
relaunches, it picks up files added while it wasn't running (within 12 hours), using a saved
watermark. On first launch it adds nothing.

**References.** Items follow renames and moves (bookmarks plus inode check), disappear when the
file is deleted or trashed, and are never confused with a new download that reuses the name.
Losing permission marks an item unavailable instead of dropping it. Clear and Remove only touch the
shelf. Move to Trash is the one action that moves a file, and only when you ask: Shelfy has read-write
access to Downloads (and the folder you choose) for that and for Put Back.

**Desktop behavior.** The edge panel is a borderless, non-activating `NSPanel` on every Space.
Collapsed, it covers only the tab plus an 18–28 pt activation strip (set by Hover Sensitivity). While the tab
waits out of sight, it shrinks to an invisible 4 pt strip along the edge beside the tab. Clicks
and hovers are only captured inside those regions.

**Approach.** To notice a pointer heading for the tab, Shelfy also receives mouse-move events through
an AppKit event monitor (no permission needed).
- **What it keeps.** Movement outside a zone near the tab is discarded on arrival, no more than about
  0.1 s of movement is kept, and the monitor runs only while the tab is tucked.
- **What counts.** A move counts as an approach when its heading lands on the tab (the triangle) and
  the pointer isn't braking to stop short of the edge. The tab then sticks out about 3 pt further,
  or slides out if hidden, but the shelf only opens when you rest on the tab. Hover Sensitivity
  sets how far out an approach is recognized.
- **Staying alive.** Global monitors can go quiet after sleep or a screen lock, so Shelfy reinstalls
  them on wake and unlock. It also reinstalls them whenever macOS reports pointer movement the
  monitor never heard; it checks only when the pointer last moved, never where it is.
The panel is resized before the glass surface morphs, so the morph is never clipped. Open
shelves stay inside the screen's visible frame, clear of the menu bar, the Dock (a visible Dock on
the same edge pushes the tab inward) and the corners, where hot corners live. Holds keep the shelf
open during drags, menus, Quick Look, keyboard focus and repositioning, and a 350 ms grace period
prevents flicker. When a full-screen app covers the tab's display, the tab waits out of sight even in
*Always* mode, using the same edge strip, like the Dock.

**Accessibility.** VoiceOver labels and actions on the tab and items, Finder-style keyboard
navigation, Reduce Motion (crossfades, no nudge), Reduce Transparency (opaque surface), light and
dark appearances.

## Verification

What was actually exercised on this Mac (macOS 27.2):

- **62 automated tests, all passing**, run against real files on disk and simulated pointer paths:
  - Chrome-, Firefox-, Safari- and curl-style downloads are each reported once, under the final name.
  - Interrupted Chrome, Firefox and Safari downloads never appear.
  - Several simultaneous downloads; a downloaded folder; relaunch catch-up.
  - Existing, renamed, edited, hidden and temporary files are ignored.
  - Clearing and removing leave the originals byte-for-byte intact; Undo Clear works.
  - Rename, move, delete, trash, name reuse, identical names, permission loss, persistence across relaunch.
  - Edge geometry: both edges, Dock, menu bar, corners, a second display with a negative origin, and the hidden-tab sensor strip.
  - Preferences persist, including the Show Tab and Hide When Empty settings.
  - Approach detection, on recorded-style pointer paths:
    - Straight, diagonal and flick-at-the-edge reaches stick the tab out at least 0.1 s before arrival.
    - Aiming elsewhere, sliding along the edge, slow drift, far-away movement, and braking to stop
      short of the edge (a sidebar-style move) are ignored. That last test fails if braking detection
      is turned off.
    - The tab retracts when the pointer turns back or leaves the zone.
    - The left edge mirrors the right; higher sensitivity reaches farther; the monitor health check works.
- **Real downloads into `~/Downloads`:**
  - Three files via curl (a PDF through a Chrome-style `.crdownload` rename, a small JPEG, and a 14.7 MB JPEG written directly). Each appeared about a second after finishing.
  - A real Chrome download (`10Mb.dat`) in a throwaway profile.
  - A real interrupted Chrome download: a 1.25 GB file killed at 468 MB. It never appeared. The partial file was deleted afterwards.
- **First launch** with 278 existing files in Downloads: the shelf stayed empty.
- **Screenshots, driven by the Debug-only hooks** (`scripts/shelfy-debug.swift`) and checked by eye:
  - The resting tab, with the unseen-arrival dot.
  - The expanded shelf: glass, stack of real Quick Look thumbnails, "3 Files" capsule.
  - The menu bar popover showing the same shelf.
  - The Settings window.
- **Near Pointer mode, checked with window bounds:** after launch the tab peeked (18×256 pt panel), then
  settled into the 4 pt edge strip. A replayed Chrome download made it peek for about 4 s and tuck back.
  Deleting that file removed it from the shelf.
- **Approach tracker, checked in logs:**
  - A build left running across a two-hour screen lock received no pointer events at all afterwards.
  - After the fix, a fresh launch received pointer movement as soon as the mouse moved.
  - The 30 s health check read real values inside the sandbox ("pointer last moved 0.0 s ago").
  - The re-arm path works when triggered through the Debug hook (`shelfy-debug rearm-approach`).
- **Privacy prompt:** found and fixed a hang where the first launch blocked the main thread on the
  Downloads permission dialog. The check now runs in the background.

**Not verified** (needs real pointer and keyboard input, which wasn't available):

- Hover-to-open timing and feel; collapse when the pointer leaves; how easy the hidden tab is to summon from the edge.
- How the approach feels in practice (how early the tab sticks out, how often it guesses wrong), and
  re-arming after a real lock or sleep. That path is wired up and the health check backs it up, but a
  lock wasn't reproduced.
- Dragging out of the shelf into Finder, Mail, TextEdit and a browser upload field.
- Double-click, Space/Esc/arrow keys, the context menu, Quick Look's presentation, the grab handle.
- Grid mode, dark mode, Reduce Motion and Reduce Transparency rendering, and the left edge.
- Multiple displays, full-screen auto-hide with a real full-screen app, Launch at Login.

### Manual test checklist

1. Run Shelfy, then download anything in Safari or Chrome. The tab should peek out, nudge, and show a blue dot.
2. Push the pointer to the edge near the tab; it slides out. Rest on it and the shelf grows out of it. Move away; it should tuck back, and the tab hides again.
   Try Settings ▸ Show Tab ▸ Always and Hide When Shelf Is Empty.
3. Drag the thumbnail into a Finder window. You get a copy, and the shelf tucks away.
4. Download two more files and confirm the stack. Click "3 Files ›" for the grid, then drag one cell into Mail or a browser upload field.
5. Click a thumbnail, then press Space (Quick Look), Esc (closes Quick Look), Esc again (shelf closes).
6. Click ✕ and confirm the files are still in Downloads. Undo Clear restores the shelf.
   Hover a file and click the trash can: the file goes to the Trash, and Put Back (or ⌘Z) returns it to Downloads and the shelf.
7. Cancel a download midway in Safari or Chrome. Nothing should appear.
8. Try the menu bar popover, Settings (left edge, position, display), and Reduce Motion/Transparency in System Settings ▸ Accessibility ▸ Display.

`scripts/simulate-downloads.sh chrome|firefox|safari|direct|multiple|interrupted|cleanup` replays
each browser's on-disk sequence in `~/Downloads`, using files named `shelfy-sim-…`. With the Debug build,
`swift scripts/shelfy-debug.swift expand|grid|popover|settings|collapse` drives the UI for screenshots, and
`trash-sim` / `undo` move the `shelfy-sim-…` files to the Trash and put them back.

## Known limitations

- **Edge clicks.** Shelfy's edge regions are real (transparent) windows. Clicks in the 4 pt strip
  beside a hidden tab, or on the visible tab area, go to Shelfy rather than to what's underneath, such
  as the outermost sliver of a scroll bar.
- **Approach guesses.** A quick move toward something very close to the edge, level with the tab,
  can make the tab stick out for a moment. It never opens the shelf on its own.
- **Drag-out copies.** The original stays in Downloads, so the shelf keeps working. Finder never moves the file.
- **Stalled direct writes.** A file written in place by a tool that stalls for over a second
  (`curl -o` with a dead connection) can look finished. Browsers aren't affected, because they use
  temporary names.
- **Full-screen detection** looks for a window covering the whole display, including the menu bar
  area. Apps that fake full screen with an ordinary maximized window (Roblox, for example) keep the tab visible.
- **Strings** are English only so far; there's no strings catalog yet.
- **Folders chosen in Shelfy 1.0.0** were granted read-only. Move to Trash shows "Couldn’t Move to Trash"
  for files there until you choose the folder again in Settings. Downloads itself needs nothing.

## License

Shelfy is available under the [MIT License](LICENSE).

## Packaged releases

Distribution uses Zazen Technology Group LLC’s Developer ID Application certificate,
team `BZB8682VMH`, and hardened runtime. The download supports both Apple silicon
and Intel Macs running macOS 26 or later.

With the Zazen Apple account signed in to Xcode and its Developer ID certificate
installed, run:

```sh
scripts/release.sh 1.0.0
```

For command-line credentials, create a Keychain profile with `xcrun notarytool store-credentials`
and set `SHELFY_NOTARY_PROFILE=your-profile` when running the script.

The script builds a universal Release archive, submits it to Apple, staples the accepted
notarization ticket, verifies Gatekeeper acceptance, and writes the ZIP, the disk image and
`SHA256SUMS` to `build/releases/1.0.0/`. Upload those three files to the matching GitHub release.
The website’s `site.releaseDownload` should point directly to the published disk image.

`scripts/make-dmg.sh path/to/Shelfy.app` builds just the disk image from an already stapled app.
It uses [dmgbuild](https://github.com/dmgbuild/dmgbuild) (installed into `build/dmg-venv` on
first use) to lay out the "drag into Applications" window drawn in `packaging/dmg/background.html`.
After editing that page, regenerate its images with
`swift scripts/make-dmg-background.swift packaging/dmg/background.html packaging/dmg`.
With `SHELFY_NOTARY_PROFILE` set, the disk image itself is also signed, notarized and stapled;
otherwise it stays unsigned, and macOS checks the stapled app inside when it first opens.

Signing identities and notarization credentials are never committed to this repository.
