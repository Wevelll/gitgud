#!/usr/bin/env python3
"""Generates the Day-Dial app icon (concept A: the dial ring) as SVG variants.

The icon is defined here as geometry, not as checked-in binaries, so any
tweak regenerates every platform asset identically. Pipeline:

    python3 tool/icons/generate.py       # SVGs + manifest.json -> tool/icons/out
    node tool/icons/rasterize.mjs        # PNGs per manifest (needs playwright-core
                                         #   + a Chromium; dev-only, not an app dep)
    python3 tool/icons/assemble.py       # ICO + copy into the platform runners

Variants:
  plate-dark / plate-light   squircle plate (Windows/web/Android-legacy/Linux)
  square-light               full-bleed, no alpha (iOS "Any"; iOS masks corners)
  glyph-dark                 glyph on transparency (iOS dark appearance)
  glyph-tinted               grayscale glyph on transparency (iOS tinted)
  maskable-dark              full-bleed, glyph in the inner safe zone (PWA)
  fg-adaptive / mono-adaptive  Android adaptive foreground / themed monochrome
  macos                      margined squircle on transparency (Big Sur style)
"""

import json
import math
import os

BG_DARK = '#0A0D18'
BG_LIGHT = '#F2F3F8'
HUB_DARK = '#10162A'
HUB_STROKE_DARK = '#2A3352'
HUB_STROKE_LIGHT = '#DCE0EE'
CREAM = '#F2E8D5'
INK = '#2A3050'
PAL = {
    'sleep': '#4B4FA6', 'morning': '#C98A3E', 'deep': '#2E8B8B',
    'lunch': '#B5624F', 'work': '#3E7CB1', 'free': '#6FA85B',
}
# Grays for the iOS "tinted" variant (system tints via luminance).
GRAY = {
    'sleep': '#B9BCC6', 'morning': '#8E93A3', 'deep': '#9BA0AF',
    'lunch': '#7E8494', 'work': '#A6AAB8', 'free': '#C6C9D2',
}
# The reference day (minutes since midnight), same ring the app seeds.
DAY = [
    ('sleep', 1380, 1860), ('morning', 420, 540), ('deep', 540, 780),
    ('lunch', 780, 840), ('work', 840, 1080), ('free', 1080, 1380),
]
C = 256.0


def pt(r, ang_deg, s=1.0):
    a = math.radians(ang_deg - 90.0)
    return (C + r * s * math.cos(a), C + r * s * math.sin(a))


def ring_seg(r0, r1, a0, a1, fill, s=1.0, gap=2.5):
    a0 += gap / 2.0
    a1 -= gap / 2.0
    large = 1 if (a1 - a0) % 360 > 180 else 0
    x0, y0 = pt(r1, a0, s)
    x1, y1 = pt(r1, a1, s)
    x2, y2 = pt(r0, a1, s)
    x3, y3 = pt(r0, a0, s)
    return (
        f'<path d="M {x0:.2f} {y0:.2f} A {r1 * s:.2f} {r1 * s:.2f} 0 {large} 1 '
        f'{x1:.2f} {y1:.2f} L {x2:.2f} {y2:.2f} A {r0 * s:.2f} {r0 * s:.2f} 0 '
        f'{large} 0 {x3:.2f} {y3:.2f} Z" fill="{fill}"/>'
    )


def glyph(s=1.0, colors=PAL, hub=HUB_DARK, hub_stroke=HUB_STROKE_DARK,
          dot=CREAM, mark=CREAM, hub_fill=True):
    """The dial: six segments, hub, center dot, top marker. Scaled about C."""
    out = []
    for name, m0, m1 in DAY:
        out.append(ring_seg(104, 176, m0 / 4.0, m1 / 4.0, colors[name], s))
    if hub_fill:
        out.append(
            f'<circle cx="{C}" cy="{C}" r="{96 * s:.1f}" fill="{hub}" '
            f'stroke="{hub_stroke}" stroke-width="{6 * s:.1f}"/>'
        )
    out.append(f'<circle cx="{C}" cy="{C}" r="{14 * s:.1f}" fill="{dot}"/>')
    w, h, top = 54 * s, 44 * s, C - 212 * s
    out.append(
        f'<path d="M {C - w / 2:.1f} {top:.1f} L {C + w / 2:.1f} {top:.1f} '
        f'L {C} {top + h:.1f} Z" fill="{mark}" stroke="{mark}" '
        f'stroke-width="{10 * s:.1f}" stroke-linejoin="round"/>'
    )
    return ''.join(out)


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 512 512">' + body + '</svg>')


