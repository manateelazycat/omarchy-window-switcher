import QtQuick
import qs.Commons

Item {
  id: root

  property var windows: []
  property int selectedIndex: 0
  property bool hoverArmed: false
  property real maximumWidth: Style.space(900)

  signal selectRequested(int index)
  signal activateRequested(int index)

  readonly property real tileWidth: Style.space(112)
  readonly property real tileHeight: Style.space(112)

  implicitWidth: Math.min(root.maximumWidth, iconRow.implicitWidth)
  implicitHeight: root.tileHeight

  function revealSelection() {
    if (root.selectedIndex < 0 || root.selectedIndex >= iconRepeater.count)
      return
    if (flickable.contentWidth <= flickable.width) {
      flickable.contentX = 0
      return
    }
    const item = iconRepeater.itemAt(root.selectedIndex)
    if (!item)
      return
    const left = item.x
    const right = item.x + item.width
    if (left < flickable.contentX)
      flickable.contentX = left
    else if (right > flickable.contentX + flickable.width) {
      flickable.contentX = right - flickable.width
    }
  }

  onSelectedIndexChanged: Qt.callLater(root.revealSelection)
  onWidthChanged: Qt.callLater(root.revealSelection)

  Flickable {
    id: flickable

    anchors.fill: parent
    contentWidth: iconRow.implicitWidth
    contentHeight: iconRow.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width

    Behavior on contentX {
      NumberAnimation {
        duration: 100
      }
    }

    Row {
      id: iconRow
      spacing: Style.space(8)

      Repeater {
        id: iconRepeater
        model: root.windows

        Rectangle {
          id: tile

          required property int index
          required property var modelData

          property bool selected: index === root.selectedIndex
          property bool hoverSelect: hoverHandler.hovered && root.hoverArmed

          width: root.tileWidth
          height: root.tileHeight
          radius: Style.cornerRadius
          color: selected ? Color.menu.selectedBackground : (hoverHandler.hovered ? Qt.alpha(Color.menu.text, 0.08) : "transparent")
          border.width: selected ? 2 : 1
          border.color: selected ? Color.accent : Qt.alpha(Color.menu.border, 0.55)
          scale: selected ? 1 : 0.96

          Behavior on scale {
            NumberAnimation {
              duration: 100
            }
          }

          onHoverSelectChanged: {
            if (hoverSelect)
              root.selectRequested(index)
          }

          AppIcon {
            anchors.top: parent.top
            anchors.topMargin: Style.space(12)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(56)
            height: width
            iconSource: tile.modelData.iconSource
            fallbackText: tile.modelData.fallbackText
            showBackplate: true
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(9)
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            text: tile.modelData.label
            textFormat: Text.PlainText
            color: tile.selected ? Color.menu.selectedText : Color.menu.text
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          HoverHandler {
            id: hoverHandler
          }

          TapHandler {
            onTapped: root.activateRequested(tile.index)
          }
        }
      }
    }
  }
}
