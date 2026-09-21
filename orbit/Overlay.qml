import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "components"
import "SwitcherLogic.js" as Logic

Item {
  id: root

  readonly property string pluginId: "io.github.manateelazycat.window-switcher"

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool pickerPresented: false
  property bool coverCaptureNeeded: false
  readonly property bool modifierPollingNeeded: root.opened && root.releaseToActivate && root.switcherInputSource !== "native"
  property bool releaseToActivate: false
  property string releaseModifier: ""
  property bool hoverArmed: false
  property point initialPointerPosition: Qt.point(-1, -1)
  property var windows: []
  property int selectedIndex: 0
  property string mode: "grid"
  property string windowScope: "visible"
  readonly property var entries: root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
  property int snapshotWorkspaceId: -1
  property string snapshotMonitorName: ""
  property int snapshotMonitorId: -1
  property var snapshotVisibleWorkspaceIds: []
  property var snapshotVisibleMonitorNames: []
  property var snapshotVisibleMonitorIds: []
  property var targetScreen: null
  property var pendingWindow: null
  property var pendingFullscreenRelease: null
  property var pendingFullscreenRestore: null
  property var rememberedFullscreenStates: ({})
  property var handoffAnimationAddresses: []
  property bool handoffRestoresTargetFirst: false
  property bool handoffNeedsCover: false
  property bool activationCommitInProgress: false
  property bool activationCommitSettling: false
  property bool activationCommitFinalizing: false
  property bool activationTargetSurfaceReady: false
  property bool activationNativeFocusAvailable: false
  property bool activationFocusConfirmed: false
  property int activationCommitAttempts: 0
  property string activationReadiness: "none"
  property int activationGeneration: 0
  readonly property int activationCommitAttemptLimit: 50
  property bool snapshotPending: false
  property bool snapshotCancelled: false
  property bool pendingActivateOnRelease: false
  property string pendingModifier: ""
  property int pendingDirection: 1
  property int queuedSteps: 0
  property bool snapshotRestartPending: false
  property var deferredSwitchGestures: []
  property bool pendingGestureReleased: false
  property string switcherInputSource: "global"
  property bool inputTraceEnabled: false
  property var inputTrace: []
  property var lastHandoff: ({})
  property string managerMode: ""
  property var windowModes: Logic.defaultWindowModes()
  property var settingsDraft: Logic.defaultWindowModes()
  property var snapLayouts: Logic.availableSnapLayouts(root.windowModes)
  property int snapSelectedLayout: 0
  property int snapSelectedSlot: 0
  property var snapTargetWindow: null
  property var snapTargetMonitor: null
  property var snapClientRows: []
  property var snapAssistCandidates: []
  property var snapRemainingSlots: []
  property int snapAssistSelected: 0
  property bool snapActiveReady: false
  property bool snapMonitorReady: false
  property bool snapClientsReady: false
  property var snapRestoreStates: ({})
  property var snapGroups: []
  property var pendingSnapGroup: null
  property var snapAnimationAddresses: []
  property string snapPendingFocusAddress: ""
  property var dragEvent: null
  property var dragState: ({
      visible: false,
      session: 0,
      monitorId: -1,
      anchor: "top"
    })
  property var dragSelection: null
  property int dragShownCount: 0
  property int dragDropCount: 0
  property string dragLastOutcome: "none"
  property bool snapQueryPending: false
  property var snapMonitorRows: []

  function traceInput(action, detail) {
    if (!root.inputTraceEnabled)
      return
    const trace = root.inputTrace.slice(-255)
    trace.push({
      time: Date.now(),
      action: action,
      detail: detail,
      opened: root.opened,
      pending: root.snapshotPending,
      committing: root.activationCommitInProgress,
      selected: root.entries[root.selectedIndex] ? root.entries[root.selectedIndex].address : "",
      released: root.pendingGestureReleased,
      deferred: root.deferredSwitchGestures
    })
    root.inputTrace = trace
  }

  function handleDragEvent(text) {
    let event
    try {
      event = JSON.parse(text)
    } catch (error) {
      return
    }
    if (event.protocol !== 1 || !event.window || !Logic.safeAddress(event.window.address))
      return
    if (event.phase === "end" || event.phase === "cancel") {
      if (event.session !== root.dragState.session)
        return
      const sameMonitor = event.monitor && Number(event.monitor.id) === Number(root.dragState.monitorId)
      const hit = event.phase === "end" && sameMonitor && root.dragState.visible && dragLayer.item ? dragLayer.item.hitTest(event.x, event.y) : null
      root.dragState = Object.assign({}, root.dragState, {
        visible: false
      })
      root.dragLastOutcome = hit ? "dropped" : event.phase === "cancel" ? "cancelled" : "released-outside"
      if (hit) {
        root.snapTargetWindow = event.window
        root.snapTargetMonitor = event.monitor
        root.snapSelectedLayout = hit.layout
        root.snapSelectedSlot = hit.slot
        root.targetScreen = root.screenForMonitorName(event.monitor.name)
        root.dragDropCount++
        root.chooseSnapSlot(hit.layout, hit.slot)
      }
      return
    }
    if (event.phase !== "move" || root.opened || root.activationCommitInProgress || root.managerMode !== "" || root.snapQueryPending)
      return
    const bounds = dragLayer.item ? dragLayer.item.cardGeometry : null
    const next = Logic.dragPresentation(root.dragState, event, bounds)
    if (next.visible && !root.dragState.visible) {
      root.windowModes = root.configuredWindowModes()
      root.dragShownCount++
      root.dragLastOutcome = "shown-during-drag"
      root.windowScope = root.configuredScope()
      root.captureFocusContext()
      root.snapClientRows = []
      if (!snapClientsQuery.running)
        snapClientsQuery.running = true
    }
    if (root.snapLayouts.length === 0)
      next.visible = false
    root.dragEvent = event
    root.dragState = next
    root.dragSelection = next.visible && dragLayer.item ? dragLayer.item.hitTest(event.x, event.y) : null
    dragWatchdog.restart()
  }

  function applicationInfo(applicationClass, initialClass, appId) {
    const originalClass = String(applicationClass || "").trim()
    const rawVariants = [appId, applicationClass, initialClass]
    const variants = []
    for (const rawVariant of rawVariants) {
      const value = String(rawVariant || "").trim().replace(/\.desktop$/i, "")
      const lower = value.toLowerCase()
      const candidates = [value, lower, lower.replace(/-/g, ""), lower.split(".")[0], lower.split(".").pop()]
      for (const candidate of candidates) {
        if (candidate && !variants.includes(candidate))
          variants.push(candidate)
      }
    }

    for (const variant of variants) {
      const entry = DesktopEntries.byId(variant)
      if (entry)
        return desktopEntryInfo(entry, originalClass)
    }

    const applications = DesktopEntries.applications.values || []
    for (const entry of applications) {
      const startupClass = String(entry.startupClass || "").toLowerCase()
      if (startupClass && variants.includes(startupClass))
        return desktopEntryInfo(entry, originalClass)
    }

    for (const variant of variants) {
      const entry = DesktopEntries.heuristicLookup(variant)
      if (entry)
        return desktopEntryInfo(entry, originalClass)
    }

    for (const variant of variants) {
      const icon = Quickshell.iconPath(variant, true)
      if (icon) {
        return {
          id: Logic.normalizeApplicationKey(variant),
          name: Logic.friendlyAppName(originalClass),
          icon: icon,
          fallbackText: Logic.appMonogram(originalClass)
        }
      }
    }

    return {
      id: Logic.normalizeApplicationKey(appId || initialClass || originalClass),
      name: Logic.friendlyAppName(originalClass),
      icon: "",
      fallbackText: Logic.appMonogram(originalClass)
    }
  }

  function desktopEntryInfo(entry, fallbackName) {
    const name = String(entry.name || Logic.friendlyAppName(fallbackName))
    return {
      id: Logic.normalizeApplicationKey(entry.id || fallbackName),
      name: name,
      icon: entry.icon ? Quickshell.iconPath(entry.icon, true) : "",
      fallbackText: Logic.appMonogram(name)
    }
  }

  function screenForMonitorName(monitorName) {
    const screens = Quickshell.screens || []
    for (const screen of screens) {
      if (String(screen.name || "") === String(monitorName || ""))
        return screen
    }
    return null
  }

  function focusedScreen() {
    const screens = Quickshell.screens || []
    const focused = root.screenForMonitorName(root.snapshotMonitorName)
    if (focused)
      return focused
    return screens.length > 0 ? screens[0] : null
  }

  function switcherScreen() {
    const config = root.shell ? root.shell.shellConfig : null
    const monitors = []
    for (const monitor of Hyprland.monitors.values || [])
      monitors.push(monitor)
    const monitorName = Logic.overlayMonitorName(config ? config.plugins : null, root.pluginId, monitors, root.snapshotMonitorName)
    return root.screenForMonitorName(monitorName) || root.focusedScreen()
  }

  function captureFocusContext() {
    const workspace = Hyprland.focusedWorkspace
    const monitor = Hyprland.focusedMonitor
    if (!workspace || !monitor || String(workspace.name || "").startsWith("special:"))
      return false

    root.snapshotWorkspaceId = Number(workspace.id)
    root.snapshotMonitorName = String(monitor.name || "")
    root.snapshotMonitorId = Number(monitor.id)
    const visibleWorkspaceIds = []
    const visibleMonitorNames = []
    const visibleMonitorIds = []
    const monitors = Hyprland.monitors.values || []
    for (const candidateMonitor of monitors) {
      if (root.windowScope === "monitor" && Number(candidateMonitor.id) !== root.snapshotMonitorId)
        continue
      const monitorName = String(candidateMonitor.name || "")
      const monitorId = Number(candidateMonitor.id)
      const activeWorkspace = candidateMonitor.activeWorkspace
      if (monitorName && !visibleMonitorNames.includes(monitorName))
        visibleMonitorNames.push(monitorName)
      if (Number.isFinite(monitorId) && !visibleMonitorIds.includes(monitorId))
        visibleMonitorIds.push(monitorId)
      if (activeWorkspace && Number(activeWorkspace.id) !== 0 && !visibleWorkspaceIds.includes(Number(activeWorkspace.id)))
        visibleWorkspaceIds.push(Number(activeWorkspace.id))
    }
    root.snapshotVisibleWorkspaceIds = visibleWorkspaceIds
    root.snapshotVisibleMonitorNames = visibleMonitorNames
    root.snapshotVisibleMonitorIds = visibleMonitorIds
    root.targetScreen = root.focusedScreen()
    return true
  }

  function snapshotCurrentWindows(clients) {
    if (!Array.isArray(clients))
      return []

    const rows = []
    // Resolve each app once per fresh snapshot. No long-lived icon cache that
    // could outlive desktop-entry or theme changes.
    const applicationsByClass = ({})
    const toplevels = Hyprland.toplevels.values || []
    const toplevelByAddress = ({})
    for (const toplevel of toplevels) {
      const address = Logic.safeAddress(toplevel.address)
      if (address)
        toplevelByAddress[address] = toplevel
    }

    for (const ipc of clients) {
      const address = Logic.safeAddress(ipc.address)
      if (!address || ipc.mapped === false)
        continue
      const toplevel = toplevelByAddress[address] || null
      const minimized = Logic.taskbarMinimizedState(ipc)
      const workspaceId = minimized ? minimized.workspaceId : Number(ipc.workspace ? ipc.workspace.id : -1)
      const monitorName = toplevel && toplevel.monitor ? String(toplevel.monitor.name || "") : ""
      const monitorId = Number(ipc.monitor)

      if (!Logic.isEligibleWindow(ipc, workspaceId, monitorName, monitorId, root.windowScope, root.snapshotVisibleWorkspaceIds, root.snapshotVisibleMonitorNames, root.snapshotVisibleMonitorIds, root.snapshotWorkspaceId, root.snapshotMonitorName, root.snapshotMonitorId)) {
        continue
      }

      const wayland = toplevel ? toplevel.wayland || null : null
      const appId = String(wayland ? wayland.appId || "" : "")
      const initialClass = String(ipc.initialClass || "")
      const applicationClass = String(ipc.class || initialClass || appId || "Application")
      const title = String(ipc.title || (toplevel ? toplevel.title || "" : "") || applicationClass)
      const applicationKey = JSON.stringify([applicationClass, initialClass, appId])
      const application = applicationsByClass[applicationKey] || root.applicationInfo(applicationClass, initialClass, appId)
      applicationsByClass[applicationKey] = application
      const size = Array.isArray(ipc.size) ? ipc.size : []
      rows.push({
        address: address,
        workspaceId: workspaceId,
        monitorName: monitorName,
        monitorId: monitorId,
        appKey: application.id,
        applicationClass: applicationClass,
        appName: application.name,
        iconSource: application.icon,
        fallbackText: application.fallbackText,
        title: title,
        focusHistoryId: Logic.focusHistoryId(ipc.focusHistoryID),
        fullscreenState: Logic.fullscreenState(minimized ? minimized.internal : ipc.fullscreen),
        clientFullscreenState: Logic.fullscreenState(minimized ? minimized.client : ipc.fullscreenClient),
        groupIndex: Logic.groupIndex(ipc.grouped, address),
        pinned: minimized ? minimized.pinned : ipc.pinned === true,
        xwayland: ipc.xwayland === true,
        previewWidth: Number(size[0]) || 16,
        previewHeight: Number(size[1]) || 9,
        positionX: Array.isArray(ipc.at) ? Number(ipc.at[0]) || 0 : 0,
        positionY: Array.isArray(ipc.at) ? Number(ipc.at[1]) || 0 : 0,
        floating: ipc.floating === true,
        toplevel: toplevel,
        wayland: wayland
      })
    }

    return Logic.decorateDuplicateLabels(Logic.sortByRecency(rows))
  }

  function completeWindowQuery(text) {
    root.traceInput("snapshot-result", "")
    if (!root.snapshotPending || root.snapshotRestartPending)
      return
    root.snapshotPending = false
    if (root.snapshotCancelled)
      return
    let clients = []
    try {
      clients = JSON.parse(text)
    } catch (error) {
      console.warn("window-switcher: unable to read current window order:", error)
      return
    }

    const nextWindows = root.snapshotCurrentWindows(clients)
    root.windows = nextWindows
    const nextEntries = root.mode === "icons" ? Logic.applicationEntries(nextWindows) : nextWindows
    if (nextEntries.length < 2)
      return
    const initialIndex = Logic.initialSelection(nextEntries, root.pendingDirection)
    root.selectedIndex = Logic.wrapIndex(initialIndex + root.queuedSteps, nextEntries.length)
    root.releaseToActivate = root.pendingActivateOnRelease
    root.releaseModifier = root.pendingActivateOnRelease ? root.pendingModifier : ""
    root.hoverArmed = false
    root.initialPointerPosition = Qt.point(-1, -1)
    // A gesture released while the query was in flight needs no picker or
    // thumbnail delegates. Only a possible resize needs the passive capture.
    root.pickerPresented = !root.pendingGestureReleased && root.switcherInputSource !== "native"
    const source = nextWindows[0]
    const coverCandidates = root.pendingGestureReleased ? [nextEntries[root.selectedIndex]] : nextWindows
    root.coverCaptureNeeded = coverCandidates.some(target => Logic.needsHandoffCover(source, target, root.rememberedFullscreenStates[target.address], root.windowModes))
    root.opened = true
    watchdog.restart()
    if (root.pendingGestureReleased)
      root.accept()
    else if (!root.pickerPresented)
      pickerPresentationTimer.restart()
  }

  function presentPicker() {
    if (root.opened && !root.activationCommitInProgress && root.releaseToActivate)
      root.pickerPresented = true
  }

  function startSwitcher(activateOnRelease, modifier, direction, inputSource) {
    root.traceInput("start", direction)
    root.mode = root.configuredMode()
    root.windowScope = root.configuredScope()
    root.windowModes = root.configuredWindowModes()
    if (!root.captureFocusContext())
      return
    root.targetScreen = root.switcherScreen()
    root.snapshotPending = true
    root.snapshotCancelled = false
    root.pendingActivateOnRelease = activateOnRelease
    root.pendingModifier = String(modifier || "")
    root.pendingDirection = direction
    root.queuedSteps = 0
    root.pendingGestureReleased = false
    root.pickerPresented = false
    root.coverCaptureNeeded = false
    root.switcherInputSource = inputSource || "global"
    // A cancelled Process can still be delivering its old stdout. Drain that
    // generation before starting another query, never reuse its old snapshot.
    root.snapshotRestartPending = windowQuery.running
    if (!root.snapshotRestartPending)
      windowQuery.running = true
  }

  function open(payloadJson) {
    let payload = {}
    if (payloadJson) {
      try {
        payload = JSON.parse(payloadJson)
      } catch (error) {
        console.warn("window-switcher: invalid invocation payload:", error)
      }
    }
    const action = String(payload.action || "show")
    root.startSwitcher(action === "next" || action === "previous", String(payload.modifier || ""), action === "previous" ? -1 : 1)
  }

  function close() {
    root.cancel()
  }

  function setMode(value) {
    const selected = root.entries[root.selectedIndex]
    const selectedAddress = selected ? selected.address : ""
    const nextMode = Logic.normalizeMode(value)
    root.mode = nextMode
    const nextEntries = root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
    const matchingIndex = Logic.entryIndexForAddress(nextEntries, selectedAddress)
    root.selectedIndex = matchingIndex >= 0 ? matchingIndex : Math.min(root.selectedIndex, Math.max(0, nextEntries.length - 1))
    root.persistPluginSettings({
      mode: nextMode
    })
    return root.mode
  }

  function currentPluginSettings() {
    const config = root.shell ? root.shell.shellConfig : null
    const plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (const plugin of plugins) {
      if (plugin && String(plugin.id || "") === root.pluginId)
        return JSON.parse(JSON.stringify(plugin))
    }
    return {
      id: root.pluginId
    }
  }

  function persistPluginSettings(changes) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function")
      return
    const next = root.currentPluginSettings()
    for (const key in changes)
      next[key] = changes[key]
    next.id = root.pluginId
    root.shell.updateEntryInline(root.pluginId, next)
  }

  function configuredMode() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.modeFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  function configuredScope() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.scopeFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  function configuredWindowModes() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.windowModesFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  onShellChanged: {
    if (root.shell && !root.opened) {
      root.mode = root.configuredMode()
      root.windowScope = root.configuredScope()
      root.windowModes = root.configuredWindowModes()
    }
  }

  function openSettings() {
    if (root.managerMode !== "") {
      root.closeManager()
      return
    }
    root.cancel()
    root.windowScope = root.configuredScope()
    if (!root.captureFocusContext())
      return
    root.windowModes = root.configuredWindowModes()
    root.settingsDraft = Logic.normalizedWindowModes(root.windowModes)
    root.managerMode = "settings"
  }

  function toggleSettingsMode(mode) {
    root.settingsDraft = Logic.toggleWindowMode(root.settingsDraft, mode)
  }

  function setSettingsDefault(mode) {
    const next = Logic.normalizedWindowModes(root.settingsDraft)
    if (next[mode] !== true)
      return
    next.defaultMode = mode
    root.settingsDraft = Logic.normalizedWindowModes(next)
  }

  function applyWindowModeSettings() {
    root.windowModes = Logic.normalizedWindowModes(root.settingsDraft)
    root.persistPluginSettings({
      windowModes: root.windowModes
    })
    root.managerMode = ""
    settingsReload.running = true
  }

  function closeManager() {
    root.snapQueryPending = false
    root.managerMode = ""
    root.snapTargetWindow = null
    root.snapTargetMonitor = null
    root.snapClientRows = []
    root.snapAssistCandidates = []
    root.snapRemainingSlots = []
    root.pendingSnapGroup = null
  }

  function openSnapManager() {
    if (root.snapQueryPending) {
      root.closeManager()
      return
    }
    if (root.managerMode !== "") {
      root.closeManager()
      return
    }
    root.cancel()
    if (snapActiveQuery.running || snapMonitorQuery.running || snapClientsQuery.running || root.activationCommitInProgress)
      return
    root.windowScope = root.configuredScope()
    root.windowModes = root.configuredWindowModes()
    if (root.snapLayouts.length === 0)
      return
    if (!root.captureFocusContext())
      return
    root.snapSelectedLayout = 0
    root.snapSelectedSlot = 0
    root.snapTargetWindow = null
    root.snapTargetMonitor = null
    root.snapClientRows = []
    root.snapAssistCandidates = []
    root.snapRemainingSlots = []
    root.snapActiveReady = false
    root.snapMonitorReady = false
    root.snapClientsReady = false
    root.snapMonitorRows = []
    root.snapQueryPending = true
    snapActiveQuery.running = true
    snapMonitorQuery.running = true
    snapClientsQuery.running = true
  }

  function completeSnapActive(text) {
    if (!root.snapQueryPending)
      return
    try {
      const active = JSON.parse(text)
      const address = Logic.safeAddress(active.address)
      if (address) {
        root.snapTargetWindow = {
          address: address,
          workspaceId: Number(active.workspace ? active.workspace.id : -1),
          monitorId: Number(active.monitor),
          positionX: Array.isArray(active.at) ? Number(active.at[0]) || 0 : 0,
          positionY: Array.isArray(active.at) ? Number(active.at[1]) || 0 : 0,
          previewWidth: Array.isArray(active.size) ? Number(active.size[0]) || 1 : 1,
          previewHeight: Array.isArray(active.size) ? Number(active.size[1]) || 1 : 1,
          fullscreenState: Logic.fullscreenState(active.fullscreen),
          clientFullscreenState: Logic.fullscreenState(active.fullscreenClient),
          floating: active.floating === true
        }
      }
    } catch (error) {
      console.warn("window-switcher: unable to read active window for snap:", error)
    }
    root.snapActiveReady = true
    root.maybeOpenSnapManager()
  }

  function completeSnapMonitors(text) {
    if (!root.snapQueryPending)
      return
    try {
      root.snapMonitorRows = JSON.parse(text)
    } catch (error) {
      console.warn("window-switcher: unable to read monitors for snap:", error)
    }
    root.snapMonitorReady = true
    root.maybeOpenSnapManager()
  }

  function completeSnapClients(text) {
    try {
      root.snapClientRows = root.snapshotCurrentWindows(JSON.parse(text))
    } catch (error) {
      console.warn("window-switcher: unable to read clients for snap:", error)
      root.snapClientRows = []
    }
    root.snapClientsReady = true
    root.maybeOpenSnapManager()
  }

  function maybeOpenSnapManager() {
    if (!root.snapQueryPending || !root.snapActiveReady || !root.snapMonitorReady || !root.snapClientsReady)
      return
    root.snapQueryPending = false
    const monitorId = root.snapTargetWindow ? root.snapTargetWindow.monitorId : -1
    root.snapTargetMonitor = root.snapMonitorRows.find(monitor => Number(monitor.id) === monitorId) || null
    if (!root.snapTargetWindow || !root.snapTargetMonitor) {
      console.warn("window-switcher: snap layouts need an active window and monitor")
      return
    }
    root.targetScreen = root.screenForMonitorName(root.snapTargetMonitor.name)
    root.managerMode = "snap"
  }

  function snapGeometry(layoutIndex, slotIndex) {
    const layout = root.snapLayouts[layoutIndex]
    if (!layout || !layout.slots[slotIndex])
      return null
    const compositorGap = Style.gapsOut * 2
    return Logic.snapGeometry(layout.slots[slotIndex], root.snapTargetMonitor, compositorGap, compositorGap)
  }

  function rememberSnapState(window) {
    if (!window || !window.address || root.snapRestoreStates[window.address])
      return
    const saved = Object.assign({}, root.snapRestoreStates)
    saved[window.address] = {
      x: window.positionX,
      y: window.positionY,
      width: window.previewWidth,
      height: window.previewHeight,
      floating: window.floating,
      fullscreen: window.fullscreenState,
      clientFullscreen: window.clientFullscreenState
    }
    root.snapRestoreStates = saved
  }

  function forgetRememberedFullscreen(address) {
    const safeAddress = Logic.safeAddress(address)
    if (!safeAddress || !root.rememberedFullscreenStates[safeAddress])
      return
    const remembered = Object.assign({}, root.rememberedFullscreenStates)
    delete remembered[safeAddress]
    root.rememberedFullscreenStates = remembered
  }

  function snapWindow(window, layoutIndex, slotIndex) {
    const geometry = root.snapGeometry(layoutIndex, slotIndex)
    const address = window ? Logic.safeAddress(window.address) : ""
    if (!geometry || !address)
      return false
    root.rememberSnapState(window)
    // Snapping is an explicit transition to windowed geometry. Do not let a
    // fullscreen state remembered by an earlier Alt+Tab session override it.
    root.forgetRememberedFullscreen(address)
    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "true", window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.float({ action = "set", window = "address:' + address + '" })')
    // Hyprland keeps a floating window centered while resizing it. Resize first,
    // then apply the absolute position so the selected slot remains exact.
    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + geometry.width + ', y = ' + geometry.height + ', relative = false, window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.move({ x = ' + geometry.x + ', y = ' + geometry.y + ', relative = false, window = "address:' + address + '" })')
    const animationAddresses = root.snapAnimationAddresses.slice()
    if (!animationAddresses.includes(address))
      animationAddresses.push(address)
    root.snapAnimationAddresses = animationAddresses
    snapAnimationRelease.restart()
    root.snapPendingFocusAddress = address
    return true
  }

  function applySnapAction(window, action) {
    const address = window ? Logic.safeAddress(window.address) : ""
    const internalState = action === "maximized" ? 1 : action === "fullscreen" ? 2 : 0
    if (!address || internalState === 0)
      return false
    root.rememberSnapState(window)
    root.forgetRememberedFullscreen(address)
    root.snapGroups = root.snapGroups.filter(group => !group.addresses.includes(address))
    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "true", window = "address:' + address + '" })')
    // An explicit layout choice has the same client state as Super+F/Super+Alt+F.
    // Unlike Alt+Tab, choosing Maximized intentionally exits app fullscreen.
    Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = ' + internalState + ', client = ' + internalState + ', action = "set", window = "address:' + address + '" })')
    const animationAddresses = root.snapAnimationAddresses.slice()
    if (!animationAddresses.includes(address))
      animationAddresses.push(address)
    root.snapAnimationAddresses = animationAddresses
    snapAnimationRelease.restart()
    root.snapPendingFocusAddress = address
    return true
  }

  function chooseSnapSlot(layoutIndex, slotIndex) {
    const layout = root.snapLayouts[layoutIndex]
    if (!layout)
      return
    root.snapSelectedLayout = layoutIndex
    root.snapSelectedSlot = slotIndex
    if (layout.action) {
      if (!root.applySnapAction(root.snapTargetWindow, String(layout.action)))
        return
      root.managerMode = ""
      snapFocusTimer.restart()
      return
    }
    if (!root.snapWindow(root.snapTargetWindow, layoutIndex, slotIndex))
      return
    const remaining = []
    for (let index = 0; index < layout.slots.length; index++) {
      if (index !== slotIndex)
        remaining.push(index)
    }
    root.snapRemainingSlots = remaining
    root.pendingSnapGroup = {
      layoutId: String(layout.id || "layout"),
      workspaceId: root.snapTargetWindow.workspaceId,
      monitorId: root.snapTargetWindow.monitorId,
      addresses: [root.snapTargetWindow.address]
    }
    root.snapAssistCandidates = root.snapClientRows.filter(window => window.address !== root.snapTargetWindow.address && window.workspaceId === root.snapTargetWindow.workspaceId)
    root.snapAssistSelected = 0
    if (remaining.length > 0 && root.snapAssistCandidates.length > 0)
      root.managerMode = "assist"
    else {
      root.managerMode = ""
      snapFocusTimer.restart()
    }
  }

  function chooseSnapAssist(index) {
    if (index < 0 || index >= root.snapAssistCandidates.length || root.snapRemainingSlots.length === 0)
      return
    const candidate = root.snapAssistCandidates[index]
    const slotIndex = root.snapRemainingSlots[0]
    if (!root.snapWindow(candidate, root.snapSelectedLayout, slotIndex))
      return
    const pendingGroup = root.pendingSnapGroup ? Object.assign({}, root.pendingSnapGroup) : null
    if (pendingGroup) {
      pendingGroup.addresses = pendingGroup.addresses.slice()
      pendingGroup.addresses.push(candidate.address)
      root.pendingSnapGroup = pendingGroup
      root.rememberSnapGroup(pendingGroup)
    }
    root.snapRemainingSlots = root.snapRemainingSlots.slice(1)
    root.snapAssistCandidates = root.snapAssistCandidates.filter(window => window.address !== candidate.address)
    root.snapAssistSelected = Math.min(root.snapAssistSelected, Math.max(0, root.snapAssistCandidates.length - 1))
    if (root.snapRemainingSlots.length === 0 || root.snapAssistCandidates.length === 0) {
      root.managerMode = ""
      snapFocusTimer.restart()
    }
  }

  function cycleSnapSlot(step) {
    const layout = root.snapLayouts[root.snapSelectedLayout]
    root.snapSelectedSlot = Logic.wrapIndex(root.snapSelectedSlot + step, layout.slots.length)
  }

  function cycleSnapLayout(step) {
    root.snapSelectedLayout = Logic.wrapIndex(root.snapSelectedLayout + step, root.snapLayouts.length)
    const layout = root.snapLayouts[root.snapSelectedLayout]
    root.snapSelectedSlot = Math.min(root.snapSelectedSlot, layout.slots.length - 1)
  }

  function rememberSnapGroup(group) {
    if (!group || !Array.isArray(group.addresses) || group.addresses.length < 2)
      return
    const addresses = group.addresses.filter(address => Logic.safeAddress(address) !== "")
    if (addresses.length < 2)
      return
    const next = root.snapGroups.filter(existing => !existing.addresses.some(address => addresses.includes(address)))
    next.push({
      layoutId: group.layoutId,
      workspaceId: group.workspaceId,
      monitorId: group.monitorId,
      addresses: addresses
    })
    root.snapGroups = next
  }

  function raiseSnapGroup(address) {
    const safeAddress = Logic.safeAddress(address)
    if (!safeAddress)
      return
    for (const group of root.snapGroups) {
      if (!group.addresses.includes(safeAddress))
        continue
      for (const memberAddress of group.addresses) {
        if (memberAddress === safeAddress)
          continue
        Hyprland.dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + memberAddress + '" })')
      }
      Hyprland.dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + safeAddress + '" })')
      return
    }
  }

  function cycle(step) {
    root.traceInput("cycle", step)
    root.selectedIndex = Logic.wrapIndex(root.selectedIndex + step, root.entries.length)
    watchdog.restart()
  }

  function invokeShortcut(step, inputSource) {
    const source = inputSource || "global"
    root.traceInput(source + "-step", step)
    if (root.activationCommitInProgress || (root.snapshotPending && root.pendingGestureReleased)) {
      const gestures = root.deferredSwitchGestures.slice()
      const last = gestures.length > 0 ? gestures[gestures.length - 1] : null
      if (last && !last.released)
        gestures[gestures.length - 1] = {
          steps: last.steps.concat([step]),
          released: false,
          source: last.source
        }
      else
        gestures.push({
          steps: [step],
          released: false,
          source: source
        })
      root.deferredSwitchGestures = gestures
    } else if (root.opened)
      root.cycle(step)
    else if (root.snapshotPending)
      root.queuedSteps += step
    else
      root.startSwitcher(true, "alt", step, source)
  }

  function observeSwitcherStep(text) {
    try {
      const event = JSON.parse(text)
      if (event.protocol === 1 && (event.step === 1 || event.step === -1))
        root.invokeShortcut(event.step, "native")
    } catch (error) {}
  }

  function observeSwitcherFallback(text) {
    try {
      if (JSON.parse(text).protocol !== 1)
        return
      root.switcherInputSource = "global"
      root.deferredSwitchGestures = root.deferredSwitchGestures.map(gesture => Object.assign({}, gesture, {
          source: "global"
        }))
      if (root.opened) {
        pickerPresentationTimer.stop()
        root.presentPicker()
        watchdog.restart()
      }
    } catch (error) {}
  }

  function observeSwitcherRelease(text) {
    root.traceInput("native-release", "")
    let event
    try {
      event = JSON.parse(text)
    } catch (error) {
      return
    }
    if (event.protocol !== 1)
      return
    const gestures = root.deferredSwitchGestures.slice()
    if (gestures.length > 0) {
      const last = gestures[gestures.length - 1]
      gestures[gestures.length - 1] = {
        steps: last.steps,
        released: true,
        source: last.source
      }
      root.deferredSwitchGestures = gestures
    } else if (root.snapshotPending && root.pendingModifier === "alt") {
      root.pendingGestureReleased = true
    } else if (root.opened && root.releaseToActivate && root.releaseModifier === "alt") {
      root.accept()
    }
  }

  function observeSwitcherCancel(text) {
    root.traceInput("native-cancel", "")
    try {
      if (JSON.parse(text).protocol === 1 && (root.opened || root.snapshotPending || root.deferredSwitchGestures.length > 0))
        root.cancel()
    } catch (error) {}
  }

  function observeModifierState(text) {
    root.traceInput("modifier-poll", text.trim())
    if (!root.opened || !root.releaseToActivate)
      return
    const state = text.trim()
    if (state.endsWith("true"))
      watchdog.restart()
    else if (state.endsWith("false") && root.switcherInputSource !== "native")
      root.accept()
    // A failed IPC query is not proof the user released Alt. The watchdog
    // remains a bounded cancellation fallback if input reporting is broken.
  }

  function releaseModifierExpression() {
    if (root.releaseModifier === "alt")
      return 'error(tostring(hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")))'
    if (root.releaseModifier === "super")
      return 'error(tostring(hl.is_key_down("Super_L") or hl.is_key_down("Super_R")))'
    return "error(false)"
  }

  function select(index) {
    if (index < 0 || index >= root.entries.length)
      return
    root.selectedIndex = index
    watchdog.restart()
  }

  function navigate(direction) {
    if (root.mode !== "grid") {
      root.cycle(direction === "left" || direction === "up" ? -1 : 1)
      return
    }
    const view = switcherLayer.item ? switcherLayer.item.loadedView : null
    if (view && typeof view.navigationTarget === "function")
      root.select(view.navigationTarget(root.selectedIndex, direction))
  }

  function fullscreenSnapshot(window) {
    if (!window)
      return null
    const internalState = Logic.fullscreenState(window.fullscreenState)
    const clientState = Logic.fullscreenState(window.clientFullscreenState)
    if (internalState === 0 && clientState === 0)
      return null
    return {
      address: Logic.safeAddress(window.address),
      internal: internalState,
      client: clientState
    }
  }

  function rememberSourceFullscreen(source) {
    if (!source)
      return
    const address = Logic.safeAddress(source.address)
    if (!address)
      return
    const remembered = Object.assign({}, root.rememberedFullscreenStates)
    const snapshot = root.fullscreenSnapshot(source)
    if (snapshot)
      remembered[address] = snapshot
    else
      delete remembered[address]
    root.rememberedFullscreenStates = remembered
  }

  function prepareFullscreenHandoff(source, selected) {
    root.lastHandoff = ({})
    root.pendingFullscreenRelease = null
    root.pendingFullscreenRestore = null
    root.handoffRestoresTargetFirst = false
    root.handoffNeedsCover = false
    if (!source || !selected)
      return
    const sourceAddress = Logic.safeAddress(source.address)
    const selectedAddress = Logic.safeAddress(selected.address)
    if (!sourceAddress || !selectedAddress || sourceAddress === selectedAddress)
      return
    root.rememberSourceFullscreen(source)
    const desiredInternalState = Logic.desiredWindowState(selected, root.rememberedFullscreenStates[selectedAddress], root.windowModes)
    root.lastHandoff = {
      source: sourceAddress,
      sourceInternal: source.fullscreenState,
      target: selectedAddress,
      targetInternal: selected.fullscreenState,
      targetClient: selected.clientFullscreenState,
      desired: desiredInternalState
    }
    if (desiredInternalState > 0 && Logic.fullscreenState(selected.fullscreenState) !== desiredInternalState) {
      root.pendingFullscreenRestore = {
        address: selectedAddress,
        internal: desiredInternalState,
        client: desiredInternalState === 1 && Logic.fullscreenState(selected.clientFullscreenState) === 0 ? 1 : -1
      }
    }

    if (!Logic.sameWorkspace(source, selected)) {
      if (desiredInternalState > 0 && Logic.fullscreenState(selected.fullscreenState) !== desiredInternalState)
        root.suppressHandoffAnimations([selectedAddress])
      return
    }

    const handoff = Logic.fullscreenHandoffPlan(source.fullscreenState, selected.fullscreenState, desiredInternalState)
    root.handoffRestoresTargetFirst = handoff.restoreTargetBeforeFocus
    root.handoffNeedsCover = handoff.targetResizes
    const suppressAnimations = handoff.releaseSource || handoff.targetResizes
    if (suppressAnimations)
      root.suppressHandoffAnimations([sourceAddress, selectedAddress])

    if (handoff.releaseSource) {
      root.pendingFullscreenRelease = {
        address: sourceAddress
      }
    }
  }

  function suppressHandoffAnimations(addresses) {
    const uniqueAddresses = []
    for (const value of addresses) {
      const address = Logic.safeAddress(value)
      if (!address || uniqueAddresses.includes(address))
        continue
      uniqueAddresses.push(address)
      Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "true", window = "address:' + address + '" })')
    }
    root.handoffAnimationAddresses = uniqueAddresses
  }

  function releaseHandoffAnimations() {
    for (const address of root.handoffAnimationAddresses) {
      Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:' + address + '" })')
    }
    root.handoffAnimationAddresses = []
  }

  function requestPendingActivation() {
    const selected = root.pendingWindow
    if (!selected || activationDispatch.running)
      return
    // Resolve live state and perform the entire handoff on one compositor
    // transaction. Retrying is safe even if a layer unmap restored old focus:
    // no toggle-style -1 sentinel, no parallel Wayland activation request.
    const release = root.pendingFullscreenRelease
    const group = root.snapGroups.find(group => group.addresses.includes(selected.address))
    activationDispatch.command = ["hyprctl", "eval", Logic.activationScript(release ? release.address : "", selected.address, root.lastHandoff.desired, root.handoffRestoresTargetFirst, selected.groupIndex, group ? group.addresses : [])]
    activationDispatch.running = true
  }

  function requestActivationReadiness() {
    if (!root.activationCommitInProgress || root.activationCommitFinalizing || root.activationCommitAttempts === 0 || !root.pendingWindow || activationDispatch.running || activationReadinessQuery.running)
      return
    if ((root.activationTargetSurfaceReady && root.activationFocusConfirmed) || (root.activationCommitSettling && root.activationReadiness.startsWith("fallback-")))
      return
    activationReadinessQuery.generation = root.activationGeneration
    activationReadinessQuery.command = ["hyprctl", "orbit-window-ready", root.pendingWindow.address]
    activationReadinessQuery.running = true
  }

  function raisePendingWindow() {
    const selected = root.pendingWindow
    if (!selected)
      return
    root.raiseSnapGroup(selected.address)
    if (selected.groupIndex > 0) {
      Hyprland.dispatch('hl.dsp.group.active({ window = "address:' + selected.address + '", index = ' + selected.groupIndex + ' })')
    }
    // Keep activation on the ordered compositor IPC path. A foreign-toplevel
    // activate request can overtake the source fullscreen release on Wayland,
    // making Hyprland implicitly clear the browser's client fullscreen state.
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + selected.address + '" })')
    Hyprland.dispatch('hl.dsp.window.bring_to_top()')
  }

  function abortActivationCommit(targetClosed) {
    root.traceInput("abort", "")
    activationDispatch.running = false
    activationReadinessQuery.running = false
    activationCommitTimer.stop()
    activationSettleTimer.stop()
    activationRevealTimer.stop()
    activationFinalizeTimer.stop()
    pickerPresentationTimer.stop()
    root.releaseHandoffAnimations()
    if (!targetClosed)
      console.warn("window-switcher: selected window did not accept focus; keeping Orbit open")
    root.pendingWindow = null
    root.pendingFullscreenRelease = null
    root.pendingFullscreenRestore = null
    root.handoffRestoresTargetFirst = false
    root.handoffNeedsCover = false
    root.activationCommitInProgress = false
    root.activationCommitSettling = false
    root.activationCommitFinalizing = false
    root.activationTargetSurfaceReady = false
    root.activationCommitAttempts = 0
    root.deferredSwitchGestures = []
    root.releaseToActivate = false
    root.releaseModifier = ""
    if (targetClosed) {
      root.opened = false
      root.pickerPresented = false
      watchdog.stop()
      // The target can close after the atomic handoff released the source's
      // fullscreen geometry. Restore that surviving source's original mode.
      const source = root.windows.find(window => window.address === root.lastHandoff.source)
      const mode = Logic.fullscreenState(root.lastHandoff.sourceInternal)
      if (source && mode > 0)
        Hyprland.dispatch('hl.dsp.window.fullscreen_state({internal=' + mode + ',client=-1,action="set",window="address:' + source.address + '"})')
      return
    }
    root.pickerPresented = true
    watchdog.restart()
  }

  function finishActivationCommit() {
    root.traceInput("hide", "")
    if (root.activationCommitFinalizing)
      return
    activationCommitTimer.stop()
    activationSettleTimer.stop()
    activationRevealTimer.stop()
    root.activationCommitFinalizing = true
    root.opened = false
    activationFinalizeTimer.restart()
  }

  function finalizeActivationCommit() {
    root.traceInput("finalize", "")
    activationFinalizeTimer.stop()
    root.releaseHandoffAnimations()
    root.raisePendingWindow()
    root.pendingWindow = null
    root.pendingFullscreenRelease = null
    root.pendingFullscreenRestore = null
    root.handoffRestoresTargetFirst = false
    root.handoffNeedsCover = false
    root.activationCommitInProgress = false
    root.activationCommitSettling = false
    root.activationCommitFinalizing = false
    root.activationTargetSurfaceReady = false
    root.activationCommitAttempts = 0
    const deferred = root.deferredSwitchGestures
    if (deferred.length > 0) {
      const gesture = deferred[0]
      root.deferredSwitchGestures = deferred.slice(1)
      root.startSwitcher(true, "alt", gesture.steps[0], gesture.source)
      root.queuedSteps = gesture.steps.slice(1).reduce((total, step) => total + step, 0)
      root.pendingGestureReleased = gesture.released
    }
  }

  function advanceActivationCommit(fromReadiness) {
    if (!root.activationCommitInProgress || root.activationCommitFinalizing)
      return
    const selected = root.pendingWindow
    if (!selected) {
      root.finishActivationCommit()
      return
    }

    root.activationCommitAttempts++
    if (activationDispatch.running || (!fromReadiness && activationReadinessQuery.running)) {
      if (root.activationCommitAttempts >= root.activationCommitAttemptLimit)
        root.abortActivationCommit()
      return
    }
    if (root.activationCommitAttempts === 1) {
      root.requestPendingActivation()
      return
    }

    const active = Hyprland.activeToplevel
    const selectedIsActive = root.activationNativeFocusAvailable ? root.activationFocusConfirmed : active && Logic.safeAddress(active.address) === Logic.safeAddress(selected.address)
    if (!selectedIsActive) {
      root.requestPendingActivation()
      if (root.activationCommitAttempts < root.activationCommitAttemptLimit)
        return
      root.abortActivationCommit()
      return
    }

    if (root.handoffNeedsCover && !root.activationCommitSettling) {
      activationCommitTimer.stop()
      root.activationCommitSettling = true
      if (root.activationTargetSurfaceReady)
        activationRevealTimer.restart()
      else
        activationSettleTimer.restart()
      return
    }

    root.finishActivationCommit()
  }

  function observeActivationTargetCommit(text, generation) {
    if (!root.activationCommitInProgress || root.activationCommitFinalizing || !root.pendingWindow)
      return
    if (generation !== root.activationGeneration)
      return
    let state
    try {
      state = JSON.parse(text)
    } catch (error) {
      if (root.handoffNeedsCover)
        root.activationReadiness = "fallback-unavailable"
      return
    }
    if (state.protocol !== 1 || Logic.safeAddress(state.address) !== root.pendingWindow.address)
      return
    root.traceInput("native-state", state)
    if (typeof state.active === "boolean") {
      root.activationNativeFocusAvailable = true
      root.activationFocusConfirmed = state.active
    }
    if (!root.handoffNeedsCover || root.activationTargetSurfaceReady) {
      if (root.activationFocusConfirmed && root.activationCommitAttempts > 0)
        root.advanceActivationCommit(true)
      return
    }
    if (!state.supported) {
      root.activationReadiness = "fallback-unsupported"
      return
    }
    const expectedMode = root.pendingFullscreenRestore ? root.pendingFullscreenRestore.internal : 0
    if (state.protocol !== 1 || Logic.safeAddress(state.address) !== root.pendingWindow.address || state.internal !== expectedMode || !state.ready)
      return
    root.activationReadiness = "committed"
    root.activationTargetSurfaceReady = true
    if (root.activationCommitSettling) {
      activationSettleTimer.stop()
      activationRevealTimer.restart()
    } else if (root.activationFocusConfirmed && root.activationCommitAttempts > 0)
      root.advanceActivationCommit(true)
  }

  function finish(activate) {
    root.traceInput("finish", activate)
    if (!root.opened || root.activationCommitInProgress)
      return
    const selected = activate && root.selectedIndex >= 0 ? root.entries[root.selectedIndex] : null
    pickerPresentationTimer.stop()
    watchdog.stop()
    root.releaseToActivate = false
    root.releaseModifier = ""
    if (!selected) {
      root.opened = false
      return
    }
    root.prepareFullscreenHandoff(root.windows.length > 0 ? root.windows[0] : null, selected)
    root.pendingWindow = selected
    root.activationCommitInProgress = true
    root.activationCommitSettling = false
    root.activationCommitFinalizing = false
    root.activationTargetSurfaceReady = false
    root.activationNativeFocusAvailable = false
    root.activationFocusConfirmed = false
    root.activationReadiness = root.handoffNeedsCover ? "waiting" : "not-needed"
    root.activationGeneration++
    root.activationCommitAttempts = 0
    activationCommitTimer.restart()
  }

  function handleClientFullscreen(text) {
    let event
    try {
      event = JSON.parse(text)
    } catch (error) {
      return
    }
    const address = Logic.safeAddress(event.address)
    if (event.protocol !== 1 || !address || event.requested !== false || event.internal !== 0 || event.client !== 0 || event.floating || event.pinned)
      return
    // An app voluntarily leaving media fullscreen is distinct from a user's
    // manual tiling shortcut. Respect the personal default, not a global rule.
    root.forgetRememberedFullscreen(address)
    const modes = root.configuredWindowModes()
    if (!modes.maximized || modes.defaultMode !== "maximized" || root.activationCommitInProgress || root.managerMode !== "" || mediaExitRestore.running)
      return
    mediaExitRestore.command = ["hyprctl", "eval", Logic.mediaExitRestoreScript(address)]
    mediaExitRestore.running = true
  }

  function accept() {
    root.finish(true)
  }

  function cancel() {
    root.deferredSwitchGestures = []
    if (root.snapshotPending) {
      root.snapshotCancelled = true
      root.snapshotPending = false
      root.snapshotRestartPending = false
    }
    root.finish(false)
  }

  function pointerMoved(x, y) {
    if (root.hoverArmed)
      return
    if (root.initialPointerPosition.x < 0) {
      root.initialPointerPosition = Qt.point(x, y)
      return
    }
    const distance = Math.abs(x - root.initialPointerPosition.x) + Math.abs(y - root.initialPointerPosition.y)
    if (distance > 3)
      root.hoverArmed = true
  }

  function pruneClosedWindows() {
    const selected = root.entries[root.selectedIndex]
    const selectedAddress = selected ? selected.address : ""
    const liveAddresses = ({})
    const toplevels = Hyprland.toplevels.values || []
    for (const toplevel of toplevels) {
      const address = Logic.safeAddress(toplevel.address)
      if (address)
        liveAddresses[address] = true
    }
    const nextGroups = []
    for (const group of root.snapGroups) {
      const addresses = group.addresses.filter(address => liveAddresses[address] === true)
      if (addresses.length > 1)
        nextGroups.push(Object.assign({}, group, {
          addresses: addresses
        }))
    }
    root.snapGroups = nextGroups
    for (const property of ["rememberedFullscreenStates", "snapRestoreStates"]) {
      const next = ({})
      for (const address of Object.keys(root[property])) {
        if (liveAddresses[address])
          next[address] = root[property][address]
      }
      root[property] = next
    }
    if (!root.opened)
      return
    const remaining = root.windows.filter(window => liveAddresses[window.address] === true)
    if (remaining.length === root.windows.length)
      return
    root.windows = Logic.decorateDuplicateLabels(remaining)
    if (root.activationCommitInProgress && root.pendingWindow && !liveAddresses[root.pendingWindow.address]) {
      root.abortActivationCommit(true)
      return
    }
    const remainingEntries = root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
    if (remainingEntries.length < 2) {
      root.cancel()
      return
    }
    const matchingIndex = Logic.entryIndexForAddress(remainingEntries, selectedAddress)
    root.selectedIndex = matchingIndex >= 0 ? matchingIndex : Math.min(root.selectedIndex, remainingEntries.length - 1)
  }

  Process {
    id: windowQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: root.completeWindowQuery(text)
    }
  }

  Timer {
    interval: 1
    repeat: true
    running: root.snapshotRestartPending
    onTriggered: {
      if (windowQuery.running)
        return
      root.snapshotRestartPending = false
      windowQuery.running = true
    }
  }

  Process {
    id: snapActiveQuery
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      onStreamFinished: root.completeSnapActive(text)
    }
  }

  Process {
    id: snapMonitorQuery
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      onStreamFinished: root.completeSnapMonitors(text)
    }
  }

  Process {
    id: snapClientsQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: root.completeSnapClients(text)
    }
  }

  Process {
    id: settingsReload
    command: ["hyprctl", "reload"]
  }

  Process {
    id: mediaExitRestore
  }

  Process {
    id: activationDispatch
    onExited: root.requestActivationReadiness()
    stdout: StdioCollector {
      onStreamFinished: root.traceInput("activation-result", text.trim())
    }
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "next"
    description: "Cycle forward through windows on visible monitors"

    onPressed: root.invokeShortcut(1)
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "previous"
    description: "Cycle backward through windows on visible monitors"

    onPressed: root.invokeShortcut(-1)
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "snap"
    description: "Choose a Windows-style snap layout for the active window"

    onPressed: root.openSnapManager()
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "settings"
    description: "Configure Orbit window modes"

    onPressed: root.openSettings()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name === "orbitdrag")
        root.handleDragEvent(event.data)
      else if (event.name === "orbitclientfullscreen")
        root.handleClientFullscreen(event.data)
      else if (event.name === "orbitswitchrelease")
        root.observeSwitcherRelease(event.data)
      else if (event.name === "orbitswitchstep")
        root.observeSwitcherStep(event.data)
      else if (event.name === "orbitswitchfallback")
        root.observeSwitcherFallback(event.data)
      else if (event.name === "orbitswitchcancel")
        root.observeSwitcherCancel(event.data)
    }
  }

  IpcHandler {
    target: "orbit-diagnostics"

    function trace(enabled: bool): string {
      root.inputTraceEnabled = enabled
      root.inputTrace = []
      return enabled ? "enabled" : "disabled"
    }

    function events(): string {
      return JSON.stringify(root.inputTrace)
    }

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        mode: root.mode,
        scope: root.windowScope,
        screen: root.targetScreen ? root.targetScreen.name : "",
        selected: root.entries[root.selectedIndex] ? root.entries[root.selectedIndex].address : "",
        entries: root.entries.map(window => ({
              address: window.address,
              app: window.applicationClass,
              monitor: window.monitorId,
              icon: window.iconSource
            })),
        committing: root.activationCommitInProgress,
        readiness: root.activationReadiness,
        nativeFocus: root.activationNativeFocusAvailable,
        focusConfirmed: root.activationFocusConfirmed,
        resources: {
          pickerRequested: root.opened && root.pickerPresented,
          coverCaptureRequested: root.opened && root.coverCaptureNeeded,
          modifierPolling: root.modifierPollingNeeded
        },
        input: {
          pending: root.snapshotPending,
          released: root.pendingGestureReleased,
          releaseToActivate: root.releaseToActivate,
          modifier: root.releaseModifier,
          source: root.switcherInputSource,
          deferred: root.deferredSwitchGestures
        },
        handoff: root.lastHandoff,
        manager: root.managerMode,
        drag: {
          visible: root.dragState.visible,
          session: root.dragState.session,
          screen: root.dragEvent ? root.dragEvent.monitor.name : "",
          selection: root.dragSelection,
          shown: root.dragShownCount,
          dropped: root.dragDropCount,
          outcome: root.dragLastOutcome
        }
      })
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      root.pruneClosedWindows()
    }
  }

  Timer {
    id: dragWatchdog
    interval: 1000
    onTriggered: root.dragState = Object.assign({}, root.dragState, {
      visible: false
    })
  }

  LazyLoader {
    id: dragLayer
    active: root.dragState.visible && root.dragEvent !== null

    DragSnapOverlay {
      screen: root.screenForMonitorName(root.dragEvent.monitor.name)
      gesture: root.dragEvent
      presentation: root.dragState
      layouts: root.snapLayouts
      selectedLayout: root.dragSelection ? root.dragSelection.layout : -1
      selectedSlot: root.dragSelection ? root.dragSelection.slot : -1
    }
  }

  Timer {
    id: watchdog
    interval: 10000
    // The bridge delivers Alt-up/Escape in order. Holding Alt needs neither
    // periodic subprocesses nor an expiry. Unload explicitly enables fallback.
    onTriggered: {
      if (root.switcherInputSource !== "native" || !root.releaseToActivate)
        root.cancel()
    }
  }

  Timer {
    id: activationCommitTimer
    // Ordinary switches need one frame for the grab to unmap. Resize covers
    // retain their capture head start and the existing bounded retry cadence.
    interval: root.activationCommitAttempts === 0 && !root.handoffNeedsCover ? 16 : 40
    repeat: true
    onTriggered: root.advanceActivationCommit()
  }

  Timer {
    id: activationSettleTimer
    interval: 1600
    onTriggered: {
      root.activationReadiness = "timeout"
      root.finishActivationCommit()
    }
  }

  Process {
    id: activationReadinessQuery
    property int generation: 0
    stdout: StdioCollector {
      onStreamFinished: root.observeActivationTargetCommit(text, activationReadinessQuery.generation)
    }
  }

  Timer {
    interval: 32
    repeat: true
    running: root.activationCommitInProgress && !root.activationCommitFinalizing && !(root.activationTargetSurfaceReady && root.activationFocusConfirmed) && !(root.activationCommitSettling && root.activationReadiness.startsWith("fallback-"))
    onTriggered: root.requestActivationReadiness()
  }

  Timer {
    id: pickerPresentationTimer
    // Native Tab/Alt-up events work before the grab surface exists. A quick
    // tap can therefore activate immediately without flashing a costly picker.
    interval: 75
    onTriggered: root.presentPicker()
  }

  Timer {
    id: activationRevealTimer
    interval: 80
    onTriggered: root.finishActivationCommit()
  }

  Timer {
    id: activationFinalizeTimer
    interval: 32
    onTriggered: root.finalizeActivationCommit()
  }

  Timer {
    id: snapAnimationRelease
    interval: 120
    onTriggered: {
      for (const address of root.snapAnimationAddresses)
        Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:' + address + '" })')
      root.snapAnimationAddresses = []
    }
  }

  Timer {
    id: snapFocusTimer
    interval: 32
    onTriggered: {
      const address = Logic.safeAddress(root.snapPendingFocusAddress)
      root.snapPendingFocusAddress = ""
      if (!address)
        return
      Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
      Hyprland.dispatch("hl.dsp.window.bring_to_top()")
    }
  }

  LazyLoader {
    active: root.managerMode !== ""

    PanelWindow {
      id: managerPanel

      screen: root.targetScreen
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omarchy-orbit-window-manager"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim

        TapHandler {
          onTapped: root.closeManager()
        }
      }

      Rectangle {
        id: managerCard

        anchors.centerIn: parent
        width: root.managerMode === "settings" ? Style.space(560) : root.managerMode === "snap" ? Math.min(managerPanel.width - Style.gapsOut * 2, Style.space(640)) : Math.min(managerPanel.width - Style.gapsOut * 2, Style.space(560))
        height: root.managerMode === "settings" ? Style.space(490) : root.managerMode === "assist" ? Math.min(managerPanel.height - Style.gapsOut * 2, Style.space(570)) : Style.space(360)
        radius: Style.cornerRadius * 2
        color: Color.menu.background
        border.width: 1
        border.color: Color.menu.border
        focus: true

        Keys.onPressed: event => {
          root.traceInput("qml-key", event.key)
          if (event.key === Qt.Key_Escape) {
            root.closeManager()
          } else if (root.managerMode === "snap") {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
              root.cycleSnapSlot(-1)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
              root.cycleSnapSlot(1)
            else if (event.key === Qt.Key_Up)
              root.cycleSnapLayout(-1)
            else if (event.key === Qt.Key_Down)
              root.cycleSnapLayout(1)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
              root.chooseSnapSlot(root.snapSelectedLayout, root.snapSelectedSlot)
            else
              return
          } else if (root.managerMode === "assist") {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
              root.snapAssistSelected = Logic.wrapIndex(root.snapAssistSelected - 1, root.snapAssistCandidates.length)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
              root.snapAssistSelected = Logic.wrapIndex(root.snapAssistSelected + 1, root.snapAssistCandidates.length)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
              root.chooseSnapAssist(root.snapAssistSelected)
            else
              return
          } else {
            return
          }
          event.accepted = true
        }

        Text {
          id: managerHeading

          anchors {
            top: parent.top
            topMargin: Style.space(18)
            horizontalCenter: parent.horizontalCenter
          }
          text: root.managerMode === "settings" ? "Orbit · Window modes" : root.managerMode === "assist" ? "Orbit · Snap Assist" : "Orbit · Snap layouts"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Loader {
          anchors {
            top: managerHeading.bottom
            topMargin: Style.space(16)
            bottom: parent.bottom
            bottomMargin: Style.space(18)
            left: parent.left
            leftMargin: Style.space(20)
            right: parent.right
            rightMargin: Style.space(20)
          }
          sourceComponent: root.managerMode === "settings" ? settingsComponent : root.managerMode === "assist" ? snapAssistComponent : snapPickerComponent
        }

        Component {
          id: snapPickerComponent

          Column {
            spacing: Style.space(14)

            SnapLayoutPicker {
              anchors.horizontalCenter: parent.horizontalCenter
              layouts: root.snapLayouts
              selectedLayout: root.snapSelectedLayout
              selectedSlot: root.snapSelectedSlot
              onSlotHovered: (layoutIndex, slotIndex) => {
                root.snapSelectedLayout = layoutIndex
                root.snapSelectedSlot = slotIndex
              }
              onSlotRequested: (layoutIndex, slotIndex) => {
                root.snapSelectedLayout = layoutIndex
                root.snapSelectedSlot = slotIndex
                root.chooseSnapSlot(layoutIndex, slotIndex)
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Arrows choose · Enter snaps · Esc cancels"
              color: Color.menu.text
              opacity: 0.55
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Component {
          id: settingsComponent

          WindowModeSettings {
            width: parent ? parent.width : 0
            modes: root.settingsDraft
            onToggleRequested: mode => root.toggleSettingsMode(mode)
            onDefaultRequested: mode => root.setSettingsDefault(mode)
            onApplyRequested: root.applyWindowModeSettings()
            onCancelRequested: root.closeManager()
          }
        }

        Component {
          id: snapAssistComponent

          Column {
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: "Pick a window for the next open zone. Continue until the layout is filled, or press Esc."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              color: Color.menu.text
              opacity: 0.65
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            GridView {
              anchors.horizontalCenter: parent.horizontalCenter
              maximumWidth: managerCard.width - Style.space(56)
              maximumHeight: managerCard.height - Style.space(130)
              windows: root.snapAssistCandidates
              selectedIndex: root.snapAssistSelected
              hoverArmed: true
              onSelectRequested: index => root.snapAssistSelected = index
              onActivateRequested: index => {
                root.snapAssistSelected = index
                root.chooseSnapAssist(index)
              }
            }
          }
        }
      }
    }
  }

  LazyLoader {
    id: switcherLayer
    active: root.opened

    Scope {
      readonly property var loadedView: pickerLayer.item ? pickerLayer.item.loadedView : null

      LazyLoader {
        id: pickerLayer
        active: root.pickerPresented

        PanelWindow {
          id: panel
          readonly property var loadedView: viewLoader.item

          // Unmap the actual grab surface at commit. Changing keyboardFocus to
          // None before its initial map can leave a stale exclusive grab in the
          // compositor. Keep the passive cover in a separate sibling window.
          visible: !root.activationCommitInProgress
          screen: root.targetScreen
          anchors {
            top: true
            bottom: true
            left: true
            right: true
          }
          color: "transparent"
          exclusionMode: ExclusionMode.Ignore
          WlrLayershell.namespace: "omarchy-window-switcher"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

          Timer {
            id: modifierPollTimer
            interval: 150
            repeat: true
            // Keep the fallback alive after repeated keys too: layer focus changes
            // can lose the final modifier-release event on multi-monitor setups.
            running: root.modifierPollingNeeded
            onTriggered: {
              if (!modifierCheck.running)
                modifierCheck.running = true
            }
          }

          Process {
            id: modifierCheck
            command: ["hyprctl", "eval", root.releaseModifierExpression()]
            stdout: StdioCollector {
              onStreamFinished: root.observeModifierState(text)
            }
          }

          Rectangle {
            id: switcherScrim

            anchors.fill: parent
            color: Color.menu.scrim

            TapHandler {
              onTapped: root.cancel()
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: mouse => root.pointerMoved(mouse.x, mouse.y)
          }

          Rectangle {
            id: switcherCard

            anchors.centerIn: parent
            width: Math.min(panel.width - Style.gapsOut * 2, Math.max(Style.space(360), viewLoader.width + Style.space(40)))
            height: Math.min(panel.height - Style.gapsOut * 2, viewLoader.height + Style.space(144))
            radius: Style.cornerRadius * 2
            color: Color.menu.background
            border.width: 1
            border.color: Color.menu.border
            focus: true

            Keys.onPressed: event => {
              root.traceInput("qml-switcher-key", event.key)
              if (event.key === Qt.Key_Escape) {
                if (root.switcherInputSource !== "native")
                  root.cancel()
              } else if (event.key === Qt.Key_Q) {
                root.cycle(event.modifiers & Qt.ShiftModifier ? -1 : 1)
              } else if (event.key === Qt.Key_Tab) {
                root.cycle(event.modifiers & Qt.ShiftModifier ? -1 : 1)
              } else if (event.key === Qt.Key_Backtab) {
                root.cycle(-1)
              } else if (event.key === Qt.Key_Right) {
                root.navigate("right")
              } else if (event.key === Qt.Key_Left) {
                root.navigate("left")
              } else if (event.key === Qt.Key_Down) {
                root.navigate("down")
              } else if (event.key === Qt.Key_Up) {
                root.navigate("up")
              } else if (event.key === Qt.Key_1) {
                root.setMode("icons")
              } else if (event.key === Qt.Key_2) {
                root.setMode("flip")
              } else if (event.key === Qt.Key_3) {
                root.setMode("grid")
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.accept()
              } else {
                return
              }
              event.accepted = true
            }

            Keys.onReleased: event => {
              root.traceInput("qml-release", event.key)
              const superReleased = event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
              const altReleased = event.key === Qt.Key_Alt
              const modifierReleased = root.releaseModifier === "alt" ? altReleased : root.releaseModifier === "super" && superReleased
              if (root.releaseToActivate && modifierReleased && root.switcherInputSource !== "native")
                root.accept()
              event.accepted = true
            }

            Text {
              id: heading
              anchors.top: parent.top
              anchors.topMargin: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Orbit · " + (root.mode === "grid" ? "Grid" : root.mode === "flip" ? "Flip" : "Icons")
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Loader {
              id: viewLoader

              anchors.centerIn: parent
              width: item ? item.implicitWidth : 0
              height: item ? item.implicitHeight : 0
              sourceComponent: root.mode === "grid" ? gridViewComponent : root.mode === "flip" ? flipViewComponent : iconsViewComponent
            }

            Component {
              id: iconsViewComponent

              IconsView {
                maximumWidth: panel.width - Style.space(96)
                windows: root.entries
                selectedIndex: root.selectedIndex
                hoverArmed: root.hoverArmed
                onSelectRequested: index => root.select(index)
                onActivateRequested: index => {
                  root.select(index)
                  root.accept()
                }
              }
            }

            Component {
              id: gridViewComponent

              GridView {
                maximumWidth: panel.width - Style.space(96)
                maximumHeight: panel.height - Style.space(190)
                windows: root.entries
                selectedIndex: root.selectedIndex
                hoverArmed: root.hoverArmed
                onSelectRequested: index => root.select(index)
                onActivateRequested: index => {
                  root.select(index)
                  root.accept()
                }
              }
            }

            Component {
              id: flipViewComponent

              FlipView {
                maximumWidth: panel.width - Style.space(96)
                maximumHeight: panel.height - Style.space(190)
                windows: root.entries
                selectedIndex: root.selectedIndex
                hoverArmed: root.hoverArmed
                onSelectRequested: index => root.select(index)
                onActivateRequested: index => {
                  root.select(index)
                  root.accept()
                }
              }
            }

            Text {
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(16)
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width - Style.space(48), Style.space(620))
              text: root.entries[root.selectedIndex] ? root.entries[root.selectedIndex].title : ""
              textFormat: Text.PlainText
              color: Color.menu.text
              opacity: 0.72
              elide: Text.ElideRight
              horizontalAlignment: Text.AlignHCenter
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      LazyLoader {
        active: root.coverCaptureNeeded

        PanelWindow {
          // The picker stays on the primary display, but a resize cover belongs
          // to the outgoing window's display. This window never takes input.
          screen: root.screenForMonitorName(root.windows.length > 0 ? root.windows[0].monitorName : "") || root.targetScreen
          anchors {
            top: true
            bottom: true
            left: true
            right: true
          }
          exclusionMode: ExclusionMode.Ignore
          color: "transparent"
          mask: Region {}
          WlrLayershell.namespace: "omarchy-orbit-handoff"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

          Rectangle {
            id: handoffCover

            anchors.fill: parent
            z: 1000
            opacity: root.activationCommitInProgress && root.handoffNeedsCover && outgoingCapture.hasContent ? 1 : 0
            color: Color.menu.background
            clip: true

            ScreencopyView {
              id: outgoingCapture

              readonly property var captureWindow: root.windows.length > 0 ? root.windows[0] : null
              readonly property real coverScale: sourceSize.width > 0 && sourceSize.height > 0 ? Math.max(handoffCover.width / sourceSize.width, handoffCover.height / sourceSize.height) : 1

              anchors.centerIn: parent
              width: sourceSize.width > 0 ? sourceSize.width * coverScale : handoffCover.width
              height: sourceSize.height > 0 ? sourceSize.height * coverScale : handoffCover.height
              captureSource: captureWindow ? captureWindow.wayland : null
              constraintSize: Qt.size(Math.max(1, handoffCover.width), Math.max(1, handoffCover.height))
              paintCursor: false
              live: false
            }

            ShaderEffectSource {
              anchors.centerIn: parent
              width: outgoingCapture.width
              height: outgoingCapture.height
              sourceItem: outgoingCapture
              hideSource: true
              // A fast Alt release can precede the first captured frame. Keep
              // updating through the capture head start, then freeze before
              // the first activation transaction can resize the source.
              live: !root.activationCommitInProgress || root.activationCommitAttempts === 0
            }
          }
        }
      }
    }
  }
}
