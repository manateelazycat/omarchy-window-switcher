const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

test("manifest exposes every combined plugin entry point", () => {
  const manifest = JSON.parse(read("manifest.json"));
  const packageMetadata = JSON.parse(read("package.json"));
  assert.equal(manifest.id, "io.github.manateelazycat.window-switcher");
  assert.equal(manifest.version, packageMetadata.version);
  assert.deepEqual(manifest.kinds, ["panel", "bar-widget", "service"]);
  for (const entry of Object.values(manifest.entryPoints))
    assert.equal(fs.existsSync(path.join(root, entry)), true, `${entry} is missing`);
  assert.equal(manifest.omarchy.clonedFrom, "omarchy.workspaces");
});

test("Orbit reads settings from the combined plugin entry", () => {
  const source = read("orbit/Overlay.qml");
  assert.match(source, /pluginId: "io\.github\.manateelazycat\.window-switcher"/);
  assert.match(source, /property string mode: "grid"/);
});

test("the persistent service hosts Orbit so its global shortcuts are registered", () => {
  const source = read("overview/KeybindingService.qml");
  assert.match(source, /import "\.\.\/orbit" as Orbit/);
  assert.match(source, /Orbit\.Overlay\s*\{/);
  assert.match(source, /shell:\s*root\.shell/);
  assert.match(source, /manifest:\s*root\.manifest/);
});

test("switcher previews omit the requested controls and app icons", () => {
  const orbitOverlay = read("orbit/Overlay.qml");
  assert.doesNotMatch(orbitOverlay, /ModePicker\s*\{/);
  assert.doesNotMatch(orbitOverlay, /text:\s*"Orbit · "\s*\+/);
  const overviewWindow = read("overview/OverviewWindow.qml");
  assert.doesNotMatch(overviewWindow, /id:\s*windowIcon/);
  assert.doesNotMatch(overviewWindow, /AppSearch\.iconSource/);
  assert.doesNotMatch(overviewWindow, /symbol:\s*"apps"/);
});

test("Overview defaults to native workspace ordering", () => {
  assert.match(read("overview/GlobalStates.qml"), /overviewSortMode: "system"/);
  assert.match(read("overview/bar/widget.qml"), /setting\("sortMode", "system"\)/);
  assert.match(read("overview/SettingsPanel.qml"), /setting\("sortMode", "system"\)/);

  const vm = require("node:vm");
  const context = vm.createContext({});
  vm.runInContext(read("overview/WorkspaceBarConfig.js"), context);
  const shell = entry => ({ barConfig: { layout: { left: [entry], center: [], right: [] } } });
  assert.equal(context.configuredOverviewMode(shell("io.github.manateelazycat.window-switcher")), "system");
  assert.equal(context.configuredOverviewMode(shell({
    id: "io.github.manateelazycat.window-switcher",
    sortMode: "legacy"
  })), "legacy");
});

test("Super+Tab orders current workspace first and previous workspace second", () => {
  const { orderedEntries } = require("../overview/WorkspaceSwitchOrder.js");
  const entries = [1, 2, 3, 4].map(id => ({ id, isTrailingEmpty: false }));

  assert.deepEqual(
    orderedEntries(entries, 3, 1).map(entry => entry.id),
    [3, 1, 2, 4]
  );
});

test("Super+Tab falls back to the adjacent next workspace", () => {
  const { orderedEntries } = require("../overview/WorkspaceSwitchOrder.js");
  const entries = [1, 2, 3, 4].map(id => ({ id, isTrailingEmpty: false }));

  assert.deepEqual(
    orderedEntries(entries, 3, -1).map(entry => entry.id),
    [3, 4, 1, 2]
  );
  assert.deepEqual(
    orderedEntries(entries, 4, -1).map(entry => entry.id),
    [4, 1, 2, 3]
  );
});

test("Super+Tab ignores unavailable history and keeps creation slots last", () => {
  const { orderedEntries } = require("../overview/WorkspaceSwitchOrder.js");
  const entries = [
    ...[1, 2, 3, 4].map(id => ({ id, isTrailingEmpty: false })),
    { id: 5, isTrailingEmpty: true }
  ];

  assert.deepEqual(
    orderedEntries(entries, 3, 9).map(entry => entry.id),
    [3, 4, 1, 2, 5]
  );
});

test("workspace history records the workspace left behind", () => {
  const source = read("overview/GlobalStates.qml");
  assert.match(source, /property int overviewPreviousWorkspaceId: -1/);
  assert.match(source, /overviewPreviousWorkspaceId = GlobalStates\.overviewCurrentWorkspaceId/);
  assert.match(source, /onFocusedWorkspaceChanged\(\)/);
});

test("shortcut service owns only the two switcher families", () => {
  const source = read("overview/KeybindingService.qml");
  assert.match(source, /hl\.bind\("ALT \+ TAB"/);
  assert.match(source, /hl\.bind\("ALT \+ SHIFT \+ TAB"/);
  assert.match(source, /hl\.bind\("SUPER \+ TAB"/);
  assert.match(source, /hl\.bind\("SUPER \+ SHIFT \+ TAB"/);
  assert.doesNotMatch(source, /commands\.push\('hl\.bind\("SUPER_[LR]"/);
  assert.doesNotMatch(source, /hancoreOverviewSuperListener = hl\.on/);
  assert.doesNotMatch(source, /hancoreOverviewSuperListener|hancoreOverviewSuperDown/);
  assert.match(source, /manateeWindowSwitcherBindingOwner/);
  assert.doesNotMatch(source, /hyprctl[^\n]*reload|reload[^\n]*hyprctl/);
});

test("README credits both upstream projects", () => {
  const source = read("README.md");
  assert.match(source, /rohan-patnaik\/orbit/);
  assert.match(source, /iamcheyan\/omarchy-overview-workspaces/);
  assert.equal(fs.existsSync(path.join(root, "licenses/ORBIT-LICENSE")), true);
  assert.equal(fs.existsSync(path.join(root, "licenses/OVERVIEW-WORKSPACES-LICENSE")), true);
});
