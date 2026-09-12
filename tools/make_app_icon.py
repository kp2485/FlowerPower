#!/usr/bin/env python3
"""Renders FlowerPower's app icon: a honey comb with a pale flower on it.

Why a script rather than a drawing
----------------------------------
The icon has to exist for the app to build, and nobody with a drawing program
has been near this repository. A script is the version of an icon that can be
reviewed in a diff, re-rendered at any size, and adjusted by changing a number
instead of by finding the original file. It is not a substitute for a designer;
it is a substitute for the empty `AppIcon.appiconset` that was there before.

Pure standard library. Pillow and numpy are not installed on the machine this
was written on, and adding either for one PNG would be a poor trade, so the
PNG is written by hand: `zlib` for the compression, `struct` for the chunk
headers. There is no alpha channel, because an iOS app icon must not have one.

How it draws
------------
Every shape is a signed distance function — how far a point is from the shape's
edge, negative inside — and pixels are filled by how much of them the shape
covers, `0.5 - d` clamped to 0...1. That is one line of anti-aliasing and it
beats supersampling here: a 1024 canvas is a million pixels in Python, and
rendering three times that to average it down would triple a job that is
already the slowest part of the script.

What it draws, and why it is this and not something prettier
------------------------------------------------------------
It has to be legible at 60 points, which is a sixteenth of the canvas. That
rules out thin lines, small detail, and anything with more than a couple of
tones. So: seven large comb cells in honey gold over a dark wax grout, and one
pale six-petalled flower over the middle of them, outlined so the pale shape
separates from the gold at any size. Six petals rather than five because it
echoes the hexagons. No text — Apple's guidance is explicit, and a name at
60 points is unreadable anyway.

Run it from the repository root:

    python tools/make_app_icon.py

and it writes `FlowerPower/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
plus a 60-pixel `--preview` copy if asked, which is the only honest way to
check the legibility claim above.
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import sys
import zlib

# ---------------------------------------------------------------------------
# Palette
#
# The honey golds are `Theme.honey`, `Theme.nectar` and `Theme.pollen` from
# `FlowerPower/Views/Theme.swift`, and the pale flower is `Theme.wax`. Keeping
# the icon in the app's own palette is the whole reason those constants are in
# one file. The grout is a darkened propolis brown, which exists here only
# because the comb needs something to be drawn against.

WAX_GROUT_TOP = (128, 79, 24)
WAX_GROUT_BOTTOM = (104, 62, 18)

CELL_TOP = (250, 205, 80)        # Theme.nectar, lifted
CELL_BOTTOM = (224, 150, 30)     # Theme.pollen, deepened

PETAL = (250, 240, 212)          # Theme.wax, lightened to hold its own on gold
PETAL_EDGE = (150, 94, 28)
FLOWER_HEART = (232, 148, 34)    # Theme.honey, a shade deeper than the cells

# ---------------------------------------------------------------------------
# Geometry, as fractions of the canvas so the layout is resolution-independent.

CELL_APOTHEM = 0.1807            # centre of a cell to the middle of an edge
CELL_GAP = 0.0107                # half the width of the grout between cells

PETAL_ORBIT = 0.1660             # centre of the flower to the centre of a petal
PETAL_RADIUS = 0.1020            # a sixth of the orbit again, so petals scallop
HEART_RADIUS = 0.0930            # rather than merging into a disc
FLOWER_EDGE = 0.0098


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(colour_a, colour_b, t: float):
    return tuple(lerp(colour_a[i], colour_b[i], t) for i in range(3))


def coverage(distance: float) -> float:
    """How much of a pixel a shape whose edge is `distance` away covers."""
    return min(1.0, max(0.0, 0.5 - distance))


def hexagon_distance(x: float, y: float, apothem: float) -> float:
    """Signed distance to a flat-topped regular hexagon centred on the origin.

    Flat-topped — horizontal edges at y = +/- apothem, vertices left and
    right — because that is the orientation comb is built in and the one
    everybody draws.

    This is Inigo Quilez's formulation, which folds the plane into one
    sixth-sector with two reflections and then measures against a single edge.
    Written out rather than derived because getting it wrong is a shape that
    looks nearly right, which is the worst kind of wrong to debug.
    """
    kx, ky, kz = -0.8660254037844386, 0.5, 0.5773502691896258
    x, y = abs(x), abs(y)
    fold = 2.0 * min(kx * x + ky * y, 0.0)
    x -= fold * kx
    y -= fold * ky
    x -= min(max(x, -kz * apothem), kz * apothem)
    y -= apothem
    return math.hypot(x, y) * (1.0 if y > 0 else -1.0)


def circle_distance(x: float, y: float, radius: float) -> float:
    return math.hypot(x, y) - radius


def cell_centres(apothem: float, size: float):
    """Every cell of the lattice that touches the canvas, centred on the middle.

    For a flat-topped hexagon of the given apothem, neighbours sit two apothems
    away: directly above and below, and at the four diagonals. Walking that
    lattice out past the edges rather than stopping at a tidy ring of seven is
    what gives the corners comb instead of bare grout — the cells there are cut
    off by the frame, which is how a piece of comb should look.
    """
    circumradius = 2.0 * apothem / math.sqrt(3.0)
    column_step = 1.5 * circumradius
    reach_x = size / 2.0 + circumradius
    reach_y = size / 2.0 + apothem

    centres = []
    columns = int(reach_x / column_step) + 1
    rows = int(reach_y / (2.0 * apothem)) + 1
    for column in range(-columns, columns + 1):
        x = column * column_step
        if abs(x) > reach_x:
            continue
        # Odd columns are offset by one apothem, which is what makes the
        # lattice interlock instead of being a grid of hexagons.
        offset = apothem if column % 2 else 0.0
        for row in range(-rows - 1, rows + 2):
            y = row * 2.0 * apothem + offset
            if abs(y) > reach_y:
                continue
            centres.append((x, y))
    return centres


def petal_centres(orbit: float):
    """Six petals, starting at twelve o'clock."""
    return [
        (orbit * math.sin(i * math.pi / 3.0), orbit * math.cos(i * math.pi / 3.0))
        for i in range(6)
    ]


