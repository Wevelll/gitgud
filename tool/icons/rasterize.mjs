// Rasterizes tool/icons/out/*.svg to PNGs per manifest.json using a local
// Chromium (playwright-core). Dev-only tooling — not an app dependency.
//
//   npm i playwright-core   (or reuse an existing install)
//   PW_EXE=/path/to/chrome node tool/icons/rasterize.mjs
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, 'out');
const manifest = JSON.parse(readFileSync(join(out, 'manifest.json'), 'utf8'));

const exe = process.env.PW_EXE;
if (!exe) throw new Error('Set PW_EXE to a Chromium executable');

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
for (const { variant, size, file } of manifest) {
  const page = await browser.newPage({
    viewport: { width: size, height: size },
    deviceScaleFactor: 1,
  });
  const svg = readFileSync(join(out, `${variant}.svg`), 'utf8');
  await page.setContent(
    `<style>*{margin:0}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`,
  );
  await page.screenshot({ path: join(out, file), omitBackground: true });
  await page.close();
}
await browser.close();
console.log(`rasterized ${manifest.length} PNGs`);
