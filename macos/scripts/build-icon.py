#!/usr/bin/env python3
"""Turns Resources/icon/source.png into Resources/AppIcon.icns.

The drawing comes from an image model as two flat colours, but not quite Vocafy's: the ground
and the teal each sit a few values off. Every pixel is put back on the line between Vocafy's
ground (#ecf0f2) and teal (#39c5bb), keeping how far along that line it was, so the soft edges
survive and the colours match the site's icon exactly.

The picture is then re-centred with a fixed margin and written out square and opaque: macOS
rounds app icons itself, and an icon that arrives pre-rounded gets the system shape laid over
its own.
"""

import pathlib
import subprocess

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "icon" / "source.png"
ICNS = ROOT / "Resources" / "AppIcon.icns"

CANVAS = 1024
GROUND = (0xEC, 0xF0, 0xF2)
INK = (0x39, 0xC5, 0xBB)
# Space left around the drawing, as a share of the side. macOS's rounded corners eat into it.
MARGIN = 0.17


def blend_palette(steps=16):
    """The ground, the ink and the blends between them. Every pixel lies on that line, so a
    palette of those steps keeps the PNGs tiny. A palette chosen by Pillow from the picture
    picked stray colours instead: yellow specks at 16 px and a faint box around the drawing.
    """
    colours = []
    for i in range(steps):
        t = i / (steps - 1)
        colours += [round(g + t * (k - g)) for g, k in zip(GROUND, INK)]
    palette = Image.new("P", (1, 1))
    palette.putpalette(colours + colours[-3:] * (256 - steps))
    return palette


PALETTE = blend_palette()


def snap(image):
    """Recolours every pixel onto the ground-to-ink line."""
    span = [i - g for g, i in zip(GROUND, INK)]
    length = sum(s * s for s in span)

    def amount(pixel):
        t = sum((p - g) * s for p, g, s in zip(pixel, GROUND, span)) / length
        return max(0.0, min(1.0, t))

    out = Image.new("RGB", image.size)
    source = image.load()
    target = out.load()
    for y in range(image.height):
        for x in range(image.width):
            t = amount(source[x, y])
            target[x, y] = tuple(round(g + t * s) for g, s in zip(GROUND, span))
    return out


def recentre(image):
    """Crops to the drawing and places it in the middle with MARGIN around it."""
    mask = image.convert("L").point(lambda v: 255 if v < 200 else 0)
    box = mask.getbbox()
    if box is None:
        raise SystemExit("the source is entirely background")
    drawing = image.crop(box)
    inner = round(CANVAS * (1 - 2 * MARGIN))
    scale = inner / max(drawing.size)
    drawing = drawing.resize((round(drawing.width * scale), round(drawing.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGB", (CANVAS, CANVAS), GROUND)
    canvas.paste(drawing, ((CANVAS - drawing.width) // 2, (CANVAS - drawing.height) // 2))
    return canvas


def main():
    canvas = recentre(snap(Image.open(SOURCE).convert("RGB")))

    iconset = ROOT / "Resources" / "AppIcon.iconset"
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    iconset.mkdir(parents=True)
    for size in (16, 32, 128, 256, 512):
        for name, side in ((f"icon_{size}x{size}.png", size), (f"icon_{size}x{size}@2x.png", size * 2)):
            small = canvas.resize((side, side), Image.LANCZOS)
            # iconutil turns 16 and 32 pt into the old run-length formats, and a palette PNG
            # comes out of that with the bottom rows' blue zeroed - a yellow strip. Those stay
            # full colour; they are small anyway.
            if side > 64:
                small = small.quantize(palette=PALETTE, dither=Image.NONE)
            small.save(iconset / name, optimize=True)

    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)
    subprocess.run(["rm", "-rf", str(iconset)], check=True)
    print(f"built {ICNS.relative_to(ROOT)} ({ICNS.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
