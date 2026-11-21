// StatusPill.qml -- compact status badge (ok / warning / error / neutral).

import QtQuick
import DragonArm

Rectangle {
    id: pill

    // "ok" | "warning" | "error" | "neutral"
    property string state_: "neutral"
    property string text: ""

    readonly property color tone: state_ === "ok" ? Theme.success
                                 : state_ === "warning" ? Theme.warning
                                 : state_ === "error" ? Theme.danger
                                 : Theme.textMuted

    readonly property color toneSoft: state_ === "ok" ? Theme.successSoft
                                     : state_ === "warning" ? Theme.warningSoft
                                     : state_ === "error" ? Theme.dangerSoft
                                     : Theme.surfaceAlt

    implicitWidth: label.implicitWidth + 30
    implicitHeight: 24
    radius: Theme.radiusSmall
    color: toneSoft
    border.width: 1
    border.color: Theme.fade(tone, 0.45)

    Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        rotation: 45                    // a diamond, not a dot
        color: pill.tone
    }

    Text {
        id: label
        anchors.left: dot.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: pill.text
        color: pill.tone
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTiny
        font.weight: Theme.weightStrong
        font.letterSpacing: 0.6
    }
}
