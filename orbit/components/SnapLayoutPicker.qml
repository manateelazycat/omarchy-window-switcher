import QtQuick
import qs.Commons

Grid {
  id: root

  property var layouts: []
  property int selectedLayout: 0
  property int selectedSlot: 0
  property bool interactive: true

  signal slotRequested(int layoutIndex, int slotIndex)
  signal slotHovered(int layoutIndex, int slotIndex)

  columns: 4
  spacing: Style.space(12)

  function hitTest(x, y) {
    for (let index = 0; index < layoutRepeater.count; index++) {
      const tile = layoutRepeater.itemAt(index)
      const slot = tile ? tile.slotAt(root, x, y) : -1
      if (slot >= 0)
        return {
          layout: index,
          slot: slot
        }
    }
    return null
  }

  Repeater {
    id: layoutRepeater
    model: root.layouts

    Rectangle {
      id: layoutTile

      required property int index
      required property var modelData

      readonly property var layoutData: modelData

      function slotAt(item, x, y) {
        for (let index = 0; index < slotRepeater.count; index++) {
          const slot = slotRepeater.itemAt(index)
          const point = slot.mapFromItem(item, x, y)
          if (slot.contains(point))
            return index
        }
        return -1
      }

      width: Style.space(136)
      height: Style.space(108)
      radius: Style.cornerRadius
      color: Color.background
      border.width: root.selectedLayout === index ? 2 : 1
      border.color: root.selectedLayout === index ? Color.accent : Color.menu.border

      Item {
        id: layoutCanvas

        anchors {
          top: parent.top
          left: parent.left
          right: parent.right
          margins: Style.space(10)
        }
        height: Style.space(68)

        Repeater {
          id: slotRepeater
          model: layoutTile.layoutData.slots

          Rectangle {
            id: slotTile

            required property int index
            required property var modelData

            readonly property bool selected: root.selectedLayout === layoutTile.index && root.selectedSlot === index

            x: modelData.x * layoutCanvas.width + Style.space(2)
            y: modelData.y * layoutCanvas.height + Style.space(2)
            width: modelData.width * layoutCanvas.width - Style.space(4)
            height: modelData.height * layoutCanvas.height - Style.space(4)
            radius: Math.max(2, Style.cornerRadius - Style.space(4))
            color: selected || hoverHandler.hovered ? Qt.alpha(Color.accent, selected ? 0.62 : 0.36) : Qt.alpha(Color.menu.text, 0.13)
            border.width: selected ? 2 : 1
            border.color: selected ? Color.accent : Qt.alpha(Color.menu.text, 0.25)

            HoverHandler {
              id: hoverHandler
              enabled: root.interactive
              onHoveredChanged: {
                if (hovered)
                  root.slotHovered(layoutTile.index, slotTile.index)
              }
            }

            TapHandler {
              enabled: root.interactive
              onTapped: root.slotRequested(layoutTile.index, slotTile.index)
            }
          }
        }
      }

      Text {
        anchors {
          bottom: parent.bottom
          bottomMargin: Style.space(8)
          horizontalCenter: parent.horizontalCenter
        }
        text: String(layoutTile.layoutData.label || "Layout")
        color: Color.menu.text
        opacity: 0.72
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
