// Prepended to the Emscripten output (--pre-js). Runs before the game starts.
//
// SDLPoP writes its saves (PRINCE.SAV, QUICKSAVE.SAV, PRINCE.HOF, SDLPoP.cfg) to $HOME/.SDLPoP.
// Back that folder with IndexedDB so saves survive page reloads.

var SAVE_DIR = '/home/web_user/.SDLPoP';

Module.preRun = [].concat(Module.preRun || []);
Module.preRun.push(function () {
  FS.mkdirTree(SAVE_DIR);
  FS.mount(IDBFS, {}, SAVE_DIR);
  // Hold the start of the game until the saves are loaded from IndexedDB.
  addRunDependency('load-saves');
  FS.syncfs(true, function (err) {
    if (err) console.warn('Could not load saves from IndexedDB:', err);
    removeRunDependency('load-saves');
  });
});

// Called from C (sync_saves() in common.h) after a save file is written.
var saveSyncRunning = false;
var saveSyncPending = false;
Module.syncSaves = function () {
  if (saveSyncRunning) {
    saveSyncPending = true;
    return;
  }
  saveSyncRunning = true;
  FS.syncfs(false, function (err) {
    if (err) console.warn('Could not store saves in IndexedDB:', err);
    saveSyncRunning = false;
    if (saveSyncPending) {
      saveSyncPending = false;
      Module.syncSaves();
    }
  });
};
