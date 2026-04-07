import { defineConfig } from 'wxt';

export default defineConfig({
  manifest: {
    name: 'GrotTrack Tab Tracker',
    version: '0.11.0', // x-release-please-version
    description: 'Sends active tab information to the GrotTrack macOS app for time tracking.',
    permissions: ['tabs', 'nativeMessaging'],
    icons: {
      16: '/icon-16.png',
      48: '/icon-48.png',
      128: '/icon-128.png',
    },
    action: {
      default_icon: {
        16: '/icon-16.png',
        48: '/icon-48.png',
        128: '/icon-128.png',
      },
    },
  },
  browser: 'chrome',
  manifestVersion: 3,
});
