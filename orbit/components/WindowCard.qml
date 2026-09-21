import QtQuick
import Quickshell.Wayland
import qs.Commons

Rectangle {
  id: root

  property var windowData: null
  property int windowIndex: -1
  property bool selected: false
  property bool hoverArmed: false
  property bool previewEnabled: true

  signal selectRequested(int index)
  signal activateRequested(int index)

  radius: Style.cornerRadius
  color: root.selected ? Color.menu.selectedBackground : Color.background
  border.width: root.selected ? 2 : 1
  border.color: root.selected ? Color.accent : Color.menu.border
  clip: true

  Rectangle {
    id: previewFrame

    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      bottom: header.top
      margins: Style.space(8)
      bottomMargin: Style.space(6)
    }
    radius: Math.max(2, Style.cornerRadius - Style.space(3))
    color: Qt.alpha(Color.menu.text, 0.05)
    clip: true

    AppIcon {
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height) * 0.32
      height: width
      iconSource: root.windowData ? root.windowData.iconSource : ""
      fallbackText: root.windowData ? root.windowData.fallbackText : "?"
      opacity: preview.hasContent ? 0 : 0.82
    }

    ScreencopyView {
      id: preview

      anchors.fill: parent
      captureSource: root.previewEnabled && root.windowData ? root.windowData.wayland : null
      paintCursor: false
      live: false
      constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
      opacity: hasContent ? 1 : 0
    }
  }

  Rectangle {
    id: header

    anchors {
      left: parent.left
      right: parent.right
      bottom: parent.bottom
    }
    height: Style.space(38)
    color: root.selected ? Qt.alpha(Color.accent, 0.16) : "transparent"

    AppIcon {
      id: headerIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(21)
      height: width
      iconSource: root.windowData ? root.windowData.iconSource : ""
      fallbackText: root.windowData ? root.windowData.fallbackText : "?"
    }

    Text {
      anchors {
        left: headerIcon.right
        right: parent.right
        leftMargin: Style.space(8)
        rightMargin: Style.space(9)
        verticalCenter: parent.verticalCenter
      }
      text: root.windowData ? root.windowData.label : ""
      textFormat: Text.PlainText
      color: root.selected ? Color.menu.selectedText : Color.menu.text
      elide: Text.ElideRight
      maximumLineCount: 1
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }

  property bool hoverSelect: cardHover.hovered && root.hoverArmed
  onHoverSelectChanged: {
    if (hoverSelect)
      root.selectRequested(root.windowIndex)
  }

  HoverHandler {
    id: cardHover
  }

  TapHandler {
    onTapped: root.activateRequested(root.windowIndex)
  }
}
