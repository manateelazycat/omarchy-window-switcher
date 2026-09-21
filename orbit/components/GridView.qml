import QtQuick
import qs.Commons
import "../SwitcherLogic.js" as Logic

Item {
  id: root

  property var windows: []
  property int selectedIndex: 0
  property bool hoverArmed: false
  property real maximumWidth: Style.space(1240)
  property real maximumHeight: Style.space(720)

  signal selectRequested(int index)
  signal activateRequested(int index)

  readonly property int pageSize: 12
  readonly property int firstIndex: Logic.pageStart(root.selectedIndex, root.pageSize)
  readonly property var pageWindows: root.windows.slice(firstIndex, firstIndex + pageSize)
  readonly property real spacing: Style.space(12)
  readonly property real horizontalCardPadding: Style.space(8)
  readonly property real fixedCardHeight: Style.space(52)
  readonly property var layoutData: Logic.aspectGridLayout(pageWindows, maximumWidth, maximumHeight, spacing, horizontalCardPadding, fixedCardHeight, Style.space(220))

  implicitWidth: layoutData.width
  implicitHeight: layoutData.height

  function navigationTarget(index, direction) {
    if (direction === "left" || direction === "right")
      return Logic.wrapIndex(index + (direction === "left" ? -1 : 1), root.windows.length)
    const localIndex = index - root.firstIndex
    const target = Logic.gridMoveByLayout(localIndex, direction, root.layoutData.items)
    return target < 0 ? index : root.firstIndex + target
  }

  Repeater {
    model: root.layoutData.items

    WindowCard {
      required property var modelData

      x: modelData.x
      y: modelData.y
      width: modelData.width
      height: modelData.height
      windowData: root.pageWindows[modelData.index]
      windowIndex: root.firstIndex + modelData.index
      selected: windowIndex === root.selectedIndex
      hoverArmed: root.hoverArmed
      previewEnabled: true
      onSelectRequested: requestedIndex => root.selectRequested(requestedIndex)
      onActivateRequested: requestedIndex => root.activateRequested(requestedIndex)
    }
  }

  Text {
    visible: root.windows.length > root.pageSize
    anchors.top: parent.bottom
    anchors.topMargin: Style.space(6)
    anchors.horizontalCenter: parent.horizontalCenter
    text: (Math.floor(root.selectedIndex / root.pageSize) + 1) + " / " + Math.ceil(root.windows.length / root.pageSize)
    color: Color.menu.text
    opacity: 0.6
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}
