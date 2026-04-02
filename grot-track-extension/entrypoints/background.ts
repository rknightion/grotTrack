const NATIVE_HOST = 'com.grottrack.tabtracker';

interface TabMessage {
  type: 'activeTab';
  title: string;
  url: string;
  tabId: number;
  windowId: number;
  timestamp: number;
}

export default defineBackground({
  type: 'module',

  main() {
    let port: chrome.runtime.Port | null = null;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;

    function connectToHost(): void {
      try {
        port = chrome.runtime.connectNative(NATIVE_HOST);

        port.onDisconnect.addListener(() => {
          console.log('GrotTrack: Native host disconnected. Will retry in 5s.');
          port = null;
          setTimeout(connectToHost, 5000);
        });

        console.log('GrotTrack: Connected to native host.');
      } catch (error) {
        console.error('GrotTrack: Failed to connect:', error);
        setTimeout(connectToHost, 5000);
      }
    }

    async function sendActiveTabInfo(): Promise<void> {
      try {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (tab && port) {
          const message: TabMessage = {
            type: 'activeTab',
            title: tab.title || '',
            url: tab.url || '',
            tabId: tab.id ?? -1,
            windowId: tab.windowId,
            timestamp: Date.now(),
          };
          port.postMessage(message);
        }
      } catch (error) {
        console.error('GrotTrack: Error querying tabs:', error);
      }
    }

    function sendActiveTabInfoDebounced(): void {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(sendActiveTabInfo, 300);
    }

    chrome.tabs.onActivated.addListener(() => {
      sendActiveTabInfoDebounced();
    });

    chrome.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
      if ((changeInfo.title || changeInfo.url) && tab.active) {
        sendActiveTabInfoDebounced();
      }
    });

    chrome.windows.onFocusChanged.addListener((windowId) => {
      if (windowId !== chrome.windows.WINDOW_ID_NONE) {
        sendActiveTabInfoDebounced();
      }
    });

    chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
      if (message.action === 'getStatus') {
        sendResponse({ connected: port !== null });
      }
    });

    connectToHost();
  },
});
