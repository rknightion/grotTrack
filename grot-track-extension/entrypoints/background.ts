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

    function connectToHost(): void {
      try {
        port = chrome.runtime.connectNative(NATIVE_HOST);

        port.onMessage.addListener((message: { action: string }) => {
          if (message.action === 'getTabs') {
            sendActiveTabInfo();
          }
        });

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
            tabId: tab.id!,
            windowId: tab.windowId,
            timestamp: Date.now(),
          };
          port.postMessage(message);
        }
      } catch (error) {
        console.error('GrotTrack: Error querying tabs:', error);
      }
    }

    chrome.tabs.onActivated.addListener(() => {
      sendActiveTabInfo();
    });

    chrome.tabs.onUpdated.addListener((_tabId, changeInfo) => {
      if (changeInfo.title || changeInfo.url) {
        sendActiveTabInfo();
      }
    });

    chrome.windows.onFocusChanged.addListener(() => {
      sendActiveTabInfo();
    });

    connectToHost();
  },
});
