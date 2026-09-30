"""Compose the README animation from Keyfinder's synthetic AppKit previews."""

import argparse
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont


WIDTH, HEIGHT = 1200, 800
BACKGROUND = "#0d1117"
FOREGROUND = "#f0f4f8"
MUTED = "#99a5b3"
ACCENTS = {0: "#99a5b3", 1: "#54c9b8", 2: "#779de8"}
SCENES = [(1, 3500), (2, 3500), (0, 2000)]


def font(path, size, bold=False):
    result = ImageFont.truetype(str(path), size)
    result.set_variation_by_name("SemiBold" if bold else "Regular")
    return result


def scene(layer, previews, typeface):
    canvas = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    accent = ACCENTS[layer]

    draw.text((44, 41), "KEYFINDER", font=font(typeface, 27, True), fill=FOREGROUND, anchor="lm")
    draw.text((44, 77), "Your layers, in plain sight.", font=font(typeface, 19), fill=MUTED, anchor="lm")

    cursor = 648
    for index, title, width in [(0, "0 · Typing", 144), (1, "1 · Symbols", 160), (2, "2 · Navigation", 184)]:
        selected = index == layer
        draw.rounded_rectangle(
            (cursor, 30, cursor + width, 88), radius=16,
            fill="#1d3036" if selected else "#151b23",
            outline=accent if selected else "#2a333e", width=2,
        )
        draw.text(
            (cursor + width / 2, 59), title, font=font(typeface, 19, selected),
            fill=FOREGROUND if selected else MUTED, anchor="mm",
        )
        cursor += width + 10

    if layer:
        with Image.open(previews / f"layer-{layer}.png") as rendered:
            overlay = rendered.convert("RGBA")
        overlay.thumbnail((1100, 610), Image.Resampling.LANCZOS)
        canvas.paste(overlay, ((WIDTH - overlay.width) // 2, 128), overlay)
    else:
        # This empty stage illustrates hiding; it is not an app window.
        draw.rounded_rectangle((562, 313, 638, 389), radius=23, fill="#1d3036", outline="#34565b", width=2)
        draw.text((600, 351), "0", font=font(typeface, 35, True), fill="#54c9b8", anchor="mm")
        draw.text((600, 445), "Back to typing.", font=font(typeface, 42, True), fill=FOREGROUND, anchor="mm")
        draw.text((600, 495), "Layer 0 hides the overlay.", font=font(typeface, 23), fill=MUTED, anchor="mm")

    draw.ellipse((46, 762, 56, 772), fill=accent)
    state = "Overlay visible" if layer else "Overlay hidden"
    draw.text((70, 767), f"Layer {layer} · {state}", font=font(typeface, 17), fill=MUTED, anchor="lm")
    draw.text((1156, 767), "OFFLINE DEMO", font=font(typeface, 15, True), fill=MUTED, anchor="rm")
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("artifacts/demo.gif"))
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="keyfinder-demo-") as directory:
        previews = Path(directory)
        subprocess.run(
            [str(args.app / "Contents/MacOS/Keyfinder"), "--render-previews", str(previews)],
            check=True,
        )
        frames = [scene(layer, previews, args.font) for layer, _ in SCENES]

    # One palette keeps text, backgrounds, and accents stable between scenes.
    atlas = Image.new("RGB", (WIDTH, HEIGHT * len(frames)))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (0, HEIGHT * index))
    palette = atlas.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        args.output, format="GIF", save_all=True, append_images=frames[1:],
        duration=[duration for _, duration in SCENES], loop=0, disposal=2, optimize=True,
    )
    print(f"Wrote {args.output}: {len(frames)} scenes, 9-second loop, {args.output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