def render(size: int) -> bytearray:
    """Draws the icon and returns raw RGB rows, top to bottom."""
    apothem = CELL_APOTHEM * size
    gap = CELL_GAP * size
    orbit = PETAL_ORBIT * size
    petal_radius = PETAL_RADIUS * size
    heart_radius = HEART_RADIUS * size
    edge = FLOWER_EDGE * size

    circumradius = 2.0 * apothem / math.sqrt(3.0)
    column_step = 1.5 * circumradius

    # The lattice is indexed by column so a pixel only ever measures itself
    # against the two or three cells that could possibly contain it. Taking a
    # minimum over all of them instead is thirty times the work for the same
    # picture, and at a million pixels that is the difference between seconds
    # and minutes.
    lattice: dict[int, list[float]] = {}
    for cell_x, cell_y in cell_centres(apothem, float(size)):
        lattice.setdefault(int(round(cell_x / column_step)), []).append(cell_y)

    petals = petal_centres(orbit)
    centre = size / 2.0

    pixels = bytearray(size * size * 3)
    index = 0

    for row in range(size):
        y = row + 0.5 - centre
        # The gradients run down the whole canvas rather than per cell, so the
        # comb reads as one lit surface rather than a heap of tiles.
        down = (row + 0.5) / size
        grout = mix(WAX_GROUT_TOP, WAX_GROUT_BOTTOM, down)
        cell = mix(CELL_TOP, CELL_BOTTOM, down)

        # Which cells this row of pixels can touch at all.
        in_row = {
            column: [cy for cy in ys if abs(y - cy) <= apothem + 1.0]
            for column, ys in lattice.items()
        }

        for column in range(size):
            x = column + 0.5 - centre

            colour = grout

            # The comb. Each cell is inset by the gap, so what is left between
            # them is the grout showing through.
            here = int(round(x / column_step))
            nearest = None
            for neighbour in (here - 1, here, here + 1):
                cell_x = neighbour * column_step
                for cell_y in in_row.get(neighbour, ()):
                    distance = hexagon_distance(x - cell_x, y - cell_y, apothem - gap)
                    if nearest is None or distance < nearest:
                        nearest = distance
            if nearest is not None and nearest < 0.5:
                colour = mix(colour, cell, coverage(nearest))

            # The flower: the union of six petals and a heart, which is a
            # minimum over their distances.
            flower = circle_distance(x, y, heart_radius)
            for px, py in petals:
                d = circle_distance(x - px, y - py, petal_radius)
                if d < flower:
                    flower = d

            # Outlined first and filled over, which is cheaper than measuring
            # a band and is exactly as accurate.
            if flower < edge + 0.5:
                colour = mix(colour, PETAL_EDGE, coverage(flower - edge))
            if flower < 0.5:
                colour = mix(colour, PETAL, coverage(flower))
                # The heart sits on top of the petals, so it is drawn after
                # them rather than being part of the same union.
                heart = circle_distance(x, y, heart_radius)
                if heart < 0.5:
                    colour = mix(colour, FLOWER_HEART, coverage(heart))

            pixels[index] = int(colour[0] + 0.5)
            pixels[index + 1] = int(colour[1] + 0.5)
            pixels[index + 2] = int(colour[2] + 0.5)
            index += 3

    return pixels


