#!/usr/bin/env python3
"""Assembles rasterized icon PNGs into the platform runners.

Run after generate.py + rasterize.mjs. Writes:
  windows/runner/resources/app_icon.ico        (multi-size, PNG-compressed)
  android mipmaps (legacy + adaptive foreground/monochrome)
  ios/Runner/Assets.xcassets/AppIcon.appiconset (single-size + appearances)
  macos/Runner/Assets.xcassets/AppIcon.appiconset
  web/icons + web/favicon.png
  assets/icon (Linux/packaging masters)
"""

import json
import os
import shutil
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))


def p(*parts):
    return os.path.join(ROOT, *parts)


def write_ico(dest, pngs):
    """ICO container with PNG-compressed entries (Vista+)."""
    entries, blobs, offset = [], [], 6 + 16 * len(pngs)
    for size, path in pngs:
        with open(path, 'rb') as f:
            data = f.read()
        dim = 0 if size >= 256 else size  # 0 encodes 256
        entries.append(struct.pack(
            '<BBBBHHII', dim, dim, 0, 0, 1, 32, len(data), offset,
        ))
        blobs.append(data)
        offset += len(data)
    with open(dest, 'wb') as f:
        f.write(struct.pack('<HHH', 0, 1, len(pngs)))
        f.writelines(entries)
        f.writelines(blobs)


def main():
    # Windows
    write_ico(
        p('windows', 'runner', 'resources', 'app_icon.ico'),
        [(s, os.path.join(OUT, f'win_{s}.png'))
         for s in (16, 24, 32, 48, 64, 128, 256)],
    )

    # Android: legacy launcher + adaptive foreground/monochrome per density.
    densities = {
        'mdpi': (48, 108), 'hdpi': (72, 162), 'xhdpi': (96, 216),
        'xxhdpi': (144, 324), 'xxxhdpi': (192, 432),
    }
    res = p('android', 'app', 'src', 'main', 'res')
    for name, (legacy, adaptive) in densities.items():
        d = os.path.join(res, f'mipmap-{name}')
        os.makedirs(d, exist_ok=True)
        shutil.copy(os.path.join(OUT, f'android_legacy_{legacy}.png'),
                    os.path.join(d, 'ic_launcher.png'))
        shutil.copy(os.path.join(OUT, f'android_fg_{adaptive}.png'),
                    os.path.join(d, 'ic_launcher_foreground.png'))
        shutil.copy(os.path.join(OUT, f'android_mono_{adaptive}.png'),
                    os.path.join(d, 'ic_launcher_monochrome.png'))
    anydpi = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon '
            'xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n'
        )
    values = os.path.join(res, 'values')
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, 'ic_launcher_background.xml'), 'w') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <color name="ic_launcher_background">#0A0D18</color>\n'
            '</resources>\n'
        )

    # iOS: modern single-size icon with light/dark/tinted appearances.
    appiconset = p('ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    for old in os.listdir(appiconset):
        if old.endswith('.png'):
            os.remove(os.path.join(appiconset, old))
    # The primary icon must carry no alpha channel (App Store validation);
    # flatten RGBA -> RGB. The dark/tinted variants NEED their transparency.
    from PIL import Image
    Image.open(os.path.join(OUT, 'ios_any_1024.png')).convert('RGB').save(
        os.path.join(appiconset, 'Icon-App-1024x1024@1x.png'))
    shutil.copy(os.path.join(OUT, 'ios_dark_1024.png'),
                os.path.join(appiconset, 'Icon-App-1024x1024-dark.png'))
    shutil.copy(os.path.join(OUT, 'ios_tinted_1024.png'),
                os.path.join(appiconset, 'Icon-App-1024x1024-tinted.png'))
    contents = {
        'images': [
            {
                'filename': 'Icon-App-1024x1024@1x.png',
                'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024',
            },
            {
                'appearances': [
                    {'appearance': 'luminosity', 'value': 'dark'},
                ],
                'filename': 'Icon-App-1024x1024-dark.png',
                'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024',
            },
            {
                'appearances': [
                    {'appearance': 'luminosity', 'value': 'tinted'},
                ],
                'filename': 'Icon-App-1024x1024-tinted.png',
                'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024',
            },
        ],
        'info': {'author': 'xcode', 'version': 1},
    }
    with open(os.path.join(appiconset, 'Contents.json'), 'w') as f:
        json.dump(contents, f, indent=2)
        f.write('\n')

    # macOS: same filenames the template's Contents.json already lists.
    mac = p('macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    for s in (16, 32, 64, 128, 256, 512, 1024):
        shutil.copy(os.path.join(OUT, f'macos_{s}.png'),
                    os.path.join(mac, f'app_icon_{s}.png'))

    # Web
    for src, dst in [
        ('web_192.png', 'Icon-192.png'), ('web_512.png', 'Icon-512.png'),
        ('web_maskable_192.png', 'Icon-maskable-192.png'),
        ('web_maskable_512.png', 'Icon-maskable-512.png'),
    ]:
        shutil.copy(os.path.join(OUT, src), p('web', 'icons', dst))
    shutil.copy(os.path.join(OUT, 'web_favicon_48.png'), p('web', 'favicon.png'))
    shutil.copy(os.path.join(OUT, 'favicon.svg'), p('web', 'favicon.svg'))

    # Linux / packaging masters
    os.makedirs(p('assets', 'icon'), exist_ok=True)
    for s in (256, 512):
        shutil.copy(os.path.join(OUT, f'linux_{s}.png'),
                    p('assets', 'icon', f'day_dial_{s}.png'))
    shutil.copy(os.path.join(OUT, 'plate-dark.svg'),
                p('assets', 'icon', 'day_dial.svg'))

    print('assembled icons into platform runners')


if __name__ == '__main__':
    main()
