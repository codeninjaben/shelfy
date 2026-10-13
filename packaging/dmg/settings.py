# dmgbuild settings for Shelfy's disk image: the "Grid paper" window drawn in background.html.
# scripts/make-dmg.sh supplies the paths:
#   dmgbuild -s packaging/dmg/settings.py -D app=… -D background=… -D icon=… Shelfy out.dmg
import os.path

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

# LZMA compression needs macOS 10.15 or later; Shelfy itself needs macOS 26.
format = "ULMO"
filesystem = "HFS+"

files = [application]
symlinks = {"Applications": "/Applications"}
hide_extensions = [appname]

# The volume icon is the app's own icon. background@2x.png next to the background makes it Retina.
icon = defines["icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

# The window's content area is exactly the 680 × 420 point background.
window_rect = ((200, 140), (680, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# Icon centers match the card and the dashed drop target in background.html.
icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {
    appname: (180, 190),
    "Applications": (500, 190),
}
