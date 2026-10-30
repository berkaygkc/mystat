#!/usr/bin/env python3
"""Renders the README images and the social preview from sample data into .github/assets/.

Usage (from the repository root, after `swift build` and `scripts/make-app.sh`):
    python3 tools/readme-screenshots.py

Needs Pillow (`pip3 install pillow`). Every image is drawn at 2x by the app's own snapshot mode in English, then
cropped so the content sits in the middle with equal margins on all sides.
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops

BIN = ".build/debug/mystat"
OUT = Path(".github/assets")
SCALE = 2


def render(target, size, *extra, dark=False):
    """Renders a snapshot and returns it as an RGB image (pixels = points × SCALE)."""
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        args = [BIN, "--lang", "en", "--scale", str(SCALE), "--snapshot", target, "--size", size, "--out", f.name, *extra]
        if dark:
            args.append("--dark")
        subprocess.run(args, check=True, capture_output=True)
        return Image.open(f.name).convert("RGB")


def content_box(image, size, dark, threshold=40):
    """Bounds of whatever differs clearly from the plain wallpaper (shadows are faint and stay outside)."""
    backdrop = render("backdrop", size, dark=dark)
    mask = ImageChops.difference(image, backdrop).convert("L").point(lambda v: 255 if v > threshold else 0)
    return mask.getbbox()


def crop(image, box, margin):
    """Crops `box` with `margin` points around it."""
    m = margin * SCALE
    left, top, right, bottom = box
    return image.crop((left - m, top - m, right + m, bottom + m))


def save(image, name, width):
    """Scales to `width` pixels (2x the width it is shown at) and writes an optimized PNG."""
    height = round(image.height * width / image.width)
    image.resize((width, height), Image.LANCZOS).save(OUT / name, optimize=True)
    print(f"{OUT / name}: {width}×{height}, {(OUT / name).stat().st_size // 1024} KB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    # Hero: menu bar, the panel opened beneath it and the monitor window, in light and dark. The view keeps 64 pt side
    # margins itself; the bottom is cut 64 pt below the panel too. The layout is the same in both appearances, so the
    # light one is measured (dark glass on the dark wallpaper is too close to it to measure reliably).
    bottom = None
    for dark, name in [(False, "hero-light.png"), (True, "hero-dark.png")]:
        image = render("hero", "1600x900", "--incident", "--kind", "cpu", dark=dark)
        bottom = bottom or content_box(image, "1600x900", dark)[3]
        save(image.crop((0, 0, image.width, bottom + 64 * SCALE)), name, 1800)

    # The panel, calm and during an incident, side by side on one wallpaper.
    image = render("panels", "1100x900")
    save(crop(image, content_box(image, "1100x900", False), 48), "panels.png", 1600)

    # Monitor sections: snapshot mode draws the window at a fixed frame (46, 56)–(1354, 860) in a 1400×900 canvas, so the
    # crop is fixed too, 40 pt on every side (measuring would pick up the window's shadow).
    window = tuple(v * SCALE for v in (46, 56, 1354, 860))
    for name, section in [("overview.png", "overview"), ("disk.png", "disk"), ("docker.png", "docker"), ("system.png", "sys")]:
        save(crop(render("monitor", "1400x900", "--section", section), window, 40), name, 1600)

    # GitHub's social preview (Settings → General → Social preview), 1280×640 and under 1 MB. Dark reads best as a
    # thumbnail. The view draws its own 64 pt margins.
    save(render("social", "1280x640", "--incident", "--kind", "cpu", dark=True), "social-preview.png", 1280)


if __name__ == "__main__":
    main()
