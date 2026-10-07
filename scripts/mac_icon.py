#!/usr/bin/env python3
"""LegacyRay.icns for os x from art/icon-1024.png.

the ios icon is a full-bleed square; an os x icon of 2013 sits inside its
canvas with room for a shadow under it (the grid apple drew for mountain
lion: the tile about 82% of the canvas, lifted off the desk by a soft drop
shadow). every size of the 10.8 icns format is written as png."""
import io
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art" / "icon-1024.png"
OUT = ROOT / "mac" / "Resources" / "LegacyRay.icns"


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


def master():
    src = Image.open(SRC).convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    canvas = 1024
    tile = int(canvas * 0.82)
    radius = int(tile * 0.18)
    art = src.resize((tile, tile), Image.LANCZOS)
    # the ios artwork has its own corners; round them again to the mac radius
    mask = rounded_mask(tile, radius)
    if art.getchannel("A").getextrema()[0] < 255:
        mask = ImageChops.multiply(mask, art.getchannel("A"))
    art.putalpha(mask)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    x = (canvas - tile) // 2
    y = int((canvas - tile) * 0.40)
    # the shadow: soft and a little below, like the dock draws icons on a desk
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    sm = Image.new("L", (canvas, canvas), 0)
    sm.paste(mask, (x, y + int(canvas * 0.022)))
    shadow.putalpha(sm.point(lambda v: int(v * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(canvas * 0.018))
    out = Image.alpha_composite(out, shadow)
    out.paste(art, (x, y), art)
    # a hairline of light along the top edge, the bevel 10.8 icons carry
    rim = Image.new("RGBA", (tile, tile), (255, 255, 255, 0))
    d = ImageDraw.Draw(rim)
    d.rounded_rectangle((1, 1, tile - 2, tile - 2), radius=radius, outline=(255, 255, 255, 46), width=max(2, tile // 180))
    fade = Image.linear_gradient("L").resize((tile, tile)).point(lambda v: 255 - v)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), fade))
    out.alpha_composite(rim, (x, y))
    return out


def png(img, size):
    buf = io.BytesIO()
    img.resize((size, size), Image.LANCZOS).save(buf, "PNG", optimize=True)
    return buf.getvalue()


def main():
    m = master()
    entries = [
        (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
        (b"ic07", 128), (b"ic13", 256), (b"ic08", 256), (b"ic14", 512),
        (b"ic09", 512), (b"ic10", 1024),
    ]
    body = b""
    for code, size in entries:
        data = png(m, size)
        body += code + struct.pack(">I", len(data) + 8) + data
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    m.resize((512, 512), Image.LANCZOS).save(ROOT / "mac" / "Resources" / "icon-preview.png")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    sys.exit(main())
