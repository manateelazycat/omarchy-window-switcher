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

test("Alt+Tab uses the current workspace on one monitor and all local workspaces on multiple monitors", () => {
  const source = read("orbit/Overlay.qml");
  const startSwitcher = source.match(/function startSwitcher\([^]*?\n  function open\(/)?.[0];
  assert.ok(startSwitcher);
  assert.match(startSwitcher, /root\.windowScope = Logic\.altTabScope\(monitorCount\)/);
  assert.match(source, /const workspace = Hyprland\.focusedWorkspace\s+const monitor = Hyprland\.focusedMonitor/);
  assert.match(source, /const focused = root\.screenForMonitorName\(root\.snapshotMonitorName\)/);
  assert.match(source, /root\.prepareFullscreenHandoff\(root\.sourceWindow, selected\)/);

  const vm = require("node:vm");
  const logic = vm.createContext({});
  vm.runInContext(read("orbit/SwitcherLogic.js").replace(/^\.pragma library\s*/, ""), logic);
  assert.equal(logic.altTabScope(1), "monitor");
  assert.equal(logic.altTabScope(2), "monitor-workspaces");
  const eligible = (scope, workspaceId, monitorId, name = String(workspaceId)) =>
    logic.isEligibleWindow({ mapped: true, pinned: false, workspace: { name } },
      workspaceId, "", monitorId, scope, [2, 4], ["DP-1", "HDMI-A-1"], [0, 1],
      2, "DP-1", 0);

  assert.equal(eligible(logic.altTabScope(1), 2, 0), true);
  assert.equal(eligible(logic.altTabScope(1), 3, 0), false);
  assert.equal(eligible(logic.altTabScope(2), 2, 0), true);
  assert.equal(eligible(logic.altTabScope(2), 3, 0), true);
  assert.equal(eligible(logic.altTabScope(2), 4, 1), false);
  assert.equal(eligible(logic.altTabScope(2), -99, 0, "special:scratchpad"), false);
  assert.equal(eligible(logic.altTabScope(2), -99, 0, "special:taskbar-minimized-3-0-0-0-abcd"), true);

  const windows = [{ address: "0x1" }, { address: "0x2" }, { address: "0x3" }];
  assert.equal(logic.initialSelection(windows, 1, "0x2"), 2);
  assert.equal(logic.initialSelection(windows, -1, "0x2"), 0);
  assert.equal(logic.initialSelection([{ address: "0x3" }], 1, ""), 0);
  assert.equal(logic.initialSelection([{ address: "0x3" }], 1, "0x3"), -1);
});

test("Orbit falls back promptly when native activation readiness is unavailable", () => {
  const source = read("orbit/Overlay.qml");
  assert.match(source, /function useActivationReadinessFallback\(reason\)/);
  assert.match(source, /activationSettleTimer\.stop\(\)\s+activationRevealTimer\.restart\(\)/);
  assert.match(source, /activationTargetSurfaceReady \|\| root\.activationReadiness\.startsWith\("fallback-"\)/);
  assert.match(source, /catch \(error\) \{\s+root\.useActivationReadinessFallback\("fallback-unavailable"\)/);
  assert.match(source, /if \(!state\.supported\) \{\s+root\.useActivationReadinessFallback\("fallback-unsupported"\)/);
  assert.match(source, /running: root\.activationCommitInProgress[^\n]+&& !root\.activationReadiness\.startsWith\("fallback-"\)/);
  assert.doesNotMatch(source, /activationCommitSettling && root\.activationReadiness\.startsWith\("fallback-"\)/);
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
  const overviewWidget = read("overview/OverviewWidget.qml");
  assert.doesNotMatch(overviewWidget, /id:\s*workspaceBadge/);
});

test("workspace outlines stay above fullscreen window previews", () => {
  const source = read("overview/OverviewWidget.qml");
  assert.match(source, /property int workspaceBorderZ: windowDraggingZ - 1/);
  assert.match(source, /Repeater \{ \/\/ Workspace entry borders \(on top of windows\)[\s\S]*?z: root\.workspaceBorderZ/);
  assert.doesNotMatch(source, /Workspace entry borders \(on top of windows\)[\s\S]*?z: root\.windowZ\s/);
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

test("Super+Tab puts empty workspaces after occupied ones across monitors", () => {
  const { orderedEntries } = require("../overview/WorkspaceSwitchOrder.js");
  const entries = [
    { id: 10, monitorName: "HDMI-A-2", isEmpty: false },
    { id: 7, monitorName: "HDMI-A-1", isEmpty: false },
    { id: 4, monitorName: "DP-2", isEmpty: false },
    { id: 5, monitorName: "DP-2", isEmpty: false },
    { id: 2, monitorName: "DP-1", isEmpty: false },
    { id: 1, monitorName: "DP-1", isEmpty: true },
    { id: 3, monitorName: "DP-1", isEmpty: true }
  ];

  assert.deepEqual(orderedEntries(entries, 10, 7).map(entry => entry.id),
    [10, 7, 2, 4, 5, 1, 3]);
  assert.deepEqual(orderedEntries(entries, 1, 3).map(entry => entry.id),
    [2, 4, 5, 7, 10, 1, 3]);
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
