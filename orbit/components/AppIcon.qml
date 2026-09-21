import QtQuick
import Quickshell
import "../SwitcherLogic.js" as Logic

Item {
  id: root

  property string iconSource: ""
  property string fallbackText: "?"
  property bool showBackplate: false

  readonly property bool hasIcon: root.iconSource.length > 0 && artwork.status !== Image.Error
  property real sampledLuminance: 0.5
  readonly property color contrastBackplate: root.sampledLuminance < 0.5 ? "#f5f5f5" : "#171717"

  // ColorQuantizer only opens local files; themed icons use image://icon/.
  // Canvas uses Qt's image loader, including that provider, entirely in memory.
  Canvas {
    id: sampler
    width: 32
    height: 32
    opacity: 0
    visible: root.showBackplate && root.hasIcon
    property string sampleSource: visible ? root.iconSource : ""
    property string previousSource: ""
    onSampleSourceChanged: {
      if (previousSource)
        unloadImage(previousSource)
      previousSource = sampleSource
      root.sampledLuminance = 0.5
      if (sampleSource)
        loadImage(sampleSource)
      requestPaint()
    }
    onImageLoaded: requestPaint()
    onPaint: {
      if (!sampleSource || !isImageLoaded(sampleSource))
        return
      const context = getContext("2d")
      context.clearRect(0, 0, width, height)
      context.drawImage(sampleSource, 0, 0, width, height)
      root.sampledLuminance = Logic.iconLuminance(context.getImageData(0, 0, width, height).data)
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: root.showBackplate || !root.hasIcon
    radius: Math.max(3, width * 0.22)
    color: root.hasIcon ? root.contrastBackplate : "#202020"
    border.width: root.showBackplate ? 1 : 0
    border.color: root.hasIcon && root.sampledLuminance < 0.5 ? "#d5d5d5" : "#303030"
  }

  Image {
    id: artwork
    anchors.centerIn: parent
    width: root.showBackplate ? parent.width * 0.76 : parent.width
    height: root.showBackplate ? parent.height * 0.76 : parent.height
    visible: root.hasIcon
    source: root.iconSource
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    sourceSize.width: Math.max(1, width)
    sourceSize.height: Math.max(1, height)
  }

  Text {
    anchors.centerIn: parent
    visible: !root.hasIcon
    text: root.fallbackText || "?"
    color: "#f5f5f5"
    font.bold: true
    font.pixelSize: Math.max(9, Math.min(parent.width, parent.height) * 0.38)
  }
}
