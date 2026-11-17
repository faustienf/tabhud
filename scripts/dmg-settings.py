# The DMG's window, for dmgbuild; scripts/setup.sh package runs it:
#   dmgbuild -s scripts/dmg-settings.py -D app=… -D background=… "⌘Tab Wheel v19" CmdTabWheel.dmg
# The window size and the icons' centers match scripts/draw-dmg-background.swift.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "ULFO"  # LZFSE compression
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: it flags the bundle with a Finder attribute that breaks the signature
# check (Finder hides ".app" anyway, unless told to show every extension).
icon =os.path.join(app, "Contents/Resources/AppIcon.icns")  # the mounted disk's icon

background = defines["background"]
window_rect = ((200, 120), (640, 432))  # with the title bar: 400 of content on macOS 26
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {app_name: (160, 190), "Applications": (480, 190)}
