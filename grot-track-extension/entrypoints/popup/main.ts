const statusEl = document.getElementById('status')!;

chrome.runtime.sendMessage({ action: 'getStatus' }, (response) => {
  if (chrome.runtime.lastError || !response) {
    statusEl.textContent = 'GrotTrack not running';
    statusEl.className = 'status disconnected';
    return;
  }

  if (response.connected) {
    statusEl.textContent = 'Connected to GrotTrack';
    statusEl.className = 'status connected';
  } else {
    statusEl.textContent = 'GrotTrack not running';
    statusEl.className = 'status disconnected';
  }
});
