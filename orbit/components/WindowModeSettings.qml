import QtQuick
import qs.Commons

Column {
  id: root

  property var modes: ({})

  signal toggleRequested(string mode)
  signal defaultRequested(string mode)
  signal applyRequested
  signal cancelRequested

  readonly property var rows: [
    {
      key: "tiled",
      label: "Tiled",
      shortcut: "Layout managed",
      canDefault: true
    },
    {
      key: "floating",
      label: "Floating / Snapped",
      shortcut: "Super + T",
      canDefault: true
    },
    {
      key: "maximized",
      label: "Maximized (work area)",
      shortcut: "Super + Alt + F",
      canDefault: true
    },
    {
      key: "maximizeOnSwitch",
      label: "Maximize on switch",
      shortcut: "Normal Alt + Tab targets",
      canDefault: false
    },
    {
      key: "fullscreen",
      label: "Fullscreen",
      shortcut: "Super + F",
      canDefault: false
    },
    {
      key: "tiledFullscreen",
      label: "Tiled content fullscreen",
      shortcut: "Super + Ctrl + F",
      canDefault: false
    }
  ]

  spacing: Style.space(8)

  Text {
    width: parent.width
    text: "Choose the launch default, Alt+Tab behavior, and which Omarchy mode shortcuts remain available. App-requested video and game fullscreen stays allowed."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: Color.menu.text
    opacity: 0.72
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.rows

    Rectangle {
      id: modeRow

      required property var modelData

      readonly property bool modeEnabled: root.modes[modelData.key] === true
      readonly property bool isDefault: root.modes.defaultMode === modelData.key

      width: root.width
      height: Style.space(48)
      radius: Style.cornerRadius
      color: modeEnabled ? Qt.alpha(Color.menu.text, 0.06) : "transparent"
      border.width: 1
      border.color: modeEnabled ? Color.menu.border : Qt.alpha(Color.menu.text, 0.12)

      Rectangle {
        id: checkBox

        anchors {
          left: parent.left
          leftMargin: Style.space(12)
          verticalCenter: parent.verticalCenter
        }
        width: Style.space(22)
        height: width
        radius: Style.space(5)
        color: modeRow.modeEnabled ? Color.accent : "transparent"
        border.width: 1
        border.color: modeRow.modeEnabled ? Color.accent : Color.menu.border

        Text {
          anchors.centerIn: parent
          visible: modeRow.modeEnabled
          text: "✓"
          color: Color.background
          font.bold: true
          font.pixelSize: Style.font.caption
        }

        TapHandler {
          onTapped: root.toggleRequested(String(modeRow.modelData.key))
        }
      }

      Column {
        anchors {
          left: checkBox.right
          leftMargin: Style.space(10)
          verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
          text: String(modeRow.modelData.label)
          color: Color.menu.text
          opacity: modeRow.modeEnabled ? 1 : 0.5
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        Text {
          text: String(modeRow.modelData.shortcut)
          color: Color.menu.text
          opacity: 0.48
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        visible: modeRow.modelData.canDefault
        anchors {
          right: parent.right
          rightMargin: Style.space(10)
          verticalCenter: parent.verticalCenter
        }
        width: Style.space(82)
        height: Style.space(26)
        radius: height / 2
        color: modeRow.isDefault ? Qt.alpha(Color.accent, 0.22) : "transparent"
        border.width: 1
        border.color: modeRow.isDefault ? Color.accent : Color.menu.border

        Text {
          anchors.centerIn: parent
          text: modeRow.isDefault ? "Default" : "Set default"
          color: modeRow.isDefault ? Color.accent : Color.menu.text
          opacity: modeRow.modeEnabled ? 1 : 0.38
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        TapHandler {
          enabled: modeRow.modeEnabled
          onTapped: root.defaultRequested(String(modeRow.modelData.key))
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    spacing: Style.space(8)

    Repeater {
      model: [
        {
          label: "Cancel",
          primary: false
        },
        {
          label: "Apply",
          primary: true
        }
      ]

      Rectangle {
        id: actionButton

        required property var modelData

        width: Style.space(92)
        height: Style.space(32)
        radius: Style.cornerRadius
        color: modelData.primary ? Color.accent : Qt.alpha(Color.menu.text, 0.08)
        border.width: modelData.primary ? 0 : 1
        border.color: Color.menu.border

        Text {
          anchors.centerIn: parent
          text: String(actionButton.modelData.label)
          color: actionButton.modelData.primary ? Color.background : Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          font.bold: actionButton.modelData.primary
        }

        TapHandler {
          onTapped: {
            if (actionButton.modelData.primary)
              root.applyRequested()
            else
              root.cancelRequested()
          }
        }
      }
    }
  }
}
