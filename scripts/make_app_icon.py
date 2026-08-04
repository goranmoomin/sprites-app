#!/usr/bin/env python3
"""Build App/AppIcon.icon from the sprite logo published on docs.sprites.dev.

Fetches the page, pulls the logo svg out of the header, re-emits its three
tones (body, inner, eyes) as 1024x1024 stencil assets, reads the site's css
variables for their colors and for the background gradient, and writes the
Icon Composer package.
"""

import argparse
import json
import re
import shutil
import sys
import urllib.parse
import urllib.request
from html import escape
from html.parser import HTMLParser
from pathlib import Path

DOCS_URL = "https://docs.sprites.dev/"

# Icon Composer's design canvas, in points.
CANVAS = 1024
# How wide the creature sits on that canvas, in points.
LOGO_WIDTH = 724

# Background gradient stops, as css variables, lighter end first in each theme:
# white to pale violet in light, violet-tinted charcoal to near-black in dark.
BACKGROUND_VARS = ("--sl-color-bg", "--sl-color-accent-low")
BACKGROUND_VARS_DARK = ("--sl-color-accent-low", "--sl-color-bg")

# Each tone, as the class marking its shapes (newest naming first), the css
# variable holding its color, and whether it takes LiquidGlass. The eyes read
# as holes, so they stay flat. Ordered bottom-most layer first.
TONES = [
    ("Outline", "sprite-outline.svg", {"body", "fill-navy-900"}, "--logo-body", True),
    ("Body", "sprite-body.svg", {"inner", "fill-violet-600"}, "--logo-inner", True),
    ("Eyes", "sprite-eyes.svg", {"eye"}, "--logo-eye", False),
]

SHAPES = {"path", "rect", "circle", "ellipse", "polygon", "polyline", "line"}