def write_png(path: str, size: int, pixels: bytearray) -> None:
    """Writes 8-bit RGB with no alpha, which is what an iOS icon must be."""

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = size * 3
    for row in range(size):
        raw.append(0)  # filter type: none. The compressor does well enough.
        raw += pixels[row * stride:(row + 1) * stride]

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(chunk(b"IEND", b""))


def downsample(size: int, pixels: bytearray, to: int) -> bytearray:
    """Box-averages down to `to` pixels, for the legibility preview.

    Only ever used to look at the icon small. The real sizes are generated by
    Xcode from the 1024 original, which is the single-size convention every
    app icon has used since Xcode 14.
    """
    step = size / to
    out = bytearray(to * to * 3)
    index = 0
    for row in range(to):
        y0, y1 = int(row * step), max(int(row * step) + 1, int((row + 1) * step))
        for column in range(to):
            x0, x1 = int(column * step), max(int(column * step) + 1, int((column + 1) * step))
            totals = [0, 0, 0]
            count = 0
            for y in range(y0, y1):
                base = (y * size + x0) * 3
                for _ in range(x1 - x0):
                    totals[0] += pixels[base]
                    totals[1] += pixels[base + 1]
                    totals[2] += pixels[base + 2]
                    base += 3
                    count += 1
            for channel in range(3):
                out[index + channel] = totals[channel] // count
            index += 3
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Render FlowerPower's app icon.")
    parser.add_argument(
        "--out",
        default=os.path.join(
            "FlowerPower", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"
        ),
        help="where to write the 1024 icon",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument(
        "--preview",
        type=int,
        default=0,
        help="also write a downsampled copy this many pixels across, "
        "to check it is still legible small",
    )
    parser.add_argument(
        "--also",
        action="append",
        default=[],
        help="another path to write the same icon to; repeatable, for the "
        "watch's own icon set",
    )
    arguments = parser.parse_args(argv)

    pixels = render(arguments.size)

    for path in [arguments.out] + arguments.also:
        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        write_png(path, arguments.size, pixels)
        print(f"wrote {path} ({arguments.size}x{arguments.size})")

    if arguments.preview:
        small = arguments.preview
        root, extension = os.path.splitext(arguments.out)
        path = f"{root}-{small}{extension}"
        write_png(path, small, downsample(arguments.size, pixels, small))
        print(f"wrote {path} ({small}x{small})")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
