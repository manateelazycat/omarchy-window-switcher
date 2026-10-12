import QtQuick
import qs.Commons as Commons
Row {
  id: root

  property string currentMode: "grid"

  signal modeRequested(string mode)

  spacing: Commons.Style.space(6)

  Repeater {
    model: ["icons", "flip", "grid"]

    Rectangle {
      id: pill

      required property int index
      required property var modelData

      readonly property bool selected: root.currentMode === modelData

      width: Commons.Style.space(82)
      height: Commons.Style.space(28)
      radius: height / 2
      color: selected ? Commons.Color.menu.selectedBackground : (hoverHandler.hovered ? Qt.alpha(Commons.Color.menu.text, 0.08) : "transparent")
      border.width: selected ? 1 : 0
      border.color: Commons.Color.accent

      Text {
        anchors.centerIn: parent
        text: (pill.index + 1) + "  " + String(pill.modelData).charAt(0).toUpperCase() + String(pill.modelData).slice(1)
        color: pill.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
        opacity: pill.selected || hoverHandler.hovered ? 1 : 0.68
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
      }

      HoverHandler {
        id: hoverHandler
      }

      TapHandler {
        onTapped: root.modeRequested(String(pill.modelData))
      }
    }
  }
}
