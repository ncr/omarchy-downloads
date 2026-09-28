// Exercise the production rebuild function without starting a desktop shell.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const qml = fs.readFileSync(path.join(__dirname, '../DownloadsStore.qml'), 'utf8');
const rebuild = qml.slice(qml.indexOf('  function rebuild()'), qml.indexOf('  onFilterChanged:'));
const now = 1_000_000;
const source = () => ({ files: [], omitted: [], truncated: false, error: '' });
const row = (path, category, source, modified = now, omitted = false) =>
  ({ path, category, source, modified, omitted });
function store() {
  const state = {
    now, freshMinutes: 5, maxRows: 200, showAll: false, filter: 'all',
    draggingUrl: '', pendingRebuild: false, files: [],
    downloads: source(), pictures: source(), videos: source(),
    fileUrl: path => 'file://' + path,
  };
  state.root = state;
  vm.createContext(state);
  vm.runInContext(rebuild, state);
  return state;
}

// The screenshot regression: six old omitted files, no recent files.
const s = store();
s.pictures.omitted = Array.from({ length: 6 }, (_, i) =>
  row('/pictures/' + i, 'images', 'images', now - 600_000, true));
s.rebuild();
assert.equal(s.files.length, 0);
assert.equal(s.hiddenCount, 0);
s.showAll = true;
s.rebuild();
assert.equal(s.hiddenCount, 6);
s.filter = 'videos';
s.rebuild();
assert.equal(s.hiddenCount, 0);

// Recent overflow respects media filters, source filters and elapsed time.
const t = store();
t.downloads.omitted = [row('/downloads/image', 'images', 'downloads', now, true)];
t.pictures.omitted = [row('/pictures/image', 'images', 'images', now, true)];
t.videos.omitted = [row('/videos/movie', 'videos', 'videos', now, true)];
for (const [filter, expected] of [['all', 3], ['downloads', 1], ['images', 2], ['videos', 1]]) {
  t.filter = filter;
  t.rebuild();
  assert.equal(t.hiddenCount, expected, filter);
}
t.now += 300_001;
t.rebuild();
assert.equal(t.hiddenCount, 0);

// Count the visible-list cap plus matching overflow, without double counting
// files from overlapping configured folders or displaying metadata as rows.
const u = store();
u.downloads.files = Array.from({ length: 200 }, (_, i) => row('/downloads/' + i, 'other', 'downloads'));
u.pictures.files = [row('/pictures/image', 'images', 'images')];
u.downloads.omitted = [row('/downloads/extra', 'other', 'downloads', now, true)];
u.pictures.omitted = [row('/pictures/image', 'images', 'images', now, true)];
u.videos.omitted = [row('/downloads/extra', 'other', 'downloads', now, true)];
u.rebuild();
assert.equal(u.files.length, 200);
assert.equal(u.hiddenCount, 2);
assert.ok(u.files.every(file => !file.omitted));

// A copy represented by another source must not swallow Downloads overflow.
const v = store();
v.pictures.files = [row('/shared/image', 'images', 'images')];
v.downloads.omitted = [row('/shared/image', 'images', 'downloads', now, true)];
v.rebuild();
assert.equal(v.files.length, 1);
assert.equal(v.hiddenCount, 0);
assert.equal(v.freshCount, 1);
v.filter = 'downloads';
v.rebuild();
assert.equal(v.hiddenCount, 1);
assert.equal(v.freshCount, 1);
console.log('Filter regressions passed: time, category, source, expiry, cap and deduplication.');
