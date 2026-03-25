#!/usr/bin/env node

/**
 * Generates all required icon sizes for the Chrome extension and macOS app
 * from the master SVG at assets/icon.svg.
 *
 * Usage: node scripts/generate-icons.mjs
 * Requires: sharp (npm install)
 */

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');

const svgBuffer = readFileSync(join(root, 'assets', 'icon.svg'));

// Chrome extension icon sizes
const chromeIcons = [
  { size: 16, name: 'icon-16.png' },
  { size: 48, name: 'icon-48.png' },
  { size: 128, name: 'icon-128.png' },
];

// macOS app icon sizes (per Contents.json: size@scale)
const macIcons = [
  { size: 16, name: 'icon_16x16.png' },
  { size: 32, name: 'icon_16x16@2x.png' },
  { size: 32, name: 'icon_32x32.png' },
  { size: 64, name: 'icon_32x32@2x.png' },
  { size: 128, name: 'icon_128x128.png' },
  { size: 256, name: 'icon_128x128@2x.png' },
  { size: 256, name: 'icon_256x256.png' },
  { size: 512, name: 'icon_256x256@2x.png' },
  { size: 512, name: 'icon_512x512.png' },
  { size: 1024, name: 'icon_512x512@2x.png' },
];

const chromeDir = join(root, 'grot-track-extension', 'public');
const macDir = join(root, 'GrotTrack', 'Assets.xcassets', 'AppIcon.appiconset');

async function generate(outDir, icons) {
  for (const { size, name } of icons) {
    await sharp(svgBuffer, { density: Math.round((72 * size) / 1024) * 10 })
      .resize(size, size)
      .png()
      .toFile(join(outDir, name));
    console.log(`  ${name} (${size}x${size})`);
  }
}

console.log('Generating Chrome extension icons...');
await generate(chromeDir, chromeIcons);

console.log('Generating macOS app icons...');
await generate(macDir, macIcons);

console.log('Done.');
