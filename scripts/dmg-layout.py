#!/usr/bin/env python3
"""Write the Finder window layout for the Keyfinder disk image.

Finder normally records a disk image's window layout in .DS_Store while the
volume is mounted. This writes the same records directly so the image can be
built in the Nix sandbox: the window opens with the app on the left, an arrow,
and the Applications shortcut on the right.

Usage: dmg-layout.py CONTENTS_DIRECTORY VOLUME_NAME
"""

import datetime
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import ALIAS_FIXED_DISK, ALIAS_KIND_FILE, Alias, TargetInfo, VolumeInfo
from PIL import Image, ImageDraw

# Finder measures the window origin from the bottom-left of the main display.
# This places the window near the upper middle of common laptop displays.
WINDOW_ORIGIN = (440, 420)
WINDOW_SIZE = (600, 360)  # Finder content area, in points
ICON_SIZE = 128
APP_CENTER = (160, 170)
APPLICATIONS_CENTER = (440, 170)

# Finder draws windows with a background picture in Light mode, so the
# picture uses Keyfinder's light palette and Finder's black labels stay legible.
PARCHMENT = (0xF4, 0xF3, 0xEE)
ORANGE = (0xF7, 0x7F, 0x00)

BACKGROUND_FOLDER = ".background"
BACKGROUND_NAME = "background.tiff"


def render_background(scale):
    # Draw oversized and downsample for smooth edges; Pillow does not
    # antialias polygons. The result depends only on these constants.
    supersample = 4
    factor = scale * supersample
    width, height = WINDOW_SIZE
    image = Image.new("RGB", (width * factor, height * factor), PARCHMENT)
    draw = ImageDraw.Draw(image)
    y = APP_CENTER[1]
    start, tip = 256, 344
    head_length, head_width, shaft_width = 26, 40, 8
    draw.line([(start * factor, y * factor), ((tip - head_length + 2) * factor, y * factor)],
              fill=ORANGE, width=shaft_width * factor)
    radius = shaft_width * factor // 2
    draw.ellipse([start * factor - radius, y * factor - radius, start * factor + radius, y * factor + radius], fill=ORANGE)
    draw.polygon([((tip - head_length) * factor, (y - head_width / 2) * factor),
                  (tip * factor, y * factor),
                  ((tip - head_length) * factor, (y + head_width / 2) * factor)], fill=ORANGE)
    return image.resize((width * scale, height * scale), Image.Resampling.LANCZOS)


def write_background(path):
    # One TIFF with 1x and 2x representations, as `tiffutil -cathidpicheck`
    # makes, so Finder draws it sharply on both kinds of displays.
    standard, retina = render_background(1), render_background(2)
    retina.encoderinfo = {"dpi": (144, 144), "compression": "tiff_adobe_deflate"}
    standard.save(path, save_all=True, append_images=[retina], dpi=(72, 72), compression="tiff_adobe_deflate")


def background_alias(volume_name):
    # Finder stores the background as an alias, normally recorded from the
    # mounted volume. These are the values it records for this image: xorriso's
    # fixed dates, and catalog IDs 17 and 18 because .DS_Store (16) and
    # .background sort before the app. If they ever drift, Finder falls back
    # to the volume name and path.
    epoch = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
    folder_id, file_id = 17, 18
    volume = VolumeInfo(volume_name, epoch, b"H+", ALIAS_FIXED_DISK, 0, b"\0\0", posix_path=f"/Volumes/{volume_name}")
    target = TargetInfo(ALIAS_KIND_FILE, BACKGROUND_NAME, folder_id, file_id, epoch, b"\0\0\0\0", b"\0\0\0\0",
                        folder_name=BACKGROUND_FOLDER, cnid_path=[folder_id],
                        carbon_path=f"{volume_name}:{BACKGROUND_FOLDER}:\0{BACKGROUND_NAME}",
                        posix_path=f"/{BACKGROUND_FOLDER}/{BACKGROUND_NAME}")
    return Alias(volume=volume, target=target).to_bytes()


def write_layout(contents, volume_name):
    folder = contents / BACKGROUND_FOLDER
    folder.mkdir()
    write_background(folder / BACKGROUND_NAME)
    (x, y), (width, height) = WINDOW_ORIGIN, WINDOW_SIZE
    with DSStore.open(str(contents / ".DS_Store"), "w+") as store:
        store["."]["bwsp"] = {
            "WindowBounds": f"{{{{{x}, {y}}}, {{{width}, {height}}}}}",
            "ShowToolbar": False,
            "ShowSidebar": False,
            "ContainerShowSidebar": False,
            "ShowStatusBar": False,
            "ShowPathbar": False,
            "ShowTabView": False,
            "PreviewPaneVisibility": False,
            "SidebarWidth": 0,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 2,
            "backgroundImageAlias": background_alias(volume_name),
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
            "arrangeBy": "none",
            "iconSize": float(ICON_SIZE),
            "textSize": 13.0,
            "labelOnBottom": True,
            "showIconPreview": True,
            "showItemInfo": False,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
        }
        store["."]["vstl"] = ("type", b"icnv")
        store["."]["vSrn"] = ("long", 1)
        store["Keyfinder.app"]["Iloc"] = APP_CENTER
        store["Applications"]["Iloc"] = APPLICATIONS_CENTER


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    write_layout(Path(sys.argv[1]), sys.argv[2])
