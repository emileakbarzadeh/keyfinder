"""Compose the README animation from Keyfinder's synthetic AppKit previews."""

import argparse
from io import BytesIO
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageCms, ImageColor, ImageDraw, ImageFont


WIDTH, HEIGHT = 1200, 800
ORANGE = "#f77f00"
RED = "#d62828"
INK = "#111315"
PARCHMENT = "#f4f3ee"
PALETTES = {
    "dark": dict(background=INK, foreground=PARCHMENT, surface="#1c1f22", muted="#b3b8be", border="#454a50"),
    "light": dict(background=PARCHMENT, foreground="#202326", surface="#ffffff", muted="#50565b", border="#cecfca"),
}
SCENES = [(1, 3500), (2, 3500), (0, 2000)]


def font(path, size, bold=False):
    result = ImageFont.truetype(str(path), size)
    result.set_variation_by_name("SemiBold" if bold else "Regular")
    return result


def indexed_frame(frame, palette, reserved):
    indexed = frame.quantize(palette=palette, dither=Image.Dither.NONE)
    # Pillow's palette lookup groups nearby RGB values; preserve exact flat fills.
    for index, color in enumerate(reserved, start=256 - len(reserved)):
        r, g, b = ImageChops.difference(frame, Image.new("RGB", frame.size, color)).split()
        mask = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda value: 255 if value == 0 else 0)
        indexed.paste(index, mask=mask)
    return indexed


def scene(layer, previews, typeface, appearance):
    colors = PALETTES[appearance]
    canvas = Image.new("RGB", (WIDTH, HEIGHT), colors["background"])
    draw = ImageDraw.Draw(canvas)
    accent = {0: colors["foreground"], 1: ORANGE, 2: RED}[layer]

    draw.text((44, 41), "KEYFINDER", font=font(typeface, 27, True), fill=colors["foreground"], anchor="lm")
    draw.text((44, 77), "Keyboard layer overlay", font=font(typeface, 19), fill=colors["muted"], anchor="lm")

    cursor = 648
    for index, title, width in [(0, "0 · Typing", 144), (1, "1 · Symbols", 160), (2, "2 · Navigation", 184)]:
        selected = index == layer
        draw.rounded_rectangle(
            (cursor, 30, cursor + width, 88), radius=16,
            fill=accent if selected else colors["surface"],
            outline=accent if selected else colors["border"], width=2,
        )
        draw.text(
            (cursor + width / 2, 59), title, font=font(typeface, 19, selected),
            fill=(colors["background"] if layer == 0 else PARCHMENT if layer == 2 else INK) if selected else colors["muted"], anchor="mm",
        )
        cursor += width + 10

    if layer:
        suffix = "-light" if appearance == "light" else ""
        with Image.open(previews / f"layer-{layer}{suffix}.png") as rendered:
            # AppKit captures can use a display profile; GIF has no color profile.
            profile = rendered.info.get("icc_profile")
            overlay = ImageCms.profileToProfile(
                rendered, ImageCms.ImageCmsProfile(BytesIO(profile)), ImageCms.createProfile("sRGB"), outputMode="RGBA",
            ) if profile else rendered.convert("RGBA")
        overlay.thumbnail((1100, 610), Image.Resampling.LANCZOS)
        canvas.paste(overlay, ((WIDTH - overlay.width) // 2, 128), overlay)
    else:
        # This empty stage illustrates hiding; it is not an app window.
        draw.rounded_rectangle((562, 313, 638, 389), radius=23, fill=ORANGE)
        draw.text((600, 351), "0", font=font(typeface, 35, True), fill=INK, anchor="mm")
        draw.text((600, 445), "Typing layer", font=font(typeface, 42, True), fill=colors["foreground"], anchor="mm")
        draw.text((600, 495), "Layer 0 hides the overlay.", font=font(typeface, 23), fill=colors["muted"], anchor="mm")

    draw.ellipse((46, 762, 56, 772), fill=accent)
    state = "Overlay visible" if layer else "Overlay hidden"
    draw.text((70, 767), f"Layer {layer} · {state}", font=font(typeface, 17), fill=colors["muted"], anchor="lm")
    draw.text((1156, 767), "OFFLINE DEMO", font=font(typeface, 15, True), fill=colors["muted"], anchor="rm")
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("artifacts/demo.gif"))
    parser.add_argument("--appearance", choices=PALETTES, default="dark")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="keyfinder-demo-") as directory:
        previews = Path(directory)
        subprocess.run(
            [str(args.app / "Contents/MacOS/Keyfinder"), "--render-previews", str(previews)],
            check=True,
        )
        frames = [scene(layer, previews, args.font, args.appearance) for layer, _ in SCENES]

    # One palette keeps text, backgrounds, and accents stable between scenes.
    atlas = Image.new("RGB", (WIDTH, HEIGHT * len(frames)))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (0, HEIGHT * index))
    reserved = [PALETTES[args.appearance]["background"], PALETTES[args.appearance]["foreground"], ORANGE, RED, INK, PARCHMENT]
    color_count = 256 - len(reserved)
    palette = atlas.quantize(colors=color_count, method=Image.Quantize.MEDIANCUT)
    # Reserve flat fills so quantization does not shift them between scenes.
    flat_colors = [channel for color in reserved for channel in ImageColor.getrgb(color)]
    palette.putpalette(palette.getpalette()[:color_count * 3] + flat_colors)
    frames = [indexed_frame(frame, palette, reserved) for frame in frames]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        args.output, format="GIF", save_all=True, append_images=frames[1:],
        duration=[duration for _, duration in SCENES], loop=0, disposal=2, optimize=True,
    )
    print(f"Wrote {args.output}: {len(frames)} scenes, 9-second loop, {args.output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
