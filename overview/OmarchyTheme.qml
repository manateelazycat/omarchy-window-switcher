pragma Singleton
import QtQuick
import qs.Commons as Commons
QtObject {
    readonly property color accent: Commons.Color.accent
    readonly property color accentSoft: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18)
    readonly property color accentBorder: Commons.Color.accent
    readonly property color accentActiveBorder: Commons.Color.accent
    readonly property color tintedBackground: Commons.Color.background
}
