import QtQuick
import qs.Commons
import "../SwitcherLogic.js" as Logic

Item {
  id: root

  property var windows: []
  property int selectedIndex: 0
  property bool hoverArmed: false
  property real maximumWidth: Style.space(1160)
  property real maximumHeight: Style.space(620)

  signal selectRequested(int index)
  signal activateRequested(int index)

  readonly property real cardWidth: Math.min(Style.space(430), maximumWidth * 0.5)
  readonly property real cardHeight: Math.min(Style.space(282), maximumHeight * 0.68)
  readonly property real horizontalStep: Math.min(Style.space(126), cardWidth * 0.3)
  readonly property int visibleCount: Math.min(windows.length, 7)

  implicitWidth: Math.min(maximumWidth, cardWidth + horizontalStep * Math.max(0, visibleCount - 1))
  implicitHeight: Math.min(maximumHeight, cardHeight + Style.space(92))

  Repeater {
    model: root.windows

    // Keep delegates tied to window identity while selection changes. The old
    // array model recreated every preview (and capture) on every Tab press.
    Loader {
      id: slot

      required property var modelData
      required property int index
      readonly property var offset: Logic.flipOffset(index, root.selectedIndex, root.windows.length, 7)
      active: offset !== null
      z: active ? 100 - Math.abs(offset) * 10 : 0

      sourceComponent: WindowCard {
        id: card

        readonly property int distance: Math.abs(slot.offset || 0)

        width: root.cardWidth
        height: root.cardHeight
        x: (root.width - width) / 2 + (slot.offset || 0) * root.horizontalStep
        y: (root.height - height) / 2 + distance * Style.space(14)
        z: 100 - distance * 10
        scale: 1 - distance * 0.075
        opacity: 1 - distance * 0.16
        windowData: slot.modelData
        windowIndex: slot.index
        selected: slot.index === root.selectedIndex
        hoverArmed: root.hoverArmed
        previewEnabled: true
        transform: Rotation {
          origin.x: card.width / 2
          origin.y: card.height / 2
          axis.x: 0
          axis.y: 1
          axis.z: 0
          angle: -(slot.offset || 0) * 13
        }

        // Selection is immediate. Animating retained cards on every Tab kept
        // the scene rendering for 120 ms per press, even with static captures.

        onSelectRequested: requestedIndex => root.selectRequested(requestedIndex)
        onActivateRequested: requestedIndex => root.activateRequested(requestedIndex)
      }
    }
  }
}
