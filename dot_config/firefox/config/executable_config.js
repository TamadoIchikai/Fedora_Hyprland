// config.js file needs to start with a comment line

var Services = globalThis.Services;
Services.console.logStringMessage("config.js script loaded");

if (!Services.appinfo.inSafeMode) {
  Services.obs.addObserver(function (aSubject) {
    var chromeWindow = aSubject;
    chromeWindow.addEventListener("load", function (aEvent) {
      var doc = aEvent.target;
      if (doc.location.href === "chrome://browser/content/browser.xhtml") {
        chromeWindow.setTimeout(() => {
          try {
            const keysToRemove = [
              'key_search2', 'key_search', 'openFileKb', 'key_viewSource', 'key_viewInfo',
              'viewBookmarksSidebarKb', 'viewBookmarksToolbarKb', 'bookmarkAllTabsKb',
              'key_closeWindow', 'focusURLBar', 'printKb'
            ];

            keysToRemove.forEach(id => {
              const key = doc.getElementById(id);
              if (key) key.remove();
            });

            const mainKeyset = doc.getElementById('mainKeyset');
            if (mainKeyset) {
              const newShortcuts = [
                { id: 'key_AddressBar', modifiers: 'accel', key: 'O', command: 'Browser:OpenLocation' },
                { id: 'key_TabGoDown', modifiers: 'accel', key: 'J', command: 'Browser:NextTab' },
                { id: 'key_TabGoUp', modifiers: 'accel', key: 'K', command: 'Browser:PrevTab' },
                { id: 'key_undoCloseTab', modifiers: 'accel, shift', key: 'W', command: 'History:UndoCloseTab' }
              ];

              newShortcuts.forEach(({ id, modifiers, key, command }) => {
                const newKey = doc.createElementNS('http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul', 'key');
                newKey.setAttribute("id", id);
                newKey.setAttribute("modifiers", modifiers);
                newKey.setAttribute("key", key);
                newKey.setAttribute("command", command);
                mainKeyset.appendChild(newKey);
              });

              const modifyShortcuts = [
                { id: 'key_quitApplication', modifiers: 'accel, shift',key: 'Q' },
                { id: 'key_privatebrowsing', key: 'N' },
                { id: 'key_undoCloseWindow', modifiers: 'accel', key: 'Q' },
                { id: 'showAllHistoryKb',modifiers: 'accel', key: 'P' },
                { id: 'addBookmarkAsKb', key: 'B' },
                { id: 'manBookmarkKb', key: 'B' },
                { id: 'key_gotoHistory', key: 'P' },
                { id: 'goBackKb', modifiers: 'accel', key: 'H' },
                { id: 'goForwardKb', modifiers: 'accel', key: 'L' },
                { id: 'key_openDownloads', modifiers: 'accel', key: 'I' }
              ];

              modifyShortcuts.forEach(({ id, modifiers, key }) => {
                const shortcut = doc.getElementById(id);
                if (shortcut) {
                  if (modifiers) shortcut.setAttribute("modifiers", modifiers);
                  if (key) shortcut.setAttribute("key", key);
                }
              });
            }
          } catch (e) {
            Components.utils.reportError(e);
          }
        }, 10);
      }
    }, false);
  }, "chrome-document-global-created", false);
}