def squircle(fill, s=1.0):
    side = 512 * s
    off = (512 - side) / 2
    return (f'<rect x="{off:.1f}" y="{off:.1f}" width="{side:.1f}" '
            f'height="{side:.1f}" rx="{115 * s:.1f}" fill="{fill}"/>')


variants = {
    'plate-dark': svg(squircle(BG_DARK) + glyph()),
    'plate-light': svg(
        squircle(BG_LIGHT)
        + glyph(hub_stroke=HUB_STROKE_LIGHT, dot=CREAM, mark=INK)
    ),
    'square-light': svg(
        f'<rect width="512" height="512" fill="{BG_LIGHT}"/>'
        + glyph(hub_stroke=HUB_STROKE_LIGHT, dot=CREAM, mark=INK)
    ),
    'glyph-dark': svg(glyph()),
    'glyph-tinted': svg(
        glyph(colors=GRAY, hub='#3A3F4E', hub_stroke='#565C6E',
              dot='#FFFFFF', mark='#FFFFFF')
    ),
    'maskable-dark': svg(
        f'<rect width="512" height="512" fill="{BG_DARK}"/>' + glyph(s=0.78)
    ),
    'fg-adaptive': svg(glyph(s=0.72)),
    'mono-adaptive': svg(
        glyph(s=0.72, colors={k: '#FFFFFF' for k in PAL}, dot='#FFFFFF',
              mark='#FFFFFF', hub_fill=False)
    ),
    'macos': svg(squircle(BG_DARK, s=0.82) + glyph(s=0.82)),
}

# Every PNG the platforms need: (variant, size, output name).
RASTER = []
for size in (16, 24, 32, 48, 64, 128, 256):
    RASTER.append(('plate-dark', size, f'win_{size}.png'))
for size in (48, 72, 96, 144, 192):
    RASTER.append(('plate-dark', size, f'android_legacy_{size}.png'))
for size in (108, 162, 216, 324, 432):
    RASTER.append(('fg-adaptive', size, f'android_fg_{size}.png'))
    RASTER.append(('mono-adaptive', size, f'android_mono_{size}.png'))
for size in (16, 32, 64, 128, 256, 512, 1024):
    RASTER.append(('macos', size, f'macos_{size}.png'))
RASTER += [
    ('square-light', 1024, 'ios_any_1024.png'),
    ('glyph-dark', 1024, 'ios_dark_1024.png'),
    ('glyph-tinted', 1024, 'ios_tinted_1024.png'),
    ('plate-dark', 192, 'web_192.png'),
    ('plate-dark', 512, 'web_512.png'),
    ('maskable-dark', 192, 'web_maskable_192.png'),
    ('maskable-dark', 512, 'web_maskable_512.png'),
    ('plate-dark', 48, 'web_favicon_48.png'),
    ('plate-dark', 256, 'linux_256.png'),
    ('plate-dark', 512, 'linux_512.png'),
]


def favicon():
    """Theme-aware favicon: plate/marker/hub-stroke flip with the browser
    theme via CSS classes; geometry identical to the plate variants."""
    style = (
        '<style>.plate{fill:#F2F3F8}.mark{fill:#2A3050;stroke:#2A3050}'
        '.hubs{stroke:#DCE0EE}'
        '@media (prefers-color-scheme: dark){.plate{fill:#0A0D18}'
        '.mark{fill:#F2E8D5;stroke:#F2E8D5}.hubs{stroke:#2A3352}}</style>'
    )
    body = squircle('CLASS_PLATE')
    body += glyph(hub_stroke='CLASS_HUBS', mark='CLASS_MARK')
    body = (body
            .replace('fill="CLASS_PLATE"', 'class="plate"')
            .replace('stroke="CLASS_HUBS"', 'class="hubs"')
            .replace('fill="CLASS_MARK" stroke="CLASS_MARK"', 'class="mark"'))
    return svg(style + body)


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
    os.makedirs(out, exist_ok=True)
    for name, content in variants.items():
        with open(os.path.join(out, f'{name}.svg'), 'w') as f:
            f.write(content)
    with open(os.path.join(out, 'favicon.svg'), 'w') as f:
        f.write(favicon())
    with open(os.path.join(out, 'manifest.json'), 'w') as f:
        json.dump([
            {'variant': v, 'size': s, 'file': fn} for v, s, fn in RASTER
        ], f, indent=2)
    print(f'wrote {len(variants)} SVGs + favicon + manifest '
          f'({len(RASTER)} rasters)')


if __name__ == '__main__':
    main()
