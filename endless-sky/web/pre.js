// Prepended to the Emscripten output (--pre-js). Runs before the game starts.
//
// Endless Sky keeps its user files (saves/, preferences.txt, keys.txt, errors.txt, plugins/) in
// its config directory, which the browser build sets to /persist. Back that folder with
// IndexedDB so pilots and preferences survive page reloads. The game data (/data, /images,
// /sounds, /shaders) is preloaded at / and is not touched here.
//
// Storing (FS.syncfs(false)) makes IndexedDB an exact copy of /persist: files missing from
// /persist are deleted from IndexedDB. So nothing is stored before the saves have loaded, and
// nothing at all in a session whose load failed.

var PERSIST_DIR = '/persist';
// If IndexedDB never answers (broken or blocked storage), start anyway after this long.
var PERSIST_LOAD_TIMEOUT_MS = 15000;

// 'loading' until the saves are in /persist, then 'ready'. 'off' if the load failed: /persist
// may be incomplete, and storing it would erase the saves that did not load.
var persistState = 'loading';

// Tell the console and the player (the page shows the text).
function persistWarning(text, err) {
  console.warn(text, err || '');
  if (Module.onPersistWarning) Module.onPersistWarning(text);
}

Module.preRun = [].concat(Module.preRun || []);
Module.preRun.push(function () {
  FS.mkdirTree(PERSIST_DIR);
  try {
    FS.mount(IDBFS, {}, PERSIST_DIR);
  } catch (err) {
    // Without IDBFS the folder stays in memory: the game runs, but nothing is kept.
    persistState = 'off';
    persistWarning('Saving is off: this browser does not offer IndexedDB storage.', err);
    return;
  }

  // Hold the start of the game until the user files are loaded from IndexedDB.
  addRunDependency('load-persist');
  var done = false;
  function finish() {
    if (done) return;
    done = true;
    clearTimeout(timer);
    removeRunDependency('load-persist');
  }
  var timer = setTimeout(function () {
    // Start without the saves. Saves requested meanwhile wait for the load (see Module.syncSaves).
    persistWarning('Your saved pilots are taking long to load from browser storage, so the game ' +
      'starts without them. Progress saved before they finish loading may be lost.');
    finish();
  }, PERSIST_LOAD_TIMEOUT_MS);

  FS.syncfs(true, function (err) {
    if (err) {
      persistState = 'off';
      persistWarning('Saving is off for this session: browser storage (IndexedDB) could not be ' +
        'read, and writing to it now could erase your saved pilots.', err);
    } else {
      persistState = 'ready';
    }
    finish();
    // A save requested before the load finished (only possible after the timeout) was held back.
    if (saveSyncPending && persistState === 'ready') {
      saveSyncPending = false;
      Module.syncSaves();
    }
  });
});

// Called from C (Files.cpp, under __EMSCRIPTEN__) after each write, delete, move or copy in
// /persist. Only one store runs at a time; calls made meanwhile are merged into one more run.
var saveSyncRunning = false;
var saveSyncPending = false;
Module.syncSaves = function () {
  if (persistState === 'off') return;
  if (saveSyncRunning || persistState !== 'ready') {
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