class PageParser(HTMLParser):
    """Collects every inline svg as (viewBox, shapes) plus stylesheet hrefs."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.svgs = []
        self.stylesheets = []
        self._depth = 0
        self._view_box = None
        self._shapes = []

    def handle_starttag(self, tag, attrs):
        attrs = [(name, value or "") for name, value in attrs]
        if tag == "svg":
            self._depth += 1
            if self._depth == 1:
                # HTMLParser lower-cases attribute names, so viewBox arrives as viewbox.
                self._view_box = dict(attrs).get("viewbox", "")
                self._shapes = []
        elif self._depth and tag in SHAPES:
            classes = set(dict(attrs).get("class", "").split())
            self._shapes.append((classes, tag, [a for a in attrs if a[0] != "class"]))
        elif tag == "link":
            link = dict(attrs)
            if "stylesheet" in link.get("rel", "") and link.get("href"):
                self.stylesheets.append(link["href"])

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag == "svg":
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag == "svg" and self._depth:
            self._depth -= 1
            if self._depth == 0:
                self.svgs.append((self._view_box, self._shapes))


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "make_app_icon"})
    with urllib.request.urlopen(request) as response:
        return response.read().decode("utf-8")


def find_logo(svgs):
    """Return (width, height, shapes) for the svg carrying the logo's tones.

    The page has several inline svgs, so the logo is identified by content
    rather than by position: only it has both an outline and an inner tone.
    """
    for view_box, shapes in svgs:
        tones = [classes for classes, _, _ in shapes]
        if not all(any(c & tone for c in tones) for _, _, tone, _, _ in TONES[:2]):
            continue
        box = view_box.split()
        if len(box) != 4:
            raise SystemExit(f"logo svg has an unusable viewBox: {view_box!r}")
        return float(box[2]), float(box[3]), shapes
    raise SystemExit("no logo svg found on the page")


def palettes(css):
    """Return the ({var: hex}, {var: hex}) declared for light and dark.

    Declarations resolving to something other than a hex color, such as a
    var() reference, are skipped; later blocks win, as in the cascade.
    """
    light, dark = {}, {}
    for selector, block in re.findall(r"([^{}]*)\{([^{}]*)\}", css):
        declarations = re.findall(r"(--[\w-]+)\s*:\s*(#[0-9a-fA-F]{3,6})\b", block)
        if declarations:
            target = light if "[data-theme=light]" in selector else dark
            target.update(dict(declarations))
    if not light or not dark:
        raise SystemExit("page does not declare css color variables for both themes")
    return light, dark


def color(hex_color):
    """An Icon Composer color string, from a 3 or 6 digit css hex color."""
    digits = hex_color.lstrip("#")
    if len(digits) == 3:
        digits = "".join(d * 2 for d in digits)
    components = ",".join(f"{int(digits[i:i + 2], 16) / 255:.3f}" for i in (0, 2, 4))
    return f"extended-srgb:{components},1.000"


def stencil(shapes, tone, width, height, logo_width):
    """Wrap the shapes of one tone in a 1024pt svg, centered and scaled."""
    selected = [
        "<{} {}/>".format(tag, " ".join(f'{n}="{escape(v)}"' for n, v in attrs))
        for classes, tag, attrs in shapes
        if classes & tone
    ]
    if not selected:
        return None
    scale = logo_width / width
    x = (CANVAS - width * scale) / 2
    y = (CANVAS - height * scale) / 2
    body = "\n    ".join(selected)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">\n'
        f'  <g transform="translate({x:.3f} {y:.3f}) scale({scale:.5f})" '
        f'fill="#000000" fill-rule="evenodd">\n    {body}\n  </g>\n</svg>\n'
    )


def layer(name, asset, light, dark, glass):
    """One image layer, specialized per appearance only when the colors differ."""
    fill = (
        {"fill": {"solid": color(light)}}
        if light == dark
        else {"fill-specializations": [
            {"value": {"solid": color(light)}},
            {"appearance": "dark", "value": {"solid": color(dark)}},
        ]}
    )
    return {"name": name, "image-name": asset, "glass": glass, **fill}


def document(layers, background, background_dark):
    """The icon.json. Layers are listed topmost first."""
    return {
        "fill-specializations": [
            {"value": {"linear-gradient": background}},
            {"appearance": "dark", "value": {"linear-gradient": background_dark}},
        ],
        "groups": [
            {
                "layers": layers[::-1],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.5},
            }
        ],
        "supported-platforms": {"squares": "shared"},
    }


def gradient(palette, variables):
    """The two color stops named by variables, looked up in one theme."""
    missing = [v for v in variables if v not in palette]
    if missing:
        raise SystemExit(f"page does not declare {', '.join(missing)}")
    return [color(palette[v]) for v in variables]


def write_package(output, icon, assets):
    if output.suffix != ".icon":
        raise SystemExit(f"{output} must end in .icon")
    shutil.rmtree(output, ignore_errors=True)
    (output / "Assets").mkdir(parents=True)
    (output / "icon.json").write_text(json.dumps(icon, indent=2, sort_keys=True) + "\n")
    for name, svg in assets.items():
        (output / "Assets" / name).write_text(svg)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=DOCS_URL, help="page carrying the logo")
    parser.add_argument("--output", type=Path, default=Path("App/AppIcon.icon"))
    parser.add_argument("--logo-width", type=float, default=LOGO_WIDTH,
                        help=f"creature width in points, on a {CANVAS}pt canvas")
    args = parser.parse_args()

    page = PageParser()
    page.feed(fetch(args.url))
    width, height, shapes = find_logo(page.svgs)
    css = "".join(fetch(urllib.parse.urljoin(args.url, href)) for href in page.stylesheets)
    light, dark = palettes(css)

    layers, assets = [], {}
    for name, asset, tone, variable, glass in TONES:
        svg = stencil(shapes, tone, width, height, args.logo_width)
        if svg is None:  # older markup has no eye shapes
            continue
        if variable not in light or variable not in dark:
            raise SystemExit(f"{variable} is not declared for both themes")
        layers.append(layer(name, asset, light[variable], dark[variable], glass))
        assets[asset] = svg

    icon = document(
        layers,
        gradient(light, BACKGROUND_VARS),
        gradient(dark, BACKGROUND_VARS_DARK),
    )
    write_package(args.output, icon, assets)
    print(f"created {args.output} from {len(assets)} tone(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
