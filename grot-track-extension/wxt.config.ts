import { defineConfig } from 'wxt';

export default defineConfig({
  manifest: {
    name: 'GrotTrack Tab Tracker',
    version: '1.0.0',
    description: 'Sends active tab information to the GrotTrack macOS app for time tracking.',
    permissions: ['tabs', 'nativeMessaging'],
  },
  browser: 'chrome',
  manifestVersion: 3,
});
