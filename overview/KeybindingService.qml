import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../orbit" as Orbit
import "WorkspaceBarConfig.js" as WorkspaceBarConfig

Item {
    id: root

    // Injected by Omarchy's service loader.
    property var shell: null
    property var manifest: null
    property string appliedMode: ""
    property bool restoring: false
    property bool destroying: false
    property string bindingOwner: ""

    // Omarchy loads only one panel/overlay/menu entry point per plugin and
    // prefers the panel. Host Orbit here so its GlobalShortcuts are always
    // registered alongside the shortcut service.
    Orbit.Overlay {
        shell: root.shell
        manifest: root.manifest
    }

    // Never queue a callback that captures this service. The host destroys and
    // recreates all plugin entry points during a hot reload; an owned Timer is
    // cancelled with this object, while a queued method callback can
    // survive long enough to call into an invalid QML context.
    Timer {
        id: applyBindingsTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!root.destroying)
                root.applyBindings();
        }
    }

    // A config reload can arrive just after we install the runtime bindings.
    // Check the live bindings after it settles, then reinstall only if needed.
    Timer {
        id: reapplyAfterReload
        interval: 850
        repeat: false
        onTriggered: {
            if (!bindingStatusQuery.running)
                bindingStatusQuery.running = true;
        }
    }

    Process {
        id: bindingStatusQuery
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.verifyBindings(text)
        }
    }

    function verifyBindings(output) {
        if (root.destroying || !root.shell || root.appliedMode === "")
            return;
        let bindings;
        try {
            bindings = JSON.parse(output);
        } catch (error) {
            console.warn("Window switcher: could not check Hyprland bindings:", error);
            return;
        }
        const hasBinding = (mask, description) => bindings.some(binding =>
            binding.modmask === mask && String(binding.key).toUpperCase() === "TAB"
                && binding.description === description);
        if (hasBinding(8, "Orbit next window")
                && hasBinding(64, "Overview workspace next"))
            return;
        root.appliedMode = "";
        root.applyBindings();
    }

    // The only key expressions installed below belong to this plugin. Never
    // add a generic SUPER+key observer: it cannot distinguish a standalone
    // Super release from a user shortcut such as Ctrl+Super+V.
    function configuredMode() {
        return WorkspaceBarConfig.configuredOverviewMode(root.shell);
    }

    function migrateLegacyDuplicateWidget() {
        const legacyConfig = WorkspaceBarConfig.legacyShellConfig(root.shell);
        if (!legacyConfig || typeof root.shell.mutateShellConfig !== "function")
            return;
        const configCopy = JSON.parse(JSON.stringify(legacyConfig));
        if (WorkspaceBarConfig.removeDuplicateNativeWidget(configCopy)) {
            root.shell.mutateShellConfig(function(config) {
                WorkspaceBarConfig.removeDuplicateNativeWidget(config);
            });
        }
    }

    // Workspace numbers and the overview navigation chords are the only normal
    // bindings this plugin owns. Do not install generic SUPER+key observers:
    // Hyprland cannot associate an unbind with its original owner, so those
    // observers can interfere with user-defined shortcuts.
    function workspaceNumberCommands(optimized) {
        const commands = [];
        for (let slot = 1; slot <= 10; ++slot) {
            const keycode = slot + 9;
            commands.push(`hl.unbind("SUPER + code:${keycode}")`);
            if (optimized) {
                commands.push(`hl.bind("SUPER + code:${keycode}", hl.dsp.global("quickshell:workspaceSlot${slot}"), { description = "Overview workspace slot ${slot}" })`);
            } else {
                commands.push(`hl.bind("SUPER + code:${keycode}", hl.dsp.focus({ workspace = "${slot}" }), { description = "Switch to workspace ${slot}" })`);
            }
        }
        return commands;
    }

    function nativeWorkspaceNumberCommands() {
        return root.workspaceNumberCommands(false);
    }

    function bindingScript(optimized, ownerToken) {
        const commands = [
            'hl.layer_rule({ name = "overview-instant", match = { namespace = "^quickshell:overview$" }, no_anim = true, animation = "none" })',
            'hl.layer_rule({ name = "window-switcher-instant", match = { namespace = "^(omarchy-window-switcher|omarchy-orbit-handoff)$" }, no_anim = true, animation = "none" })',
            // These are the plugin's own expressions. Do not add unrelated
            // user shortcuts here; unbind has no owner information.
            'hl.unbind("ALT + TAB")',
            'hl.unbind("ALT + SHIFT + TAB")',
            'hl.unbind("SUPER + SUPER_L")',
            'hl.unbind("SUPER + SUPER_R")',
            'hl.unbind("SUPER + TAB")',
            'hl.unbind("SUPER + SHIFT + TAB")'
        ];
        // This local customization deliberately does not bind standalone Super.
        // Super+Tab still opens and cycles the overview; releasing Super commits.
        commands.push('hl.bind("ALT + TAB", hl.dsp.global("omarchy-window-switcher:next"), { repeating = true, description = "Orbit next window" })');
        commands.push('hl.bind("ALT + SHIFT + TAB", hl.dsp.global("omarchy-window-switcher:previous"), { repeating = true, description = "Orbit previous window" })');
        commands.push('hl.bind("SUPER + TAB", hl.dsp.global("quickshell:overviewNext"), { description = "Overview workspace next" })');
        commands.push('hl.bind("SUPER + SHIFT + TAB", hl.dsp.global("quickshell:overviewPrev"), { description = "Overview workspace previous" })');
        commands.push('hl.bind("SUPER + SUPER_L", hl.dsp.global("quickshell:overviewCommit"), { release = true, description = "Overview workspace commit" })');
        commands.push('hl.bind("SUPER + SUPER_R", hl.dsp.global("quickshell:overviewCommit"), { release = true, description = "Overview workspace commit" })');
        commands.push(`_G.manateeWindowSwitcherBindingOwner = "${ownerToken}"`);
        // Native mode does not own Win+number. Never unbind or recreate those
        // keys there; they may be user-defined rather than Omarchy defaults.
        return optimized
            ? commands.concat(root.workspaceNumberCommands(true)).join("; ")
            : commands.join("; ");
    }

    function transitionScript(previousMode, nextMode, ownerToken) {
        const commands = [root.bindingScript(nextMode === "legacy", ownerToken)];
        // Only a live legacy -> system transition proves that these number
        // bindings belong to this service. Restore the native mappings during
        // that handoff; a fresh system-mode start must leave user mappings alone.
        if (WorkspaceBarConfig.requiresNativeWorkspaceNumberRestore(previousMode, nextMode))
            for (const command of root.nativeWorkspaceNumberCommands())
                commands.push(command);
        return commands.join("; ");
    }

    function applyBindings() {
        if (root.destroying || !root.shell)
            return;
        root.migrateLegacyDuplicateWidget();
        const mode = root.configuredMode();
        if (mode === "") {
            if (root.appliedMode !== "") {
                root.restoreBindings();
                root.appliedMode = "";
            }
            return;
        }
        if (root.appliedMode === mode)
            return;
        root.restoring = false;
        root.bindingOwner = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
        Quickshell.execDetached(["hyprctl", "eval", root.transitionScript(root.appliedMode, mode, root.bindingOwner)]);
        root.appliedMode = mode;
    }

    function scheduleApplyBindings() {
        if (!root.destroying)
            applyBindingsTimer.restart();
    }

    function restoreBindings() {
        if (root.restoring)
            return;
        root.restoring = true;
        const ownerToken = root.bindingOwner;
        const commands = [
            `if _G.manateeWindowSwitcherBindingOwner == "${ownerToken}" then _G.manateeWindowSwitcherBindingOwner = nil`,
            'hl.unbind("ALT + TAB")',
            'hl.unbind("ALT + SHIFT + TAB")',
            'hl.unbind("SUPER + SUPER_L")',
            'hl.unbind("SUPER + SUPER_R")',
            'hl.unbind("SUPER + TAB")',
            'hl.unbind("SUPER + SHIFT + TAB")'
        ];
        if (root.appliedMode === "legacy")
            for (const command of root.nativeWorkspaceNumberCommands())
                commands.push(command);
        commands.push('hl.bind("ALT + TAB", hl.dsp.window.cycle_next(), { description = "Focus on next window" })');
        commands.push('hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }), { description = "Focus on previous window" })');
        commands.push('hl.bind("ALT + TAB", hl.dsp.window.bring_to_top(), { description = "Reveal active window on top" })');
        commands.push('hl.bind("ALT + SHIFT + TAB", hl.dsp.window.bring_to_top(), { description = "Reveal active window on top" })');
        commands.push('hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })');
        commands.push('hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })');
        commands.push('end');
        Quickshell.execDetached(["hyprctl", "eval", commands.join("; ")]);
    }

    Component.onCompleted: root.scheduleApplyBindings()
    onShellChanged: root.scheduleApplyBindings()

    Connections {
        target: root.shell
        ignoreUnknownSignals: true
        function onBarConfigChanged() {
            root.scheduleApplyBindings();
        }
        function onShellConfigChanged() {
            root.scheduleApplyBindings();
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event?.name !== "configreloaded")
                return;
            reapplyAfterReload.restart();
        }
    }

    Component.onDestruction: {
        root.destroying = true;
        applyBindingsTimer.stop();
        reapplyAfterReload.stop();
        bindingStatusQuery.running = false;
        root.restoreBindings();
    }
}
