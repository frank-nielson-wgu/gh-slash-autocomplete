// The extension has no popup of its own; its toolbar icon opens the options page.
chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());
