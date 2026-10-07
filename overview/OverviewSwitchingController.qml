pragma Singleton
pragma ComponentBehavior: Bound
import "."

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool grabbed: false
    property bool focusQueued: false
    property bool cycleQueued: false
    property int cycleDelta: 0
    property int switchSession: 0

    // Focus can move to the preview after Super-up has already been delivered.
    // Check compositor state throughout the gesture so a missed release cannot
    // leave the overview open. One controller owns this across all monitors.
    Timer {
        interval: 150
        repeat: true
        triggeredOnStart: true
        running: GlobalStates.overviewOpen && root.grabbed
        onTriggered: {
            if (!superStateQuery.running)
                superStateQuery.running = true;
        }
    }

    Process {
        id: superStateQuery
        // hyprctl eval does not print return values; a tagged Lua error exposes
        // the boolean and identifies the gesture that started the query.
        command: ["hyprctl", "eval", 'error("overview-super:' + root.switchSession
            + ':" .. tostring(hl.is_key_down("Super_L") or hl.is_key_down("Super_R")))']
        stdout: StdioCollector {
            onStreamFinished: root.observeSuperState(text)
        }
    }

    Timer {
        id: cycleTimer
        interval: 0
        repeat: false
        onTriggered: root.flushCycle()
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: {
            root.focusQueued = false;
            if (GlobalStates.overviewOpen)
                root.requestFocus();
        }
    }

    // Self-register into GlobalStates so the Super-release shortcut (owned by
    // the core qs root singleton) can drive switching mode without a core→module
    // import. Runs only in processes that load this overview module.
    Component.onCompleted: GlobalStates.overviewSwitchingController = root

    signal requestFocus()

    function navigationOpen() {
        return GlobalStates.overviewOpen;
    }

    function observeSuperState(output) {
        if (!GlobalStates.overviewOpen || !root.grabbed)
            return;
        const state = output.trim().match(/overview-super:(\d+):(true|false)$/);
        // Failed queries and results from a previous gesture are not releases.
        if (state && Number(state[1]) === root.switchSession && state[2] === "false")
            root.commitGrabbedMode();
    }

    function flushCycle() {
        cycleTimer.stop();
        const delta = root.cycleDelta;
        root.cycleDelta = 0;
        root.cycleQueued = false;
        if (GlobalStates.overviewOpen && root.grabbed && delta !== 0)
            WorkspaceNavigation.navigateByIndex(delta);
    }

    function queueCycle(dir) {
        root.cycleDelta += dir;
        if (root.cycleQueued)
            return;

        root.cycleQueued = true;
        cycleTimer.restart();
    }

    function queueFocus() {
        if (root.focusQueued)
            return;

        root.focusQueued = true;
        focusTimer.restart();
    }

    function openGrabbedMode(dir) {
        GlobalStates.superReleaseMightTrigger = false;
        if (GlobalStates.overviewOpen && root.grabbed) {
            root.queueCycle(dir);
        } else {
            root.switchSession += 1;
            root.grabbed = true;
            GlobalStates.overviewOpen = true;
            root.queueCycle(dir);
            root.queueFocus();
        }
    }

    function commitGrabbedMode() {
        if (!root.grabbed)
            return;
        // A quick release can beat the zero-delay navigation timer.
        root.flushCycle();
        GlobalStates.superReleaseMightTrigger = false;
        root.grabbed = false;
        WorkspaceNavigation.commitSelectedWorkspace();
        GlobalStates.overviewOpen = false;
    }

    function reset() {
        root.grabbed = false;
        root.focusQueued = false;
        root.cycleQueued = false;
        root.cycleDelta = 0;
        cycleTimer.stop();
        focusTimer.stop();
    }
}
