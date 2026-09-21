const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

test("manifest exposes every combined plugin entry point", () => {
  const manifest = JSON.parse(read("manifest.json"));
  assert.equal(manifest.id, "io.github.manateelazycat.window-switcher");
  assert.deepEqual(manifest.kinds, ["overlay", "panel", "bar-widget", "service"]);
  for (const entry of Object.values(manifest.entryPoints))
    assert.equal(fs.existsSync(path.join(root, entry)), true, `${entry} is missing`);
  assert.equal(manifest.omarchy.clonedFrom, "omarchy.workspaces");
});

test("Orbit reads settings from the combined plugin entry", () => {
  const source = read("orbit/Overlay.qml");
  assert.match(source, /pluginId: "io\.github\.manateelazycat\.window-switcher"/);
  assert.match(source, /property string mode: "grid"/);
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
